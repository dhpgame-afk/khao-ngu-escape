--!strict
-- RescueUi: หน้าจอกลับเข้าแมพหลังตาย (มือถือเป็นหลัก — Scale ทั้งหมด ปุ่มใหญ่ ข้อความไทย)
-- - คนยังมีชีวิต: ปุ่ม "โทรเรียกเพื่อน (n)" เมื่อมีเพื่อนตายรออยู่ · กดแล้วมีแถบ "กำลังโทร..." · กดซ้ำ = วางสาย
-- - คนตาย: กล้องตามดูเพื่อนที่ยังมีชีวิต + ปุ่มสลับคนที่ดู (ข้อความ "คุณตายแล้ว — รอเพื่อนโทรเรียก" อยู่ใน Hud)
-- - ครบ 40 วิ: หน้าจอเล็งหนังสติ๊ก — แผนที่มองจากด้านบน · ลากนิ้วดึงถอยหลังเหมือน Angry Birds · ปล่อยเพื่อยิง
--   เป้าหมาย = ทิศตรงข้ามกับที่ดึง ขยายตามสเกลบนแผนที่ (Config.Rescue.PullToMapScale) · ส่ง SlingshotFire(x, z)
-- - client "โง่": วาดตามสถานะที่เซิร์ฟเวอร์ส่งมา (RescueState) และส่งแค่เจตนา · เซิร์ฟเวอร์ตรวจทุกค่าอีกชั้น

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Hud = require(script.Parent.Hud)
local MapView = require(script.Parent.MapView)

local RC = Config.Rescue

local DARK = Color3.fromRGB(25, 28, 33)
local WHITE = Color3.fromRGB(255, 255, 255)
local GREEN = Color3.fromRGB(60, 160, 90)
local ORANGE = Color3.fromRGB(215, 140, 40)
local RED = Color3.fromRGB(220, 70, 60)
local BLUE = Color3.fromRGB(60, 120, 200)
local YELLOW = Color3.fromRGB(255, 235, 150)
local SLING_BROWN = Color3.fromRGB(170, 120, 70)
local MATE_COLOR = Color3.fromRGB(255, 255, 255)
local MATE_DEAD_COLOR = Color3.fromRGB(130, 130, 130)

-- ปุ่ม "โทรเรียกเพื่อน": ขวากลางจอ ใกล้ปุ่มขว้างประทัด (0.76, 0.36) แต่ไม่ทับ · พ้นปุ่มเปลี่ยนแม็ก (0.62, 0.58) และโซนปุ่มกระโดด
local CALL_BUTTON_CENTER = Vector2.new(0.62, 0.36)
local CALL_BUTTON_SIZE = 0.19
local KEY_CALL = Enum.KeyCode.T -- คีย์ลัดบนคอม (มือถือใช้ปุ่มบนจอ)

export type Mate = { userId: number, x: number, z: number, alive: boolean }

type State = {
	stage: string, -- "None" | "Dead" | "Aiming" | "Flying"
	endsAt: number,
	beingCalled: boolean,
	ready: boolean, -- ตัวละครอยู่ที่ถุงหนังสติ๊กแล้ว (ลากเล็งได้)
	waiting: number,
	callEndsAt: number,
	mates: { Mate },
}

type Candidate = { userId: number, humanoid: Humanoid, name: string }

export type Api = {
	onSnapshot: (snapshot: { [string]: any }) -> (), -- MissionState (ไว้วาดจุดสำคัญบนแผนที่เล็ง)
	getMates: () -> { Mate }, -- ตำแหน่งเพื่อนร่วมภารกิจล่าสุดจากเซิร์ฟเวอร์ (อ่านอย่างเดียว · NavMap ใช้)
}

local RescueUi = {}

local function addCorner(inst: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = inst
end

-- ป้ายข้อความมีพื้นหลังทึบครึ่งหนึ่ง (อ่านง่ายบนฉากเกม)
local function makePill(parent: Instance, name: string, position: UDim2, size: UDim2): TextLabel
	local label = Hud.makeLabel(parent, name, "", position, size)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundColor3 = DARK
	label.BackgroundTransparency = 0.3
	label.TextWrapped = true
	addCorner(label, 0.25)
	label.Visible = false
	return label
end

local function sanitize(payload: any): State?
	if type(payload) ~= "table" then
		return nil
	end
	local stage = payload.stage
	if stage ~= "Dead" and stage ~= "Aiming" and stage ~= "Flying" then
		stage = "None"
	end
	local mates: { Mate } = {}
	if type(payload.mates) == "table" then
		for _, m in payload.mates do
			if
				type(m) == "table"
				and type(m.userId) == "number"
				and type(m.x) == "number"
				and type(m.z) == "number"
			then
				table.insert(mates, { userId = m.userId, x = m.x, z = m.z, alive = m.alive == true })
			end
		end
	end
	return {
		stage = stage,
		endsAt = if type(payload.endsAt) == "number" then payload.endsAt else 0,
		beingCalled = payload.beingCalled == true,
		ready = payload.ready == true,
		waiting = if type(payload.waiting) == "number" then math.max(0, math.floor(payload.waiting)) else 0,
		callEndsAt = if type(payload.callEndsAt) == "number" then payload.callEndsAt else 0,
		mates = mates,
	}
end

function RescueUi.start(): Api
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local rescueState = remotes:WaitForChild("RescueState") :: RemoteEvent
	local callStartRemote = remotes:WaitForChild("CallFriendStart") :: RemoteEvent
	local callCancelRemote = remotes:WaitForChild("CallFriendCancel") :: RemoteEvent
	local fireRemote = remotes:WaitForChild("SlingshotFire") :: RemoteEvent

	local state: State = {
		stage = "None",
		endsAt = 0,
		beingCalled = false,
		ready = false,
		waiting = 0,
		callEndsAt = 0,
		mates = {},
	}

	local gui = Instance.new("ScreenGui")
	gui.Name = "Rescue"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- เลี่ยงรอยบาก/ขอบจอ
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 3
	gui.Parent = playerGui

	-- ===== โทรเรียกเพื่อน =====
	local callButton = Hud.makeButton(gui, "CallFriend", "", CALL_BUTTON_CENTER, CALL_BUTTON_SIZE, true)
	callButton.BackgroundColor3 = GREEN
	callButton.Visible = false

	local callProgressBack = Instance.new("Frame")
	callProgressBack.Name = "CallProgress"
	callProgressBack.AnchorPoint = Vector2.new(0.5, 0.5)
	-- ใต้ป้ายภารกิจ/ข้อความกลางจอ (ล่างสุด y 0.24) · ซ้ายของปุ่มโทร (x 0.57–0.67) · พ้นปุ่มเล็งและป้ายกระสุน
	callProgressBack.Position = UDim2.fromScale(0.43, 0.29)
	callProgressBack.Size = UDim2.fromScale(0.24, 0.045)
	callProgressBack.BackgroundColor3 = DARK
	callProgressBack.BackgroundTransparency = 0.3
	callProgressBack.BorderSizePixel = 0
	callProgressBack.Visible = false
	callProgressBack.Parent = gui
	addCorner(callProgressBack, 0.4)
	local callProgressFill = Instance.new("Frame")
	callProgressFill.Name = "Fill"
	callProgressFill.Size = UDim2.fromScale(0, 1)
	callProgressFill.BackgroundColor3 = GREEN
	callProgressFill.BorderSizePixel = 0
	callProgressFill.Parent = callProgressBack
	addCorner(callProgressFill, 0.4)
	local callProgressText = Hud.makeLabel(
		callProgressBack,
		"Text",
		"กำลังโทร...",
		UDim2.fromScale(0, 0),
		UDim2.fromScale(1, 1)
	)
	callProgressText.ZIndex = 2

	-- ===== คนตาย: ดูเพื่อน =====
	local watchLabel = makePill(gui, "Watching", UDim2.fromScale(0.14, 0.40), UDim2.fromScale(0.24, 0.07))
	local spectateButton = Hud.makeButton(
		gui,
		"Spectate",
		"ดูเพื่อนคนอื่น",
		Vector2.new(0.14, 0.50), -- ซ้ายกลางจอ (x 0.03–0.25, y 0.45–0.55) ไม่ทับแถบอาวุธ/ปุ่มเล็ง · โชว์เฉพาะคนตาย
		0.1,
		false
	)
	spectateButton.Size = UDim2.fromScale(0.22, 0.10)
	spectateButton.BackgroundColor3 = BLUE
	spectateButton.Visible = false
	local calledLabel = makePill(gui, "BeingCalled", UDim2.fromScale(0.55, 0.40), UDim2.fromScale(0.44, 0.08))
	calledLabel.Text =
		"เพื่อนกำลังโทรเรียกคุณ — รอสักครู่"
	calledLabel.TextColor3 = YELLOW
	local flyingLabel = makePill(gui, "Flying", UDim2.fromScale(0.5, 0.29), UDim2.fromScale(0.40, 0.06)) -- ใต้แบนเนอร์ (ล่างสุด 0.24)
	flyingLabel.Text = "กำลังบินกลับเข้าแมพ..."
	flyingLabel.TextColor3 = YELLOW

	-- ===== เล็งหนังสติ๊ก =====
	local aimRoot = Instance.new("Frame")
	aimRoot.Name = "SlingshotAim"
	aimRoot.Size = UDim2.fromScale(1, 1)
	aimRoot.BackgroundColor3 = DARK
	aimRoot.BackgroundTransparency = 0.1
	aimRoot.BorderSizePixel = 0
	aimRoot.Active = true -- กินอินพุตทั้งจอ ไม่ให้ทะลุไปหมุนกล้อง/กดปุ่มข้างล่าง
	aimRoot.Visible = false
	aimRoot.Parent = gui

	local titleLabel = Hud.makeLabel(aimRoot, "Title", "", UDim2.fromScale(0.1, 0.14), UDim2.fromScale(0.8, 0.07))
	titleLabel.TextColor3 = YELLOW
	local mapView =
		MapView.create(aimRoot, UDim2.fromScale(0.5, 0.55), UDim2.fromScale(0.72, 0.60), Vector2.new(0.5, 0.5))
	local mapFrame = mapView.frame
	mapFrame.Active = true
	local countdownLabel =
		Hud.makeLabel(aimRoot, "Countdown", "", UDim2.fromScale(0.2, 0.87), UDim2.fromScale(0.6, 0.07))

	-- เส้นยาง (แดง) จากหนังสติ๊กถึงนิ้ว · เส้นประทางยิง (ขาวจาง) จากหนังสติ๊กถึงเป้า
	local function makeLine(name: string, color: Color3, transparency: number, zIndex: number): Frame
		local line = Instance.new("Frame")
		line.Name = name
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.BackgroundColor3 = color
		line.BackgroundTransparency = transparency
		line.BorderSizePixel = 0
		line.ZIndex = zIndex
		line.Visible = false
		line.Parent = mapFrame
		return line
	end
	local aimLine = makeLine("AimLine", WHITE, 0.5, 6)
	local bandLine = makeLine("Band", RED, 0, 7)

	local slingDot = mapView.makeDot("Sling", SLING_BROWN, 0.05, 8)
	slingDot.Position = UDim2.fromScale(0.5, 0.5) -- หนังสติ๊กอยู่กลางแผนที่ ดึงไปทางไหน เป้าก็อยู่ฝั่งตรงข้าม
	local slingStroke = Instance.new("UIStroke")
	slingStroke.Color = WHITE
	slingStroke.Thickness = 2
	slingStroke.Parent = slingDot
	local slingLabel = Hud.makeLabel(
		mapFrame,
		"SlingLabel",
		"หนังสติ๊ก",
		UDim2.fromScale(0.5, 0.57),
		UDim2.fromScale(0.16, 0.07)
	)
	slingLabel.AnchorPoint = Vector2.new(0.5, 0)
	slingLabel.ZIndex = 8
	local targetDot = mapView.makeDot("Target", MapView.COLOR_LANDING, 0.06, 9)
	local targetStroke = Instance.new("UIStroke")
	targetStroke.Color = WHITE
	targetStroke.Thickness = 3
	targetStroke.Parent = targetDot
	targetDot.Visible = false

	local mateDots: { [number]: Frame } = {}

	-- ขอบเขตจุดลงที่ยอมรับ (เหมือนฝั่งเซิร์ฟเวอร์) ไว้บีบเป้าไม่ให้ล้นแผนที่
	local limitX = Config.Map.HalfWidthStuds - Config.Map.LandingMarginStuds
	local limitZ = Config.Map.HalfDepthStuds - Config.Map.LandingMarginStuds

	-- ===== ลากนิ้ว =====
	local activeInput: InputObject? = nil
	local dragStart = Vector2.zero
	local dragPull = Vector2.zero -- px · ทิศที่ดึง (จากจุดที่เริ่มแตะ)
	local targetWorldX, targetWorldZ = 0, 0
	local lastFireClock = 0

	local function setLine(line: Frame, a: Vector2, b: Vector2, thickness: number)
		local size = mapFrame.AbsoluteSize
		local dx, dy = (b.X - a.X) * size.X, (b.Y - a.Y) * size.Y
		local length = math.sqrt(dx * dx + dy * dy)
		line.Position = UDim2.fromScale((a.X + b.X) / 2, (a.Y + b.Y) / 2)
		line.Size = UDim2.fromScale(length / math.max(size.X, 1), thickness) -- thickness เป็นสัดส่วนความสูงแผนที่
		line.Rotation = math.deg(math.atan2(dy, dx))
		line.Visible = true
	end

	local function hideDragVisuals()
		aimLine.Visible = false
		bandLine.Visible = false
		targetDot.Visible = false
	end

	local function cancelDrag()
		activeInput = nil
		dragPull = Vector2.zero
		hideDragVisuals()
	end

	local function updateDrag(currentPosition: Vector2)
		local size = mapFrame.AbsoluteSize
		if size.X < 1 or size.Y < 1 then
			return
		end
		local pull = currentPosition - dragStart
		local maxPull = size.Y * RC.MaxPullHeightFraction
		if pull.Magnitude > maxPull then
			pull = pull.Unit * maxPull
		end
		dragPull = pull

		-- เป้า = ตรงข้ามกับที่ดึง ขยายด้วย PullToMapScale (หน่วยพิกเซลเดียวกันทั้งสองแกน ทิศจึงตรงข้ามจริง)
		local targetPx = size / 2 - pull * RC.PullToMapScale
		local u = math.clamp(targetPx.X / size.X, 0, 1)
		local v = math.clamp(targetPx.Y / size.Y, 0, 1)
		local worldX, worldZ = mapView.mapToWorld(u, v)
		targetWorldX = math.clamp(worldX, -limitX, limitX)
		targetWorldZ = math.clamp(worldZ, -limitZ, limitZ)

		local sling = Vector2.new(0.5, 0.5)
		local finger = sling + Vector2.new(pull.X / size.X, pull.Y / size.Y)
		local targetUdim = mapView.worldToMap(targetWorldX, targetWorldZ)
		local target = Vector2.new(targetUdim.X.Scale, targetUdim.Y.Scale)
		setLine(bandLine, sling, finger, 0.018)
		setLine(aimLine, sling, target, 0.008)
		targetDot.Position = targetUdim
		targetDot.Visible = true
	end

	local function endDrag()
		local pull = dragPull
		cancelDrag()
		local size = mapFrame.AbsoluteSize
		if pull.Magnitude < size.Y * RC.MinPullHeightFraction then
			return -- แค่แตะ ไม่ใช่การดึง
		end
		if state.stage ~= "Aiming" or state.beingCalled or not state.ready then
			return
		end
		local now = os.clock()
		if now - lastFireClock < 0.5 then
			return
		end
		lastFireClock = now
		fireRemote:FireServer(targetWorldX, targetWorldZ)
	end

	mapFrame.InputBegan:Connect(function(input: InputObject)
		if activeInput ~= nil or state.stage ~= "Aiming" or state.beingCalled or not state.ready then
			return -- ยังไม่พร้อม: ตัวละครยังไม่ถึงถุงหนังสติ๊ก เซิร์ฟเวอร์จะทิ้งคำสั่งยิง
		end
		local t = input.UserInputType
		if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then
			return
		end
		activeInput = input
		dragStart = Vector2.new(input.Position.X, input.Position.Y)
		dragPull = Vector2.zero
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local tracked = activeInput
		if tracked == nil then
			return
		end
		local isTracked = input == tracked
			or (
				tracked.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			)
		if isTracked then
			updateDrag(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if activeInput ~= nil and input == activeInput then
			endDrag()
		end
	end)

	-- ===== โทรเรียกเพื่อน: ปุ่ม / คีย์ลัด =====
	local function isOwnAlive(): boolean
		local character = player.Character
		return character ~= nil and character:GetAttribute("State") == "Alive"
	end

	local function toggleCall()
		if state.stage ~= "None" or not isOwnAlive() then
			return
		end
		if state.callEndsAt > 0 then
			callCancelRemote:FireServer()
		elseif state.waiting > 0 then
			callStartRemote:FireServer()
		end
	end
	callButton.Activated:Connect(toggleCall)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == KEY_CALL then
			toggleCall()
		end
	end)

	-- ===== คนตาย: ดูเพื่อน =====
	local spectatingUserId = 0
	local spectateActive = false -- ตอนนี้เราเป็นคนเปลี่ยนกล้องอยู่ (ต้องคืนกล้องเมื่อเลิกดู)

	-- Humanoid ของเราที่ยังมีชีวิต (ไม่ใช่ซาก — ห้ามตั้งกล้องไปที่ซากตัวเอง)
	local function ownLivingHumanoid(): Humanoid?
		local character = player.Character
		if character == nil or character:GetAttribute("State") == "Dead" then
			return nil
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil and humanoid.Health > 0 then
			return humanoid
		end
		return nil
	end

	-- เพื่อนที่ยังมีชีวิตและตัวละครอยู่ฝั่งเราจริง (StreamingEnabled อาจยังไม่โหลดตัวเพื่อนที่อยู่ไกล)
	local function spectateCandidates(): { Candidate }
		local list: { Candidate } = {}
		for _, mate in state.mates do
			local other = Players:GetPlayerByUserId(mate.userId)
			local character = if other ~= nil then other.Character else nil
			if other ~= nil and character ~= nil and mate.alive and character:GetAttribute("State") ~= "Dead" then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid ~= nil and humanoid.Health > 0 then
					table.insert(list, { userId = mate.userId, humanoid = humanoid, name = other.DisplayName })
				end
			end
		end
		return list
	end

	spectateButton.Activated:Connect(function()
		local candidates = spectateCandidates()
		if #candidates == 0 then
			return
		end
		local currentIndex = 0
		for i, candidate in candidates do
			if candidate.userId == spectatingUserId then
				currentIndex = i
			end
		end
		spectatingUserId = candidates[(currentIndex % #candidates) + 1].userId
	end)

	-- คืนกล้องให้ตัวละครของเราเอง (ตอนเกิดใหม่/เลิกดู)
	local function restoreCamera()
		spectateActive = false
		spectatingUserId = 0
		local camera = Workspace.CurrentCamera
		local humanoid = ownLivingHumanoid()
		if camera ~= nil and humanoid ~= nil and camera.CameraSubject ~= humanoid then
			camera.CameraSubject = humanoid
		end
	end

	local function updateSpectate()
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return
		end
		local candidates = spectateCandidates()
		local chosen: Candidate? = nil
		for _, candidate in candidates do
			if candidate.userId == spectatingUserId then
				chosen = candidate
			end
		end
		if chosen == nil then
			chosen = candidates[1]
		end
		if chosen == nil then
			watchLabel.Visible = false
			spectateButton.Visible = false
			if spectateActive then
				restoreCamera() -- เพื่อนที่ดูอยู่ออก/ตาย ไม่เหลือใครให้ดู: คืนกล้อง (ถ้าเรามีตัวละครที่ยังมีชีวิต)
			end
			return
		end
		spectatingUserId = chosen.userId
		spectateActive = true
		if camera.CameraSubject ~= chosen.humanoid then
			camera.CameraSubject = chosen.humanoid
		end
		local text = "กำลังดู: " .. chosen.name
		if watchLabel.Text ~= text then
			watchLabel.Text = text
		end
		watchLabel.Visible = true
		spectateButton.Visible = #candidates > 1
	end

	-- ===== วาดจุดเพื่อนบนแผนที่เล็ง =====
	local function refreshMateDots()
		local seen: { [number]: boolean } = {}
		for _, mate in state.mates do
			seen[mate.userId] = true
			local dot = mateDots[mate.userId]
			if dot == nil then
				dot = mapView.makeDot("Mate" .. mate.userId, MATE_COLOR, 0.03, 4)
				mateDots[mate.userId] = dot
			end
			dot.Position = mapView.worldToMap(mate.x, mate.z)
			dot.BackgroundColor3 = if mate.alive then MATE_COLOR else MATE_DEAD_COLOR
		end
		for userId, dot in mateDots do
			if not seen[userId] then
				dot:Destroy()
				mateDots[userId] = nil
			end
		end
	end

	-- ===== วนอัปเดตทุกเฟรม (เขียน property เฉพาะเมื่อค่าเปลี่ยน) =====
	local cache: { [string]: any } = {}
	local function setCached(key: string, value: any): boolean
		if cache[key] == value then
			return false
		end
		cache[key] = value
		return true
	end

	local function render()
		local now = Workspace:GetServerTimeNow()
		local stage = state.stage
		local ownAlive = isOwnAlive()
		local calling = state.callEndsAt > 0

		-- ปุ่มโทร + แถบกำลังโทร
		local showCall = stage == "None" and ownAlive and (state.waiting > 0 or calling)
		if setCached("callVisible", showCall) then
			callButton.Visible = showCall
		end
		local callText = if calling
			then "ยกเลิกโทร"
			else "โทรเรียกเพื่อน\n(" .. state.waiting .. ")"
		if setCached("callText", callText) then
			callButton.Text = callText
			callButton.BackgroundColor3 = if calling then ORANGE else GREEN
		end
		local showProgress = stage == "None" and ownAlive and calling
		if setCached("progressVisible", showProgress) then
			callProgressBack.Visible = showProgress
		end
		if showProgress then
			local fraction = 1 - (state.callEndsAt - now) / math.max(Config.Player.PhoneCallSeconds, 0.1)
			callProgressFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		end

		-- คนตาย: กล้องตามเพื่อน
		if stage == "Dead" then
			updateSpectate()
		else
			if watchLabel.Visible then
				watchLabel.Visible = false
			end
			if spectateButton.Visible then
				spectateButton.Visible = false
			end
			if spectateActive then
				restoreCamera()
			end
		end
		local showCalled = (stage == "Dead" or stage == "Aiming") and state.beingCalled
		if setCached("calledVisible", showCalled) then
			calledLabel.Visible = showCalled
		end
		local showFlying = stage == "Flying"
		if setCached("flyingVisible", showFlying) then
			flyingLabel.Visible = showFlying
		end

		-- หน้าเล็งหนังสติ๊ก
		local showAim = stage == "Aiming"
		if setCached("aimVisible", showAim) then
			aimRoot.Visible = showAim
			if not showAim then
				cancelDrag()
			end
		end
		if showAim then
			local title = if state.beingCalled
				then "เพื่อนกำลังโทรเรียกคุณ — รอสักครู่"
				elseif not state.ready then "กำลังเตรียมหนังสติ๊ก…"
				else "ลากนิ้วดึงถอยหลังจากกลางแผนที่ แล้วปล่อยเพื่อยิงตัวเองไปจุดสีเขียว"
			if setCached("aimTitle", title) then
				titleLabel.Text = title
			end
			local remaining = math.max(0, math.ceil(state.endsAt - now))
			local countdown = "ยิงอัตโนมัติใน " .. remaining .. " วิ"
			if setCached("aimCountdown", countdown) then
				countdownLabel.Text = countdown
			end
		end
	end

	RunService.RenderStepped:Connect(render)

	-- เกิดตัวละครใหม่ = เลิกดูเพื่อน (ตัวละครใหม่ของเราเองเป็นเป้ากล้อง)
	player.CharacterAdded:Connect(function(character: Model)
		spectateActive = false
		spectatingUserId = 0
		local humanoid = character:WaitForChild("Humanoid", 10)
		local camera = Workspace.CurrentCamera
		if camera ~= nil and humanoid ~= nil and humanoid:IsA("Humanoid") and player.Character == character then
			camera.CameraSubject = humanoid
		end
	end)

	rescueState.OnClientEvent:Connect(function(payload: any)
		local parsed = sanitize(payload)
		if parsed == nil then
			return
		end
		state = parsed
		refreshMateDots()
	end)

	return {
		onSnapshot = function(snapshot: { [string]: any })
			mapView.setMarkers(snapshot.markers)
		end,
		getMates = function(): { Mate }
			return state.mates
		end,
	}
end

return RescueUi
