--!strict
-- Monkeys: ลิงและรังลิง (ฝั่งเซิร์ฟเวอร์ตัดสินทุกอย่าง)
-- - รัง 4 รัง อ่านตำแหน่งจาก workspace.MapMarkers.Nest1..Nest4
-- - AI ทั้งหมดอัปเดตในลูปเดียวเป็นรอบ (AiTickSeconds) ไม่ใช้ลูปต่อตัว เพื่อไม่หน่วงมือถือ
-- - ลิงที่ไกลผู้เล่นทุกคนเกิน SleepDistance จะหยุดคิด

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerData = require(script.Parent.PlayerData)
local PlayerHealth = require(script.Parent.PlayerHealth)
local MC = Config.Monkey

type Nest = {
	index: number,
	position: Vector3,
	aliveBase: number, -- ลิงปกติที่ยังมีชีวิต
	reinforcedTotal: number, -- ลิงที่เรียกเพิ่มไปแล้วรวม
	reinforceCalls: number, -- จำนวนครั้งที่เรียกพวกแล้ว
	attacked: boolean, -- ผู้เล่นเริ่มโจมตีรังแล้ว
	alert: boolean, -- รังตื่นตัว (เห็นไกลขึ้น)
	locked: boolean, -- เรียกพวกไม่ได้อีก (ฆ่าลิงปกติหมดก่อนครบ 10 วิแรก)
	nextReinforceAt: number,
}

type MonkeyRec = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	nest: Nest,
	isReinforcement: boolean,
	hp: number,
	dead: boolean,
	mode: string, -- "idle" | "return"
	speed: number,
	lastAttack: number,
	angle: number,
	waypoint: Vector3?,
	waypointUntil: number,
	asleep: boolean,
	lastPos: Vector3,
}

local Monkeys = {}

local nests: { Nest } = {}
local records: { [Model]: MonkeyRec } = {} -- เฉพาะลิงที่ยังมีชีวิต
local corpses: { [Model]: boolean } = {}
local aliveCount = 0
local started = false
local monkeyFolder: Folder? = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local rng = Random.new()

-- ===== เครื่องมือย่อย =====

-- ลิงตีได้ทั้งคนปกติและคนที่ล้ม (ไม่รวมคนตาย)
local function isPlayerTargetable(player: Player): boolean
	local ok, state = pcall(PlayerHealth.getState, player)
	return ok and (state == "Alive" or state == "Downed")
end

local function groundY(x: number, z: number, refY: number): number
	local hit = Workspace:Raycast(Vector3.new(x, refY + 300, z), Vector3.new(0, -900, 0), rayParams)
	if hit ~= nil then
		return hit.Position.Y
	end
	return refY
end

local function horizontalDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- ===== สร้างตัวลิง (จาก Part ง่าย ๆ ยังไม่มีโมเดลจริง) =====
local BODY_COLOR = Color3.fromRGB(121, 85, 58)
local FACE_COLOR = Color3.fromRGB(205, 164, 128)

local function makePart(name: string, size: Vector3, color: Color3, collide: boolean): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = collide
	part.CanTouch = false -- ไม่ต้องใช้ Touched ประหยัดเครื่อง
	part.CanQuery = true -- ต้องให้ raycast ยิงโดนได้
	part.Massless = not collide
	return part
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function buildMonkey(cf: CFrame): (Model, Humanoid, BasePart)
	local model = Instance.new("Model")
	model.Name = "Monkey"

	local root = makePart("HumanoidRootPart", Vector3.new(2, 2, 1.2), BODY_COLOR, true)
	root.CFrame = cf
	root.Parent = model

	-- หัว (ด้านหน้าคือ -Z) และหาง
	local head = makePart("Head", Vector3.new(1.4, 1.2, 1.2), FACE_COLOR, false)
	head.CFrame = cf * CFrame.new(0, 1.5, -0.3)
	head.Parent = model
	weld(root, head)

	local tail = makePart("Tail", Vector3.new(0.3, 0.3, 2), BODY_COLOR, false)
	tail.CFrame = cf * CFrame.new(0, -0.3, 1.6)
	tail.Parent = model
	weld(root, tail)

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15 -- ให้ HipHeight ใช้งานได้
	humanoid.HipHeight = 1.5
	humanoid.MaxHealth = MC.MaxHealth
	humanoid.Health = MC.MaxHealth
	humanoid.WalkSpeed = MC.WalkSpeed
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model

	model.PrimaryPart = root
	return model, humanoid, root
end

local function setSpeed(rec: MonkeyRec, speed: number)
	if rec.speed ~= speed then
		rec.speed = speed
		rec.humanoid.WalkSpeed = speed
	end
end

-- ===== เกิด / ตาย =====

local function removeRecord(rec: MonkeyRec)
	-- เรียกซ้ำได้ปลอดภัย: นับลดครั้งเดียว
	if records[rec.model] == nil then
		return
	end
	records[rec.model] = nil
	aliveCount -= 1
	if not rec.isReinforcement then
		rec.nest.aliveBase -= 1
	end
end

local function spawnMonkey(nest: Nest, isReinforcement: boolean, x: number, z: number)
	local folder = monkeyFolder
	if folder == nil or aliveCount >= MC.MaxTotal then
		return
	end
	local y = groundY(x, z, nest.position.Y) + 3
	local angle = rng:NextNumber(0, math.pi * 2)
	local model, humanoid, root = buildMonkey(CFrame.new(x, y, z) * CFrame.Angles(0, angle, 0))
	model:SetAttribute("NestIndex", nest.index)

	local rec: MonkeyRec = {
		model = model,
		humanoid = humanoid,
		root = root,
		nest = nest,
		isReinforcement = isReinforcement,
		hp = MC.MaxHealth,
		dead = false,
		mode = "idle",
		speed = MC.WalkSpeed,
		lastAttack = 0,
		angle = angle,
		waypoint = nil,
		waypointUntil = 0,
		asleep = false,
		lastPos = root.Position,
	}
	records[model] = rec
	aliveCount += 1
	if isReinforcement then
		nest.reinforcedTotal += 1
	else
		nest.aliveBase += 1
	end

	model.Parent = folder
	CollectionService:AddTag(model, "Monkey")
	-- ให้เซิร์ฟเวอร์คุมฟิสิกส์ ไม่ให้ client คนไหนเป็นเจ้าของ (กันโกง)
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	-- ถ้าโมเดลถูกลบจากที่อื่น (เช่น ตกนอกแมพ) ให้ล้างข้อมูลด้วย ไม่นับเป็นฆ่า
	model.Destroying:Connect(function()
		removeRecord(rec)
		corpses[model] = nil
	end)
end

local function sinkCorpse(model: Model)
	task.delay(MC.CorpseSinkDelaySeconds, function()
		if model.Parent == nil or not corpses[model] then
			return
		end
		local steps = math.max(1, math.floor(MC.SinkSeconds / 0.1))
		local stepDrop = MC.SinkDepth / steps
		for _ = 1, steps do
			if model.Parent == nil then
				return
			end
			model:PivotTo(model:GetPivot() - Vector3.new(0, stepDrop, 0))
			task.wait(0.1)
		end
		corpses[model] = nil
		model:Destroy()
	end)
end

local function killMonkey(rec: MonkeyRec, attacker: Player?)
	-- ตั้ง dead ก่อนทำอย่างอื่น กันนับตาย/ให้เงินซ้ำ
	if rec.dead then
		return
	end
	rec.dead = true
	removeRecord(rec)

	local nest = rec.nest
	-- ฆ่าลิงปกติทั้งรังก่อนครบเวลาครั้งแรก → เรียกพวกไม่ได้อีก
	if nest.attacked and nest.reinforceCalls == 0 and nest.aliveBase <= 0 then
		nest.locked = true
	end

	if attacker ~= nil and attacker.Parent == Players then
		PlayerData.addMoney(attacker, MC.MoneyPerKill)
		PlayerData.addStat(attacker, "monkeysKilled", 1)
	end

	-- ล้มนิ่ง ไม่มีเลือด ไม่มีการทำลายร่าง
	rec.model:SetAttribute("Dead", true)
	rec.humanoid:MoveTo(rec.root.Position)
	rec.humanoid.WalkSpeed = 0
	for _, part in rec.model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false -- ซากไม่บังกระสุน
		end
	end
	rec.model:PivotTo(rec.model:GetPivot() * CFrame.Angles(0, 0, math.pi / 2))
	corpses[rec.model] = true
	sinkCorpse(rec.model)
end

-- ===== รังและการเรียกพวก =====

local function processNests(now: number)
	for _, nest in nests do
		if nest.attacked and not nest.locked and nest.reinforcedTotal < MC.ReinforceMaxPerNest then
			if now >= nest.nextReinforceAt then
				nest.nextReinforceAt = now + MC.ReinforceIntervalSeconds
				nest.reinforceCalls += 1
				local count = math.min(MC.ReinforceCount, MC.ReinforceMaxPerNest - nest.reinforcedTotal)
				for _ = 1, count do
					-- เกิดที่ขอบรัง
					local a = rng:NextNumber(0, math.pi * 2)
					local r = MC.NestWanderRadius + 5
					spawnMonkey(nest, true, nest.position.X + math.cos(a) * r, nest.position.Z + math.sin(a) * r)
				end
			end
		end
	end
end

-- ===== AI =====

type PlayerInfo = { player: Player, pos: Vector3, alive: boolean }

local function collectPlayers(): { PlayerInfo }
	local list: { PlayerInfo } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp ~= nil and hrp:IsA("BasePart") then
			table.insert(list, { player = player, pos = hrp.Position, alive = isPlayerTargetable(player) })
		end
	end
	return list
end

local function pickWaypoint(rec: MonkeyRec, now: number)
	local nest = rec.nest
	rec.angle += rng:NextNumber(0.5, 1.3)
	local radius = rng:NextNumber(10, MC.NestWanderRadius)
	rec.waypoint = nest.position + Vector3.new(math.cos(rec.angle) * radius, 0, math.sin(rec.angle) * radius)
	rec.waypointUntil = now + 8
	rec.humanoid:MoveTo(rec.waypoint :: Vector3)
end

local function updateMonkey(rec: MonkeyRec, players: { PlayerInfo }, now: number)
	local pos = rec.root.Position
	local nest = rec.nest

	-- หาผู้เล่นที่ใกล้สุด (ทุกคน) กับเป้าหมายที่ตีได้ (ปกติหรือล้ม ไม่รวมตาย) — เลือกคนที่ใกล้สุด
	local sight = if nest.alert then MC.AlertSightDistance else MC.SightDistance
	local nearestAny = math.huge
	local target: PlayerInfo? = nil
	local targetDist = math.huge
	for _, info in players do
		local d = (info.pos - pos).Magnitude
		if d < nearestAny then
			nearestAny = d
		end
		if
			info.alive
			and d <= sight
			and d < targetDist
			and (info.pos - nest.position).Magnitude <= MC.LeashDistance
		then
			target = info
			targetDist = d
		end
	end

	-- ไกลทุกคนมาก → หยุดคิด
	if nearestAny > MC.SleepDistance then
		if not rec.asleep then
			rec.asleep = true
			rec.humanoid:MoveTo(pos)
		end
		return
	end
	rec.asleep = false

	local movedLittle = (pos - rec.lastPos).Magnitude < 0.2
	rec.lastPos = pos

	-- ไกลรังเกิน → กลับรัง (ไม่สนผู้เล่นจนกว่าจะถึงรัศมีรัง)
	local nestDist = (pos - nest.position).Magnitude
	if nestDist > MC.LeashDistance then
		rec.mode = "return"
	end
	if rec.mode == "return" then
		if nestDist <= MC.NestWanderRadius then
			rec.mode = "idle"
			rec.waypoint = nil
		else
			setSpeed(rec, MC.ChaseSpeed)
			rec.humanoid:MoveTo(nest.position)
			if movedLittle then
				rec.humanoid.Jump = true
			end
			return
		end
	end

	if target ~= nil then
		if targetDist <= MC.AttackRange then
			rec.humanoid:MoveTo(pos) -- หยุดตี
			if now - rec.lastAttack >= MC.AttackIntervalSeconds then
				rec.lastAttack = now
				-- PlayerHealth ตรวจสถานะล่าสุดเอง (ถ้าเพิ่งชุบ/ตาย/ออกเกม จะจัดการถูกต้องหรือไม่มีผล)
				local ok, err = pcall(PlayerHealth.damageFromMonkey, target.player, MC.AttackDamage)
				if not ok then
					warn("[Monkeys] damageFromMonkey error:", err)
				end
			end
		else
			setSpeed(rec, MC.ChaseSpeed)
			rec.humanoid:MoveTo(target.pos)
			if movedLittle then
				rec.humanoid.Jump = true -- ข้ามสิ่งกีดขวางเล็ก ๆ
			end
		end
		return
	end

	-- เดินวนรอบรัง
	setSpeed(rec, MC.WalkSpeed)
	local wp = rec.waypoint
	if wp == nil or now >= rec.waypointUntil or horizontalDistance(pos, wp) < 3 then
		pickWaypoint(rec, now)
	elseif movedLittle then
		rec.humanoid.Jump = true
	end
end

local function aiTick()
	local now = os.clock()
	processNests(now)

	if next(records) == nil then
		return
	end
	local players = collectPlayers()
	-- ถ่ายรายการก่อนวน เผื่อตารางเปลี่ยนระหว่างทาง
	local list: { MonkeyRec } = {}
	for _, rec in records do
		table.insert(list, rec)
	end
	for _, rec in list do
		if not rec.dead and rec.model.Parent ~= nil and rec.root.Parent ~= nil then
			local ok, err = pcall(updateMonkey, rec, players, now)
			if not ok then
				warn("[Monkeys] AI error:", err)
			end
		end
	end
end

-- ===== โหลดรัง / เริ่มระบบ =====

local function readMarkerPosition(inst: Instance): Vector3?
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	return nil
end

local function loadNests()
	nests = {}
	local markers = Workspace:WaitForChild(Config.Map.MarkersFolderName, 10)
	if markers == nil then
		warn(
			"[Monkeys] ไม่พบ workspace.MapMarkers — ยังไม่มีรังลิง (วาง Part ชื่อ Nest1..Nest4 ในโฟลเดอร์ MapMarkers)"
		)
		return
	end
	for i = 1, MC.NestCount do
		local marker = markers:WaitForChild("Nest" .. i, 3)
		local position = if marker ~= nil then readMarkerPosition(marker) else nil
		if position == nil then
			warn(
				"[Monkeys] ไม่พบจุดรัง Nest"
					.. i
					.. " ใน MapMarkers — ข้ามรังนี้"
			)
		else
			table.insert(nests, {
				index = i,
				position = position,
				aliveBase = 0,
				reinforcedTotal = 0,
				reinforceCalls = 0,
				attacked = false,
				alert = false,
				locked = false,
				nextReinforceAt = 0,
			})
		end
	end
end

local function spawnBaseMonkeys()
	for _, nest in nests do
		for _ = 1, MC.NestBaseMax do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = rng:NextNumber(5, MC.NestWanderRadius)
			spawnMonkey(nest, false, nest.position.X + math.cos(a) * r, nest.position.Z + math.sin(a) * r)
		end
	end
end

-- ล้างลิงทั้งหมด (ทั้งที่ยังมีชีวิตและซากที่กำลังจม)
local function clearAll()
	local toDestroy: { Model } = {}
	for model in records do
		table.insert(toDestroy, model)
	end
	for model in corpses do
		table.insert(toDestroy, model)
	end
	for _, model in toDestroy do
		model:Destroy()
	end
	records = {}
	corpses = {}
	aliveCount = 0
end

-- ===== ฟังก์ชันให้ระบบอื่นเรียก =====

-- ปืน/ประทัด/ไม้กวดโดนลิง — เซิร์ฟเวอร์ตรวจเองทุกอย่าง
function Monkeys.damageMonkey(model: Model, amount: number, attacker: Player?)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local rec = records[model]
	if rec == nil or rec.dead then
		return
	end
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return
	end
	local owner: Player? = nil
	if typeof(attacker) == "Instance" and attacker:IsA("Player") and attacker.Parent == Players then
		owner = attacker
	end

	-- ผู้เล่นเริ่มโจมตีรังนี้ → เริ่มจับเวลาเรียกพวก
	local nest = rec.nest
	if not nest.attacked then
		nest.attacked = true
		nest.nextReinforceAt = os.clock() + MC.ReinforceIntervalSeconds
	end
	nest.alert = true

	rec.hp -= amount
	if rec.hp <= 0 then
		killMonkey(rec, owner)
	end
end

-- ให้ระบบภารกิจเรียกเมื่อเริ่มภารกิจใหม่: ล้างแล้วเกิดลิงรังละ NestBaseMax ตัวใหม่
function Monkeys.resetAll()
	if not started then
		return
	end
	clearAll()
	for _, nest in nests do
		nest.aliveBase = 0
		nest.reinforcedTotal = 0
		nest.reinforceCalls = 0
		nest.attacked = false
		nest.alert = false
		nest.locked = false
		nest.nextReinforceAt = 0
	end
	spawnBaseMonkeys()
end

function Monkeys.start()
	if started then
		return
	end
	started = true

	local existing = Workspace:FindFirstChild("Monkeys")
	local folder: Folder
	if existing ~= nil and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "Monkeys"
		folder.Parent = Workspace
	end
	monkeyFolder = folder
	rayParams.FilterDescendantsInstances = { folder }

	-- โหลดรังในเธรดแยก ไม่ให้บล็อกการเริ่มระบบอื่น
	task.spawn(function()
		loadNests()
		spawnBaseMonkeys()
		while true do
			task.wait(MC.AiTickSeconds)
			local ok, err = pcall(aiTick)
			if not ok then
				warn("[Monkeys] aiTick error:", err)
			end
		end
	end)
end

return Monkeys
