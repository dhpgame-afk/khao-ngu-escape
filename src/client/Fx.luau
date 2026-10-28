--!strict
-- Fx: เอฟเฟกต์ภาพฝั่ง client (เส้นกระสุน BB เล็ก ๆ) — ผลจริงมาจากเซิร์ฟเวอร์ ไม่มีเสียง ไม่มีเลือด

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Fx = {}

local MAX_TRACER_LENGTH = 400

function Fx.tracer(origin: Vector3, target: Vector3)
	local offset = target - origin
	local length = math.min(offset.Magnitude, MAX_TRACER_LENGTH)
	if length < 0.5 then
		return
	end
	local part = Instance.new("Part")
	part.Name = "Tracer"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 230, 120)
	part.Size = Vector3.new(0.12, 0.12, length)
	part.CFrame = CFrame.lookAt(origin, target) * CFrame.new(0, 0, -length / 2)
	part.Parent = Workspace
	Debris:AddItem(part, Config.Combat.TracerSeconds)
end

-- ===== ท่าฟาดไม้กวด (ขยับด้วยโค้ด ไม่ใช้ animation asset) =====
-- ขยับ 2 ที่พร้อมกัน เพื่อให้เห็นชัดแม้ข้อต่อไหล่ถูกอย่างอื่นทับ:
--   1) C0 ของข้อต่อไหล่ (Animate script แตะแค่ Transform จึงไม่ชน)
--   2) C0 ของ Weld ที่ติดไม้กวดกับมือ (ปัดไม้กวดเป็นวงกว้างเพิ่มอีกชั้น)
-- เก็บ C0 เดิมไว้ที่ baseC0 ตั้งแต่ครั้งแรก · ฟาดซ้อนกัน = เริ่มนับเวลาใหม่แต่ยังใช้ baseC0 เดิม จึงไม่เพี้ยนสะสม

type SwingState = {
	motor: Motor6D?,
	baseC0: CFrame,
	broomWeld: Weld?,
	baseWeldC0: CFrame,
	startClock: number,
	isR15: boolean,
	lastAppliedC0: CFrame?, -- ใช้ตรวจเฉพาะตอนเปิด debug: มีอะไรมาเขียนทับ C0 เราไหม
}

local activeSwings: { [Model]: SwingState } = {}
local swingConnection: RBXScriptConnection? = nil

local function debugLog(message: string)
	if Config.Debug.BroomSwing then
		print("[BroomSwing][client] " .. message)
	end
end

local function findShoulder(character: Model): (Motor6D?, boolean)
	local upperArm = character:FindFirstChild("RightUpperArm") -- R15
	if upperArm ~= nil then
		local motor = upperArm:FindFirstChild("RightShoulder")
		if motor ~= nil and motor:IsA("Motor6D") then
			return motor, true
		end
	end
	local torso = character:FindFirstChild("Torso") -- R6
	if torso ~= nil then
		local motor = torso:FindFirstChild("Right Shoulder")
		if motor ~= nil and motor:IsA("Motor6D") then
			return motor, false
		end
	end
	return nil, true
end

-- Weld ที่ติดไม้กวดกับมือ (สร้างโดยเซิร์ฟเวอร์ใน Combat.attachBroom)
local function findBroomWeld(character: Model): Weld?
	local folder = character:FindFirstChild("HeldBroom")
	local handle = if folder ~= nil then folder:FindFirstChild("Handle") else nil
	local weld = if handle ~= nil then handle:FindFirstChild("HandWeld") else nil
	if weld ~= nil and weld:IsA("Weld") then
		return weld
	end
	return nil
end

local function smoothstep(t: number): number
	return t * t * (3 - 2 * t)
end

-- มุมแขน (องศา) ณ เวลา t (0–1): ง้างขึ้น → ฟาดลง → กลับท่าเดิม
local function swingAngleDegrees(t: number): number
	local broom = Config.Broom
	local windupEnd = broom.SwingWindupFraction
	local strikeEnd = broom.SwingStrikeEndFraction
	if t < windupEnd then
		return broom.SwingWindupDegrees * smoothstep(t / windupEnd)
	elseif t < strikeEnd then
		local k = smoothstep((t - windupEnd) / (strikeEnd - windupEnd))
		return broom.SwingWindupDegrees + (broom.SwingStrikeDegrees - broom.SwingWindupDegrees) * k
	end
	local k = smoothstep((t - strikeEnd) / (1 - strikeEnd))
	return broom.SwingStrikeDegrees * (1 - k)
end

local function finishSwing(character: Model)
	local state = activeSwings[character]
	if state == nil then
		return
	end
	activeSwings[character] = nil
	local motor = state.motor
	if motor ~= nil and motor.Parent ~= nil then
		motor.C0 = state.baseC0 -- คืนท่าเดิมเสมอ
	end
	local weld = state.broomWeld
	if weld ~= nil and weld.Parent ~= nil then
		weld.C0 = state.baseWeldC0
	end
	debugLog("swing end: " .. character.Name)
end

local function updateSwings()
	local now = os.clock()
	local duration = Config.Broom.SwingSeconds
	for character, state in activeSwings do
		local characterState = character:GetAttribute("State")
		local alive = character.Parent ~= nil and characterState ~= "Downed" and characterState ~= "Dead"
		local t = (now - state.startClock) / duration
		if not alive or t >= 1 then
			finishSwing(character)
		else
			local degrees = swingAngleDegrees(t)
			local motor = state.motor
			if motor ~= nil and motor.Parent ~= nil then
				if Config.Debug.BroomSwing and state.lastAppliedC0 ~= nil and motor.C0 ~= state.lastAppliedC0 then
					debugLog("WARNING: something else changed shoulder C0 between frames")
				end
				-- R15: แกนไหล่ตรงกับตัวละคร หมุนรอบ X (บวก = แขนยกไปข้างหน้า)
				-- R6: C0 ของ Right Shoulder หมุนมา แกน Z คือแกนซ้าย-ขวาของตัว
				local angle = math.rad(degrees)
				local rotation = if state.isR15 then CFrame.Angles(angle, 0, 0) else CFrame.Angles(0, 0, angle)
				local applied = state.baseC0 * rotation
				motor.C0 = applied
				state.lastAppliedC0 = applied
			end
			-- ไม้กวดปัดเพิ่มอีกชั้น (หมุนรอบจุดจับในมือ) · weld อาจถูกสร้างใหม่/ลบ ให้เช็คทุกเฟรม
			local weld = state.broomWeld
			if weld ~= nil and weld.Parent ~= nil then
				local extra = math.rad(degrees * Config.Broom.SwingBroomExtraFactor)
				weld.C0 = state.baseWeldC0 * CFrame.Angles(extra, 0, 0)
			end
		end
	end
	if next(activeSwings) == nil and swingConnection ~= nil then
		swingConnection:Disconnect()
		swingConnection = nil
	end
end

function Fx.broomSwing(character: Model)
	local existing = activeSwings[character]
	if existing ~= nil then
		existing.startClock = os.clock() -- ฟาดซ้ำ: เริ่มท่าใหม่ ใช้ baseC0 เดิม
		debugLog("swing restart (already swinging): " .. character.Name)
		return
	end
	local characterState = character:GetAttribute("State")
	if characterState == "Downed" or characterState == "Dead" then
		debugLog("swing skipped: state=" .. tostring(characterState))
		return
	end
	local motor, isR15 = findShoulder(character)
	local weld = findBroomWeld(character)
	if motor == nil and weld == nil then
		debugLog("swing skipped: no shoulder motor and no broom weld on " .. character.Name)
		return
	end
	activeSwings[character] = {
		motor = motor,
		baseC0 = if motor ~= nil then motor.C0 else CFrame.identity,
		broomWeld = weld,
		baseWeldC0 = if weld ~= nil then weld.C0 else CFrame.identity,
		startClock = os.clock(),
		isR15 = isR15,
		lastAppliedC0 = nil,
	}
	debugLog(
		string.format(
			"swing start: %s rig=%s shoulder=%s broomWeld=%s",
			character.Name,
			if isR15 then "R15" else "R6",
			tostring(motor ~= nil),
			tostring(weld ~= nil)
		)
	)
	if swingConnection == nil then
		swingConnection = RunService.RenderStepped:Connect(updateSwings)
	end
end

return Fx
