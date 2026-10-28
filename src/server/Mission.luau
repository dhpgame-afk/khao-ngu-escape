--!strict
-- Mission: ขั้นตอนภารกิจฝั่งเซิร์ฟเวอร์ — ห้องรอ → ยิงหนังสติ๊ก → อยู่ในภารกิจ
-- - เซิร์ฟเวอร์ตัดสินทุกอย่าง: ใครเป็นหัวห้อง ใครพร้อม จุดลงใช้ได้ไหม · client ส่งได้แค่คำขอ
-- - ช่วงภารกิจ (Phase): Lobby → Launching → InMission → (ชุดถัดไป) Rocket → Results
--   Rocket / Results ยังไม่ทำ แค่เผื่อชื่อไว้ให้ client และโค้ดชุดต่อไป
-- - ผู้เล่นที่เข้าเกมกลางภารกิจ "รอในห้องรอ" จนภารกิจจบ

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local RateLimit = require(script.Parent.RateLimit)
local Lobby = require(script.Parent.Lobby)
local Combat = require(script.Parent.Combat)
local Monkeys = require(script.Parent.Monkeys)

local MissionCfg = Config.Mission
local LaunchCfg = Config.Launch

export type Phase = "Lobby" | "Launching" | "InMission" | "Rocket" | "Results"

type MarkerInfo = { name: string, x: number, z: number }

type Flight = {
	player: Player,
	character: Model,
	root: BasePart,
	startPos: Vector3,
	endPos: Vector3,
}

local Mission = {}

-- ===== สถานะ (อยู่บนเซิร์ฟเวอร์ ไม่เซฟ) =====

local phase: Phase = "Lobby"
local lobbyOrder: { Player } = {} -- ผู้เล่นทุกคนตามลำดับเข้าเกม · คนแรก = หัวห้อง
local participants: { [Player]: boolean } = {} -- คนที่ถูกยิงเข้าภารกิจรอบนี้ (ว่าง = ทุกคนอยู่ห้องรอ)
local readySet: { [Player]: boolean } = {}
local returningSet: { [Player]: boolean } = {} -- กำลังเกิดใหม่หลังจบภารกิจ: ยังไม่นับเป็นคนในห้องรอจนกว่าตัวละครใหม่จะเกิด
local landingX = 0
local landingZ = 0
local landingIsDefault = true -- หัวห้องยังไม่ได้เลือกเอง → ตามกุฏิเมื่อโหลดจุดสำคัญเสร็จ
local missionLanding: Vector3? = nil -- จุดลงจริง (หลัง raycast ลงพื้น) ของภารกิจที่กำลังเล่น
local countdownEndsClock: number? = nil -- os.clock ที่นับถอยหลังครบ (nil = ไม่ได้นับ)
local countdownId = 0 -- เพิ่มทุกครั้งที่เริ่ม/ยกเลิก กัน task.delay เก่ามาทำงานซ้ำ
local launchRunId = 0 -- เพิ่มทุกครั้งที่เริ่ม/ยกเลิกการยิง กันลูปบินเก่าทำงานต่อ
local markerPositions: { [string]: Vector3 } = {}
local markerList: { MarkerInfo } = {} -- ส่งให้ client วาดแผนที่
local stateEvent: RemoteEvent? = nil
local rng = Random.new()

local phaseChangedEvent = Instance.new("BindableEvent")
-- สัญญาณฝั่งเซิร์ฟเวอร์: (newPhase: Phase, oldPhase: Phase) — client ได้ phase ผ่าน RemoteEvent "MissionState"
Mission.PhaseChanged = phaseChangedEvent.Event

-- ===== ตัวช่วย =====

local function isFiniteNumber(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- อยู่ในห้องรอ = ยังอยู่ในเกม ไม่ได้ถูกยิงเข้าภารกิจ
local function isLobbyMember(player: Player): boolean
	return player.Parent == Players
		and not participants[player]
		and not returningSet[player]
		and table.find(lobbyOrder, player) ~= nil
end

local function lobbyMembers(): { Player }
	local list: { Player } = {}
	for _, player in lobbyOrder do
		if isLobbyMember(player) then
			table.insert(list, player)
		end
	end
	return list
end

-- คนที่ร่วมภารกิจได้จริง: ไม่เกิน Config.MaxPlayers คนแรกตามลำดับเข้าเกม (คนเกินรอที่ว่าง)
local function eligibleMembers(): { Player }
	local list: { Player } = {}
	for _, player in lobbyMembers() do
		if #list < Config.MaxPlayers then
			table.insert(list, player)
		end
	end
	return list
end

local function getMissionFolder(): Folder
	local existing = Workspace:FindFirstChild(MissionCfg.ObjectsFolderName)
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = MissionCfg.ObjectsFolderName
	folder.Parent = Workspace
	return folder
end

-- ===== จุดลง =====

-- จุดลงที่ยอมรับ: อยู่ในแมพและห่างขอบอย่างน้อย LandingMarginStuds
local function landingLimits(): (number, number)
	return Config.Map.HalfWidthStuds - Config.Map.LandingMarginStuds,
		Config.Map.HalfDepthStuds - Config.Map.LandingMarginStuds
end

local function isLandingValid(x: number, z: number): boolean
	local limitX, limitZ = landingLimits()
	return math.abs(x) <= limitX and math.abs(z) <= limitZ
end

local function clampLanding(x: number, z: number): (number, number)
	local limitX, limitZ = landingLimits()
	return math.clamp(x, -limitX, limitX), math.clamp(z, -limitZ, limitZ)
end

-- ค่าเริ่มต้น: กุฏิ + ทางใต้ 60 stud (ถ้ายังไม่เจอกุฏิ ใช้กลางแมพ)
local function defaultLanding(): (number, number)
	local kuti = markerPositions["Kuti"]
	local base = if kuti ~= nil then kuti else Vector3.zero
	return clampLanding(base.X + MissionCfg.DefaultLandingOffset.X, base.Z + MissionCfg.DefaultLandingOffset.Z)
end

-- ยิงเรย์ลงหาพื้นที่ (x, z) · ไม่นับห้องรอ ลิง ของภารกิจ และตัวผู้เล่น
local function groundPoint(x: number, z: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	local lobbyInstance = Lobby.getInstance()
	if lobbyInstance ~= nil then
		table.insert(ignore, lobbyInstance)
	end
	local monkeys = Workspace:FindFirstChild("Monkeys")
	if monkeys ~= nil then
		table.insert(ignore, monkeys)
	end
	table.insert(ignore, getMissionFolder())
	for _, player in Players:GetPlayers() do
		if player.Character ~= nil then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local result = Workspace:Raycast(
		Vector3.new(x, LaunchCfg.RaycastStartHeight, z),
		Vector3.new(0, -LaunchCfg.RaycastLength, 0),
		params
	)
	if result ~= nil then
		return result.Position
	end
	local kuti = markerPositions["Kuti"]
	return Vector3.new(x, if kuti ~= nil then kuti.Y else LaunchCfg.FallbackGroundY, z)
end

-- อ่านตำแหน่งจุดสำคัญจาก Workspace.MapMarkers (เซิร์ฟเวอร์เห็นครบ ไม่ติด StreamingEnabled)
local function loadMarkers()
	local folder = Workspace:WaitForChild("MapMarkers", MissionCfg.MarkerWaitSeconds)
	if folder == nil then
		warn(
			"[Mission] ไม่พบ Workspace.MapMarkers — แผนที่ห้องรอจะไม่มีจุดสำคัญ และจุดลงเริ่มต้นใช้กลางแมพ"
		)
		return
	end
	local positions: { [string]: Vector3 } = {}
	local list: { MarkerInfo } = {}
	for _, name in Config.Map.MarkerNames do
		local inst = folder:FindFirstChild(name)
		local position: Vector3? = nil
		if inst ~= nil and inst:IsA("BasePart") then
			position = inst.Position
		elseif inst ~= nil and inst:IsA("Model") then
			position = inst:GetPivot().Position
		end
		if position ~= nil then
			positions[name] = position
			table.insert(list, { name = name, x = position.X, z = position.Z })
		else
			warn("[Mission] ไม่พบจุด " .. name .. " ใน MapMarkers")
		end
	end
	markerPositions = positions
	markerList = list
end

-- ===== ส่งสถานะให้ client =====

local function serverTimeOf(clockValue: number): number
	return Workspace:GetServerTimeNow() + (clockValue - os.clock())
end

-- สถานะที่ส่งให้ผู้เล่นแต่ละคน (ไม่มีข้อมูลลับ: เงิน/ขนมส่งผ่าน DataChanged เท่านั้น)
local function buildSnapshot(forPlayer: Player): { [string]: any }
	local eligible = eligibleMembers()
	local members = {}
	local readyCount = 0
	for _, player in eligible do
		local isReady = readySet[player] == true
		if isReady then
			readyCount += 1
		end
		table.insert(members, { userId = player.UserId, ready = isReady })
	end
	local leader = lobbyOrder[1]
	local endsClock = countdownEndsClock
	return {
		phase = phase,
		inLobby = isLobbyMember(forPlayer),
		eligible = table.find(eligible, forPlayer) ~= nil,
		leaderUserId = if leader ~= nil then leader.UserId else 0,
		landingX = landingX,
		landingZ = landingZ,
		members = members,
		readyCount = readyCount,
		total = #eligible,
		countdownEndsAt = if endsClock ~= nil then serverTimeOf(endsClock) else 0,
		markers = markerList,
	}
end

local function broadcast()
	local event = stateEvent
	if event == nil then
		return
	end
	for _, player in Players:GetPlayers() do
		event:FireClient(player, buildSnapshot(player))
	end
end

local function setPhase(newPhase: Phase)
	local oldPhase = phase
	if newPhase == oldPhase then
		return
	end
	phase = newPhase
	phaseChangedEvent:Fire(newPhase, oldPhase)
	broadcast()
end

local function cancelCountdown()
	countdownId += 1
	countdownEndsClock = nil
end

-- ประกาศไว้ก่อน (นิยามจริงอยู่ส่วน "พร้อม / นับถอยหลัง" ด้านล่าง) เพราะ onCharacterAdded ต้องเรียก
local evaluateCountdown: () -> ()

-- ===== ย้ายผู้เล่น =====
local function teleportCharacter(player: Player, position: Vector3)
	local character = player.Character
	local root = rootOf(player)
	if character == nil or root == nil then
		return
	end
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(CFrame.new(position))
end

local function teleportToLobby(player: Player)
	teleportCharacter(player, Lobby.randomSpawnPosition())
end

local function respawnCharacter(player: Player)
	task.spawn(function()
		local ok, err = pcall(function()
			player:LoadCharacter()
		end)
		if not ok then
			warn("[Mission] เกิดใหม่ไม่สำเร็จ", player.Name, err)
			returningSet[player] = nil -- ไม่ให้ค้างสถานะ "กำลังเกิดใหม่" ตลอดไป
			evaluateCountdown()
			broadcast()
		end
	end)
end

-- ตัวละครเกิดใหม่: ห้องรอ (ปกติ) หรือรอบจุดลง (คนที่อยู่ในภารกิจแล้วเกิดใหม่กลางภารกิจ)
-- TODO(ชุดกลับเข้าแมพ): แทนส่วน "เกิดรอบจุดลง" ด้วยระบบเพื่อนโทรเรียก / หนังสติ๊กยิงตัวหลัง 40 วิ
local function onCharacterAdded(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root == nil or not root:IsA("BasePart") or character.Parent == nil then
		if returningSet[player] then
			returningSet[player] = nil
			broadcast()
		end
		return
	end
	local landing = missionLanding
	if participants[player] and landing ~= nil then
		local scatter = MissionCfg.RespawnScatterStuds
		local spot = landing
			+ Vector3.new(
				rng:NextNumber(-scatter, scatter),
				LaunchCfg.LandingRootHeight,
				rng:NextNumber(-scatter, scatter)
			)
		teleportCharacter(player, spot)
	else
		teleportToLobby(player)
	end
	if returningSet[player] then
		-- ตัวละครใหม่เกิดที่ห้องรอแล้ว: กลับมานับเป็นคนในห้องรอ (ยังไม่พร้อม → ถ้ากำลังนับถอยหลังอยู่ให้ยกเลิก)
		returningSet[player] = nil
		evaluateCountdown()
		broadcast()
	end
end

-- ===== จบภารกิจ =====

-- พาทุกคนกลับห้องรอและรีเซ็ตทุกอย่าง
-- TODO(ชุดบั้งไฟ): ให้ระบบบั้งไฟ/สรุปผลเรียกตอนจบภารกิจ (ตอนนี้เรียกแค่เมื่อผู้เล่นในภารกิจออกหมด)
function Mission.endMission()
	launchRunId += 1 -- หยุดลูปบินที่ค้างอยู่
	cancelCountdown()

	local returning: { Player } = {}
	for player in participants do
		table.insert(returning, player)
	end
	participants = {}
	readySet = {}
	missionLanding = nil
	landingX, landingZ = defaultLanding()
	landingIsDefault = true
	getMissionFolder():ClearAllChildren() -- ตะกร้าและของภารกิจ

	Monkeys.resetAll()

	-- เปลี่ยนเป็น Lobby ก่อนเกิดใหม่ เพื่อให้ onCharacterAdded ส่งทุกคนเข้าห้องรอ
	setPhase("Lobby")
	for _, player in returning do
		Combat.setLocked(player, true)
		local root = rootOf(player)
		if root ~= nil then
			root.Anchored = false -- เผื่อจบกลางอากาศ
		end
		returningSet[player] = true
		respawnCharacter(player) -- ตัวละครใหม่ = เลือด/สถานะ/แม็กสดใหม่
	end
	broadcast()
end

-- ===== ยิงหนังสติ๊ก =====

local function launchStillValid(runId: number): boolean
	return runId == launchRunId and phase == "Launching"
end

-- จุดบนเส้นโค้ง: เส้นตรงจากถุงถึงจุดลง + ยกขึ้นเป็นพาราโบลา (สูงสุดตรงกลางทาง)
local function arcPosition(startPos: Vector3, endPos: Vector3, alpha: number): Vector3
	local onLine = startPos:Lerp(endPos, alpha)
	return onLine + Vector3.new(0, LaunchCfg.ArcPeakHeight * 4 * alpha * (1 - alpha), 0)
end

local function spawnBasket(landing: Vector3)
	local ground = groundPoint(landing.X + LaunchCfg.BasketOffset.X, landing.Z + LaunchCfg.BasketOffset.Z)
	local basket = Instance.new("Part")
	basket.Name = "FoodBasket"
	basket.Size = LaunchCfg.BasketSize
	basket.Color = LaunchCfg.BasketColor
	basket.Material = Enum.Material.Wood
	basket.Anchored = true -- TODO(ชุดถือของ): ปลดเมื่อผู้เล่นหยิบ/วางได้
	basket.Position = ground + Vector3.new(0, LaunchCfg.BasketSize.Y / 2, 0)
	basket.Parent = getMissionFolder()

	-- ป้ายลอยเหนือตะกร้า ให้หาเจอบนแมพใหญ่
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(6, 2) -- หน่วย stud
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = basket
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = "ตะกร้าอาหาร"
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.Parent = billboard
end

-- ทำงานในเธรดแยก: ย้ายเข้าถุง → รอ → บินตามโค้ง → ลงพื้น → เข้าภารกิจ
local function runLaunch(runId: number, passengers: { Player })
	local count = #passengers
	local offsets: { number } = {}
	for i = 1, count do
		offsets[i] = (i - (count + 1) / 2) * LaunchCfg.SpreadStuds
	end

	local landingGround = groundPoint(landingX, landingZ)
	missionLanding = landingGround
	local pouchCf = Lobby.getPouchStandCFrame()
	local toLanding = Vector3.new(landingGround.X - pouchCf.Position.X, 0, landingGround.Z - pouchCf.Position.Z)
	local facing = if toLanding.Magnitude > 0.1 then toLanding.Unit else Vector3.new(0, 0, 1)

	-- 1) ย้ายทุกคนเข้าถุง ตรึงตัว (Anchored) แล้วคำนวณจุดลงของแต่ละคน
	local flights: { Flight } = {}
	for i, player in passengers do
		Combat.refillFirecrackers(player)
		local character = player.Character
		local root = rootOf(player)
		if character ~= nil and root ~= nil then
			local startPos = pouchCf:PointToWorldSpace(Vector3.new(offsets[i], 0, 0))
			local endGround = groundPoint(landingX + offsets[i], landingZ)
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = CFrame.lookAt(startPos, startPos + facing)
			root.Anchored = true
			table.insert(flights, {
				player = player,
				character = character,
				root = root,
				startPos = startPos,
				endPos = endGround + Vector3.new(0, LaunchCfg.LandingRootHeight, 0),
			})
		end
	end

	-- เริ่มภารกิจใหม่: ลิงเกิดใหม่ครบทุกรัง (resetAll ล้างลิงเก่าและรีเซ็ตสถานะรังด้วย) + ตะกร้าอาหาร 1 ใบ
	Monkeys.resetAll()
	getMissionFolder():ClearAllChildren()
	spawnBasket(landingGround)

	-- ระหว่างรอ ขอให้ client ของแต่ละคนโหลดแมพรอบจุดลงล่วงหน้า (StreamingEnabled) ทุกคนพร้อมกัน
	-- แล้วรอจนโหลดเสร็จหรือหมดเวลา ก่อนบิน/ปล่อยตัว กันลงบนพื้นที่ยังไม่โหลด (ตกทะลุพื้น)
	local pendingStreams = #flights
	for _, flight in flights do
		task.spawn(function()
			local ok, err = pcall(function()
				flight.player:RequestStreamAroundAsync(landingGround, LaunchCfg.StreamTimeoutSeconds)
			end)
			if not ok then
				warn("[Mission] RequestStreamAroundAsync ล้มเหลว", flight.player.Name, err)
			end
			pendingStreams -= 1
		end)
	end
	local prepEndsAt = os.clock() + LaunchCfg.PrepSeconds
	local streamGiveUpAt = os.clock() + LaunchCfg.StreamTimeoutSeconds + 1
	while launchStillValid(runId) do
		local now = os.clock()
		local prepDone = now >= prepEndsAt
		local streamDone = pendingStreams <= 0 or now >= streamGiveUpAt
		if prepDone and streamDone then
			break
		end
		task.wait(0.1)
	end
	if not launchStillValid(runId) then
		return
	end

	-- 2) บินตามโค้งโดยขยับ HumanoidRootPart ที่ถูกตรึง (ไม่พึ่งฟิสิกส์ จึงไม่ติดภูมิประเทศ)
	local elapsed = 0
	while elapsed < LaunchCfg.FlightSeconds do
		local dt = RunService.Heartbeat:Wait()
		if not launchStillValid(runId) then
			return
		end
		elapsed += dt
		local alpha = math.min(elapsed / LaunchCfg.FlightSeconds, 1)
		for _, flight in flights do
			if flight.root.Parent ~= nil and flight.player.Character == flight.character then
				local position = arcPosition(flight.startPos, flight.endPos, alpha)
				flight.root.CFrame = CFrame.lookAt(position, position + facing)
			end
		end
	end

	-- 3) ลงพื้น: ปล่อยตัว (ไม่มีดาเมจตกจากที่สูง เพราะเกมไม่มีระบบเสียเลือดจากการตก)
	for _, flight in flights do
		if flight.root.Parent ~= nil and flight.player.Character == flight.character then
			flight.root.CFrame = CFrame.lookAt(flight.endPos, flight.endPos + facing)
			flight.root.AssemblyLinearVelocity = Vector3.zero
			flight.root.Anchored = false
		end
	end
	for _, player in passengers do
		if participants[player] then
			Combat.setLocked(player, false)
		end
	end
	setPhase("InMission")
end

local function startLaunch()
	local passengers = eligibleMembers()
	-- ทุกคนต้องมีตัวละครพร้อม (ปกติผ่านเสมอเพราะกดพร้อมได้ต่อเมื่อมีตัวละคร)
	for _, player in passengers do
		if rootOf(player) == nil then
			readySet[player] = nil
			broadcast()
			return
		end
	end
	if #passengers == 0 then
		return
	end

	launchRunId += 1
	local runId = launchRunId
	cancelCountdown()
	participants = {}
	for _, player in passengers do
		participants[player] = true
		Combat.setLocked(player, true)
	end
	readySet = {}
	setPhase("Launching")

	-- ถ้าลำดับยิงพัง/ค้าง ต้องไม่ปล่อยให้ผู้เล่นถูกตรึงอยู่ที่ Launching ตลอดไป → ยกเลิกภารกิจพากลับห้องรอ
	local function abortIfStuck(reason: string)
		if runId == launchRunId and phase == "Launching" then
			warn("[Mission] ยกเลิกการยิงหนังสติ๊ก:", reason)
			Mission.endMission()
		end
	end
	task.spawn(function()
		local ok, err = pcall(runLaunch, runId, passengers)
		if not ok then
			abortIfStuck(tostring(err))
		end
	end)
	-- ตัวเฝ้า: เวลารวมสูงสุด = เตรียม/โหลดแมพ + บิน + เผื่อ
	local watchdogSeconds = LaunchCfg.PrepSeconds
		+ LaunchCfg.StreamTimeoutSeconds
		+ LaunchCfg.FlightSeconds
		+ LaunchCfg.WatchdogExtraSeconds
	task.delay(watchdogSeconds, function()
		abortIfStuck("ค้างเกินเวลา")
	end)
end

-- ===== พร้อม / นับถอยหลัง =====

local function allReady(): boolean
	local eligible = eligibleMembers()
	if #eligible < MissionCfg.MinPlayers then
		return false
	end
	for _, player in eligible do
		if not readySet[player] then
			return false
		end
	end
	return true
end

-- ตรวจใหม่ทุกครั้งที่ใครกดพร้อม/ยกเลิก/เข้า/ออก: ทุกคนพร้อม → เริ่มนับ · ไม่ครบ → ยกเลิกการนับ
function evaluateCountdown()
	if phase ~= "Lobby" then
		return
	end
	local ready = allReady()
	if ready and countdownEndsClock == nil then
		countdownId += 1
		local myId = countdownId
		countdownEndsClock = os.clock() + MissionCfg.ReadyCountdownSeconds
		task.delay(MissionCfg.ReadyCountdownSeconds, function()
			if myId ~= countdownId or phase ~= "Lobby" then
				return
			end
			countdownEndsClock = nil
			if allReady() then
				startLaunch()
			else
				broadcast()
			end
		end)
	elseif not ready and countdownEndsClock ~= nil then
		cancelCountdown()
	end
end

-- ===== คำขอจาก client (ตรวจทุกค่า ไม่เชื่อ client) =====

local function onSetReady(player: Player, value: any)
	if not RateLimit.allow(player, "MissionSetReady", MissionCfg.ReadyMinIntervalSeconds) then
		return
	end
	if type(value) ~= "boolean" then
		return
	end
	if phase ~= "Lobby" or not isLobbyMember(player) then
		return
	end
	if table.find(eligibleMembers(), player) == nil then
		return -- ห้องเต็ม รอที่ว่าง
	end
	if value and rootOf(player) == nil then
		return -- ตัวละครยังไม่พร้อม
	end
	readySet[player] = if value then true else nil
	evaluateCountdown()
	broadcast()
end

local function onSetLanding(player: Player, x: any, z: any)
	if not RateLimit.allow(player, "MissionSetLanding", MissionCfg.LandingMinIntervalSeconds) then
		return
	end
	if phase ~= "Lobby" or player ~= lobbyOrder[1] then
		return -- เฉพาะหัวห้องเท่านั้น
	end
	if countdownEndsClock ~= nil then
		return -- ระหว่างนับถอยหลังห้ามเปลี่ยน (ทุกคนพร้อมกับจุดเดิมแล้ว)
	end
	if not isFiniteNumber(x) or not isFiniteNumber(z) then
		return
	end
	if not isLandingValid(x, z) then
		return
	end
	if x == landingX and z == landingZ then
		return -- ไม่ได้เปลี่ยน
	end
	landingX, landingZ = x, z
	landingIsDefault = false
	-- จุดลงเปลี่ยน = ทุกคนต้องกดพร้อมใหม่ (กันคนที่กดพร้อมไว้ก่อนถูกยิงไปจุดที่ไม่ได้เห็น)
	readySet = {}
	evaluateCountdown()
	broadcast()
end

-- ===== ผู้เล่นเข้า/ออก =====

local function registerPlayer(player: Player)
	if table.find(lobbyOrder, player) ~= nil then
		return
	end
	table.insert(lobbyOrder, player)
	Combat.setLocked(player, true) -- ผู้เล่นใหม่เริ่มที่ห้องรอ ยิงไม่ได้ จนกว่าจะถูกยิงเข้าแมพ

	-- ให้เกิดที่แผ่นเกิดห้องรอเลย (ถ้าห้องของเจ้าของใช้ Part ธรรมดา ตั้งไม่ได้ → onCharacterAdded เทเลพอร์ตให้แทน)
	local spawnLocation = Lobby.getSpawnLocation()
	if spawnLocation ~= nil then
		pcall(function()
			player.RespawnLocation = spawnLocation
		end)
	end

	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	if player.Character ~= nil then
		task.spawn(onCharacterAdded, player, player.Character)
	end

	evaluateCountdown() -- คนใหม่ยังไม่พร้อม → ยกเลิกการนับถอยหลังถ้ากำลังนับ
	broadcast()
end

local function onPlayerRemoving(player: Player)
	local index = table.find(lobbyOrder, player)
	if index ~= nil then
		table.remove(lobbyOrder, index) -- หัวห้องออก → คนถัดไปในลำดับเป็นหัวห้องเอง
	end
	readySet[player] = nil
	participants[player] = nil
	returningSet[player] = nil
	cancelCountdown() -- ใครออก = ยกเลิกการนับถอยหลัง (ถ้าที่เหลือพร้อมครบ จะเริ่มนับใหม่)

	if phase ~= "Lobby" and next(participants) == nil then
		Mission.endMission() -- ผู้เล่นในภารกิจออกหมดแล้ว
		return
	end
	evaluateCountdown()
	broadcast()
end

-- ผู้เล่นในห้องรอที่ตกแท่น/หลุดออกนอกห้อง → พากลับจุดเกิด
local function startBoundsLoop()
	task.spawn(function()
		while true do
			task.wait(Config.Lobby.BoundsCheckSeconds)
			for _, player in Players:GetPlayers() do
				if isLobbyMember(player) then
					local root = rootOf(player)
					if root ~= nil and not root.Anchored and Lobby.isOutside(root.Position) then
						teleportToLobby(player)
					end
				end
			end
		end
	end)
end

-- ===== API ให้ระบบอื่น =====

function Mission.getPhase(): Phase
	return phase
end

-- ใช้ร้านค้า/แลกขนมได้ไหม: ต้องอยู่ช่วงห้องรอ และผู้เล่นคนนี้อยู่ในห้องรอ
function Mission.isInLobby(player: Player): boolean
	return phase == "Lobby" and isLobbyMember(player)
end

function Mission.init()
	Lobby.build()
	landingX, landingZ = defaultLanding()

	local stateRemote = Remotes.remoteEvent("MissionState") -- server → client: สถานะห้องรอ/ภารกิจ
	stateEvent = stateRemote

	-- client ขอสถานะตอนเริ่ม (กันพลาดอีเวนต์ที่ยิงก่อน client พร้อม)
	local getState = Remotes.remoteFunction("GetMissionState")
	getState.OnServerInvoke = function(player: Player)
		if not RateLimit.allow(player, "GetMissionState", MissionCfg.StateRequestMinIntervalSeconds) then
			return nil
		end
		Combat.resendState(player) -- ให้ UI ห้องรอรู้ว่าถือปืนอะไรอยู่ (อีเวนต์แรกอาจมาก่อน client ต่อสาย)
		return buildSnapshot(player)
	end

	Remotes.remoteEvent("MissionSetReady").OnServerEvent:Connect(onSetReady) -- (boolean)
	Remotes.remoteEvent("MissionSetLanding").OnServerEvent:Connect(onSetLanding) -- (x: number, z: number)

	Players.PlayerAdded:Connect(registerPlayer)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		registerPlayer(player)
	end

	startBoundsLoop()

	-- โหลดจุดสำคัญในเธรดแยก ไม่บล็อกการเริ่มระบบอื่น · เสร็จแล้วอัปเดตจุดลงเริ่มต้นและแจ้ง client
	task.spawn(function()
		loadMarkers()
		if landingIsDefault then
			landingX, landingZ = defaultLanding()
		end
		broadcast()
	end)
end

return Mission
