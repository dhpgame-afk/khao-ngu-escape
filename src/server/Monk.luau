--!strict
-- Monk: พระที่กุฏิ (NPC สร้างจาก Part ง่าย ๆ สุภาพ ไม่มีอาวุธ ไม่มีเลือด)
-- - ไม่ถูกโจมตี: ไม่ติด tag "Monkey" · ไม่มี Humanoid · Part ทุกชิ้น CanQuery = false (กระสุนทะลุ ไม่โดนเป็นเป้า)
-- - ลิงเลือกเป้าจากผู้เล่นเท่านั้น (ดู Monkeys.collectPlayers) จึงไม่สนใจพระ
-- - อยู่ใน Workspace.MapObjects (โฟลเดอร์ถาวร ไม่ถูกล้างตอนจบภารกิจ) · สร้างตั้งแต่เริ่มเซิร์ฟเวอร์ (Monk.ensure) ยืนหน้าบันไดกุฏิ
-- - ถ้าเจ้าของทำโมเดลชื่อ Config.Monk.Name ไว้ใน Workspace.MapObjects เอง จะใช้ของเจ้าของ (ไม่สร้างทับ)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapSetup = require(script.Parent.MapSetup)

local MonkCfg = Config.Monk
local KutiCfg = Config.Kuti

local Monk = {}

-- ขนาดชิ้นส่วน (ภาพล้วน ๆ ไม่กระทบกติกาเกม)
local ROBE_SIZE = Vector3.new(2.6, 3.2, 1.8)
local CHEST_SIZE = Vector3.new(2.4, 1.8, 1.5)
local SASH_SIZE = Vector3.new(1.0, 2.2, 1.7)
local HEAD_SIZE = Vector3.new(1.5, 1.5, 1.5)
local ARM_SIZE = Vector3.new(0.6, 1.6, 0.6)
local HANDS_SIZE = Vector3.new(0.7, 0.5, 0.5)
local LABEL_SIZE = UDim2.fromScale(4, 1.4)
local LABEL_OFFSET = Vector3.new(0, 2.2, 0)

local function addPart(
	model: Model,
	base: CFrame,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	offset: Vector3,
	color: Color3,
	material: Enum.Material
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false -- ไม่ขวางทาง
	part.CanQuery = false -- กระสุน/เรย์ทะลุ
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = base * CFrame.new(offset)
	part.Parent = model
	return part
end

-- สร้างพระยืนที่ groundPosition (จุดบนพื้น) หันหน้าไปทาง +Z (ใต้) · ลงใน parent
function Monk.build(parent: Instance, groundPosition: Vector3): Model
	local model = Instance.new("Model")
	model.Name = MonkCfg.Name
	-- ให้ client เห็นพระเสมอ (StreamingEnabled) ไม่งั้นปุ่มถวายอาหารไม่โผล่เพราะ client หาพระไม่เจอ
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local base = CFrame.lookAt(groundPosition, groundPosition + Vector3.new(0, 0, 1))

	local robeHeight = ROBE_SIZE.Y
	-- ชายจีวรช่วงล่าง · อก · ผ้าพาดไหล่ (สีเข้ม) · แขน/มือพนม · หัวโล้น
	local robe = addPart(
		model,
		base,
		"Robe",
		Enum.PartType.Block,
		ROBE_SIZE,
		Vector3.new(0, robeHeight / 2, 0),
		MonkCfg.RobeColor,
		Enum.Material.Fabric
	)
	local chestY = robeHeight + CHEST_SIZE.Y / 2
	addPart(
		model,
		base,
		"Chest",
		Enum.PartType.Block,
		CHEST_SIZE,
		Vector3.new(0, chestY, 0),
		MonkCfg.RobeColor,
		Enum.Material.Fabric
	)
	addPart(
		model,
		base,
		"Sash",
		Enum.PartType.Block,
		SASH_SIZE,
		Vector3.new(-0.7, chestY - 0.1, 0.05),
		MonkCfg.SashColor,
		Enum.Material.Fabric
	)
	for _, side in { -1, 1 } do
		addPart(
			model,
			base,
			"Arm",
			Enum.PartType.Block,
			ARM_SIZE,
			Vector3.new(side * 1.5, chestY - 0.1, -0.2),
			MonkCfg.RobeColor,
			Enum.Material.Fabric
		)
	end
	addPart(
		model,
		base,
		"Hands",
		Enum.PartType.Block,
		HANDS_SIZE,
		Vector3.new(0, chestY + 0.1, -0.95),
		MonkCfg.SkinColor,
		Enum.Material.SmoothPlastic
	)
	local head = addPart(
		model,
		base,
		"Head",
		Enum.PartType.Ball,
		HEAD_SIZE,
		Vector3.new(0, robeHeight + CHEST_SIZE.Y + HEAD_SIZE.Y / 2 - 0.1, 0),
		MonkCfg.SkinColor,
		Enum.Material.SmoothPlastic
	)

	model.PrimaryPart = robe

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MonkLabel"
	billboard.Size = LABEL_SIZE
	billboard.StudsOffset = LABEL_OFFSET
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = Config.Carry.LabelMaxDistance
	billboard.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = MonkCfg.LabelText
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.Parent = billboard

	model.Parent = parent
	return model
end

-- โมเดลพระที่มีอยู่แล้วใน Workspace.MapObjects (ถ้ามี)
function Monk.find(): Instance?
	return MapSetup.getObjectsFolder():FindFirstChild(MonkCfg.Name)
end

-- ตำแหน่งพระ (กึ่งกลางโมเดล) · nil ถ้ายังไม่มี
function Monk.positionOf(): Vector3?
	local inst = Monk.find()
	if inst == nil then
		return nil
	end
	if inst:IsA("Model") then
		return inst:GetPivot().Position
	elseif inst:IsA("BasePart") then
		return inst.Position
	end
	return nil
end

-- ให้มีพระยืนหน้าบันไดกุฏิ (ทางใต้ของจุด Kuti) ติดพื้น Terrain · ไม่สร้างซ้ำถ้ามีอยู่แล้ว
function Monk.ensure()
	if Monk.find() ~= nil then
		return
	end
	local kuti = MapSetup.getMarkerPosition("Kuti")
	if kuti == nil then
		warn(
			"[Monk] ไม่พบจุดกุฏิ (MapMarkers.Kuti) — ยังสร้างพระไม่ได้ ถวายอาหารไม่ได้"
		)
		return
	end
	local x = kuti.X
	-- ยืนบนพื้นดินพ้นปลายบันไดจริงของกุฏิที่โค้ดสร้าง (ผู้เล่นยืนถึงได้แน่) · กุฏิเจ้าของทำเอง → ใช้สูตรตามค่าเริ่มต้น
	local stairFootZ = MapSetup.getKutiStairFootZ()
		or (kuti.Z + KutiCfg.Depth / 2 + KutiCfg.StepCount * KutiCfg.StepDepth)
	local z = stairFootZ + MonkCfg.StepsGapStuds
	local ground = MapSetup.groundOnTerrain(x, z)
	if ground == nil then
		-- เรย์ไม่โดน Terrain → ใช้ความสูงจุดกุฏิ พระอาจลอย/จม
		warn(
			"[Monk] เรย์หาพื้นให้พระไม่โดน Terrain — ใช้ความสูงของจุดกุฏิแทน ตรวจตำแหน่งพระ"
		)
		ground = Vector3.new(x, kuti.Y, z)
	end
	Monk.build(MapSetup.getObjectsFolder(), ground)
end

return Monk
