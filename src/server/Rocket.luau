--!strict
-- Rocket: ตัวบั้งไฟจริงบนแมพ (ฝั่งเซิร์ฟเวอร์) — สร้างโมเดล / จุดมัดตัว / ควันสายชนวน / ยิงขึ้นฟ้า
-- - โมดูลนี้ "ไม่ตัดสินกติกา" (ใครจุดชนวนได้ ใครได้รางวัลเท่าไร อยู่ใน Mission) แค่ทำให้ของจริงขยับตามคำสั่ง
-- - สร้างตอนเริ่มเซิร์ฟเวอร์ที่ฐานบั้งไฟ (MapMarkers.RocketPad) ถ้ายังไม่มี Workspace.MapObjects.<Config.Rocket.Build.ModelName>
--   โครง: Model "Rocket" { Frame (แท่นยิง · อยู่กับที่) · Body (ตัวบั้งไฟ + จุดมัด TieSpot1..4 · ลอยขึ้นตอนยิง) }
--   ถ้าเจ้าของทำเอง: ใส่ Model ชื่อเดียวกัน — Model ย่อย "Body" ลอยขึ้นตอนยิง (ไม่มี = ทั้งโมเดลลอย) · Part "TieSpot1".. = จุดมัด
--   (ไม่มี TieSpot ในโมเดลของเจ้าของ ระบบสร้างจุดมัดล่องหนรอบโมเดลให้)
-- - ผู้เล่นที่มัดตัวแล้วถูกตรึง (Anchored) ที่จุดมัด · ตอนยิง เซิร์ฟเวอร์ขยับ CFrame ของบั้งไฟและคนมัดตัวด้วยกัน (ไม่พึ่งฟิสิกส์)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MapSetup = require(script.Parent.MapSetup)
local AntiTeleport = require(script.Parent.AntiTeleport)

local RC = Config.Rocket
local BC = RC.Build

type TieRecord = {
	spotIndex: number,
	relative: CFrame, -- ตำแหน่ง HumanoidRootPart เทียบกับตัวบั้งไฟ (ตอนมัด) · ตอนยิงใช้คูณตามไปด้วย
	root: BasePart,
	humanoid: Humanoid?,
	walkSpeed: number,
	jumpHeight: number,
	jumpPower: number,
}

local Rocket = {}

local model: Model? = nil
local flyer: PVInstance? = nil -- ส่วนที่ลอยขึ้นตอนยิง
local homeCFrame = CFrame.new() -- ท่าตั้งต้นของ flyer
local homePosition = Vector3.zero -- กึ่งกลางแท่น (ไว้วัดระยะ)
local spots: { BasePart } = {}
local fuseEmitters: { ParticleEmitter } = {}
local thrustEmitters: { ParticleEmitter } = {}
local tied: { [Player]: TieRecord } = {}
local spotOwner: { [number]: Player } = {}

-- ค่าภาพล้วน ๆ (ไม่กระทบกติกา)
local SPARK_COLOR = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 110, 30))
local SMOKE_COLOR = ColorSequence.new(Color3.fromRGB(235, 235, 235), Color3.fromRGB(150, 150, 150))
local FLAME_COLOR = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 90, 20))
local SMOKE_SIZE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 3),
	NumberSequenceKeypoint.new(1, 9),
})
local SMOKE_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.3),
	NumberSequenceKeypoint.new(1, 1),
})
local FLAME_SIZE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 3),
	NumberSequenceKeypoint.new(1, 0.5),
})
local SPARK_SIZE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.6),
	NumberSequenceKeypoint.new(1, 0),
})

-- ===== ตัวช่วย =====

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

local function addPart(
	parent: Instance,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	solid: boolean
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = solid
	part.CanQuery = false -- กระสุนทะลุ (ไม่งั้นคนมัดตัวที่ยืนชิดตัวบั้งไฟยิงไม่ออก)
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- กระบอกตั้งตรง: Part ทรงกระบอกมีแกนยาวเป็นแกน X → หมุนรอบ Z 90° ให้แกนชี้ขึ้น
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local function addCylinder(
	parent: Instance,
	name: string,
	diameter: number,
	height: number,
	center: CFrame,
	color: Color3,
	material: Enum.Material,
	solid: boolean
): Part
	return addPart(
		parent,
		name,
		Enum.PartType.Cylinder,
		Vector3.new(height, diameter, diameter),
		center * UPRIGHT,
		color,
		material,
		solid
	)
end

local function makeEmitter(parent: Attachment, name: string, rate: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Rate = rate
	emitter.Enabled = false -- เปิดตอนจุดชนวน/ยิง
	emitter.Parent = parent
	return emitter
end

-- ===== สร้างโมเดล =====

local function buildRocket(parent: Instance, ground: Vector3): Model
	local base = CFrame.new(ground) -- ระนาบพื้น ณ ฐานบั้งไฟ
	local deckThickness = BC.DeckSize.Y
	local deckTop = BC.DeckHeight

	local root = Instance.new("Model")
	root.Name = BC.ModelName
	root.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- client เห็นบั้งไฟตลอด (StreamingEnabled)

	-- แท่นยิง (อยู่กับที่)
	local frame = Instance.new("Model")
	frame.Name = "Frame"
	frame.Parent = root
	local deck = addPart(
		frame,
		"Deck",
		Enum.PartType.Block,
		BC.DeckSize,
		base * CFrame.new(0, deckTop - deckThickness / 2, 0),
		BC.DeckColor,
		Enum.Material.WoodPlanks,
		true
	)
	deck.CanQuery = true
	root.PrimaryPart = deck
	local legTop = deckTop - deckThickness
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local leg = addPart(
				frame,
				"Leg",
				Enum.PartType.Block,
				BC.LegSize,
				base
					* CFrame.new(
						sx * (BC.DeckSize.X / 2 - BC.LegInset),
						legTop - BC.LegSize.Y / 2,
						sz * (BC.DeckSize.Z / 2 - BC.LegInset)
					),
				BC.FrameColor,
				Enum.Material.Wood,
				true
			)
			leg.CanQuery = true
		end
	end
	-- เสากรอบด้านหลัง (ทิศเหนือ = -Z) + คานขวาง 2 ชั้น
	local backZ = -(BC.DeckSize.Z / 2 - 1)
	for _, sx in { -1, 1 } do
		addPart(
			frame,
			"FramePost",
			Enum.PartType.Block,
			BC.FramePostSize,
			base * CFrame.new(sx * BC.FramePostSpacing / 2, deckTop + BC.FramePostSize.Y / 2, backZ),
			BC.FrameColor,
			Enum.Material.Wood,
			false
		)
	end
	for _, fraction in { 0.45, 0.85 } do
		addPart(
			frame,
			"FrameBar",
			Enum.PartType.Block,
			BC.FrameBarSize,
			base * CFrame.new(0, deckTop + BC.FramePostSize.Y * fraction, backZ),
			BC.FrameColor,
			Enum.Material.Wood,
			false
		)
	end

	-- ตัวบั้งไฟ (ลอยขึ้นตอนยิง)
	local body = Instance.new("Model")
	body.Name = "Body"
	body.Parent = root
	local bodyBottom = base * CFrame.new(0, deckTop, 0)
	local shaft = addCylinder(
		body,
		"Shaft",
		BC.BodyDiameter,
		BC.BodyHeight,
		bodyBottom * CFrame.new(0, BC.BodyHeight / 2, 0),
		BC.BodyColor,
		Enum.Material.Wood,
		true
	)
	body.PrimaryPart = shaft
	for i = 1, BC.NodeCount do
		addCylinder(
			body,
			"BambooNode",
			BC.BodyDiameter + BC.NodeDiameterExtra,
			BC.NodeHeight,
			bodyBottom * CFrame.new(0, BC.BodyHeight * i / (BC.NodeCount + 1), 0),
			BC.NodeColor,
			Enum.Material.Wood,
			false
		)
	end
	-- ปลายแหลมเป็นขั้น แดง/ทองสลับ
	for tier = 1, BC.NoseTierCount do
		local diameter = BC.NoseBaseDiameter * (1 - (tier - 1) / BC.NoseTierCount)
		addCylinder(
			body,
			"Nose" .. tier,
			diameter,
			BC.NoseTierHeight,
			bodyBottom * CFrame.new(0, BC.BodyHeight + (tier - 0.5) * BC.NoseTierHeight, 0),
			BC.NoseColors[(tier - 1) % #BC.NoseColors + 1],
			Enum.Material.SmoothPlastic,
			false
		)
	end
	local tipY = BC.BodyHeight + BC.NoseTierCount * BC.NoseTierHeight
	local tip = addPart(
		body,
		"Tip",
		Enum.PartType.Ball,
		Vector3.new(BC.TipDiameter, BC.TipDiameter, BC.TipDiameter),
		bodyBottom * CFrame.new(0, tipY + BC.TipDiameter * 0.3, 0),
		BC.NoseColors[#BC.NoseColors],
		Enum.Material.Metal,
		false
	)
	-- ครีบหาง 2 แผ่นไขว้ (ยื่นออกตามแกน X/Z)
	for _, angle in { 0, math.pi / 2 } do
		addPart(
			body,
			"Fin",
			Enum.PartType.Block,
			BC.FinSize,
			bodyBottom * CFrame.Angles(0, angle, 0) * CFrame.new(0, BC.FinSize.Y / 2, 0),
			BC.FinColor,
			Enum.Material.Wood,
			false
		)
	end

	-- ป้ายลอยเหนือปลายบั้งไฟ
	local gui = Instance.new("BillboardGui")
	gui.Name = "RocketLabel"
	gui.Size = BC.LabelSize
	gui.StudsOffset = Vector3.new(0, BC.LabelAbove, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = BC.LabelMaxDistance
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Text = BC.LabelText
	text.Parent = gui
	gui.Parent = tip

	-- สายชนวนที่ก้นบั้งไฟ (เยื้องจากครีบ) + ประกายตอนจุดชนวน
	local fuseAngle = math.pi / 8
	local fuseCf = bodyBottom
		* CFrame.Angles(0, fuseAngle, 0)
		* CFrame.new(BC.BodyDiameter / 2 + 0.2, BC.FuseSize.Y / 2 + 0.3, 0)
	local fuse =
		addPart(body, "Fuse", Enum.PartType.Block, BC.FuseSize, fuseCf, BC.FuseColor, Enum.Material.Fabric, false)
	local fuseTip = Instance.new("Attachment")
	fuseTip.Name = "FuseTip"
	fuseTip.Position = Vector3.new(0, BC.FuseSize.Y / 2, 0)
	fuseTip.Parent = fuse
	local sparks = makeEmitter(fuseTip, "FuseSparks", RC.FuseSparkRate)
	sparks.Color = SPARK_COLOR
	sparks.Size = SPARK_SIZE
	sparks.Lifetime = NumberRange.new(0.3, 0.7)
	sparks.Speed = NumberRange.new(4, 9)
	sparks.SpreadAngle = Vector2.new(70, 70)
	sparks.LightEmission = 1

	-- ควันและเปลวไฟใต้ฐานตอนยิง (ปล่อยลงทางก้นบั้งไฟ)
	local exhaust = Instance.new("Attachment")
	exhaust.Name = "Exhaust"
	exhaust.Parent = shaft
	-- วางที่ก้นบั้งไฟ หันตามแกนโลก (Bottom = ลงพื้น) ไม่ตามการหมุนของทรงกระบอก
	exhaust.WorldCFrame = CFrame.new((bodyBottom * CFrame.new(0, 0.3, 0)).Position)
	local smoke = makeEmitter(exhaust, "LaunchSmoke", RC.LaunchSmokeRate)
	smoke.Color = SMOKE_COLOR
	smoke.Size = SMOKE_SIZE
	smoke.Transparency = SMOKE_FADE
	smoke.Lifetime = NumberRange.new(1.5, 2.5)
	smoke.Speed = NumberRange.new(6, 14)
	smoke.SpreadAngle = Vector2.new(35, 35)
	smoke.EmissionDirection = Enum.NormalId.Bottom
	smoke.LockedToPart = false
	local flame = makeEmitter(exhaust, "LaunchFlame", RC.LaunchFlameRate)
	flame.Color = FLAME_COLOR
	flame.Size = FLAME_SIZE
	flame.Lifetime = NumberRange.new(0.3, 0.6)
	flame.Speed = NumberRange.new(14, 24)
	flame.SpreadAngle = Vector2.new(15, 15)
	flame.EmissionDirection = Enum.NormalId.Bottom
	flame.LightEmission = 1
	flame.LockedToPart = false

	-- จุดมัดตัว: วงเชือกบนพื้นแท่น (ที่ยืน) + ปมเชือกทองที่ตัวบั้งไฟ ระดับเอว · เริ่มที่มุม 45° ห่างกันเท่า ๆ กัน (เลี่ยงครีบ)
	for i = 1, BC.TieSpotCount do
		local angle = (i - 0.5) * 2 * math.pi / BC.TieSpotCount
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		addCylinder(
			body,
			"TieSpot" .. i,
			BC.TieRingDiameter,
			BC.TieRingThickness,
			bodyBottom * CFrame.new(direction * BC.TieSpotRadius + Vector3.new(0, BC.TieRingThickness / 2 + 0.05, 0)),
			BC.TieRingColor,
			Enum.Material.Fabric,
			false
		)
		addPart(
			body,
			"TieKnot" .. i,
			Enum.PartType.Ball,
			Vector3.new(BC.TieKnotSize, BC.TieKnotSize, BC.TieKnotSize),
			bodyBottom * CFrame.new(direction * (BC.BodyDiameter / 2) + Vector3.new(0, BC.TieKnotHeight, 0)),
			BC.TieKnotColor,
			Enum.Material.Fabric,
			false
		)
	end

	root.Parent = parent
	return root
end

-- ===== ผูกกับโมเดลที่มีอยู่ (ที่เราสร้างหรือของเจ้าของ) =====

local function collectSpots(root: Model): { BasePart }
	local list: { BasePart } = {}
	for i = 1, BC.TieSpotCount do
		local found = root:FindFirstChild("TieSpot" .. i, true)
		if found ~= nil and found:IsA("BasePart") then
			table.insert(list, found)
		end
	end
	return list
end

-- โมเดลของเจ้าของที่ไม่มีจุดมัด: สร้างจุดล่องหนรอบโมเดล ที่ระดับล่างสุดของโมเดล + ความสูงแท่น
local function createFallbackSpots(root: Model, parent: Instance): { BasePart }
	local boxCf, boxSize = root:GetBoundingBox()
	local bottomY = boxCf.Position.Y - boxSize.Y / 2
	local list: { BasePart } = {}
	for i = 1, BC.TieSpotCount do
		local angle = (i - 0.5) * 2 * math.pi / BC.TieSpotCount
		local part = Instance.new("Part")
		part.Name = "TieSpot" .. i
		part.Size = Vector3.new(1, 0.2, 1)
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Position = Vector3.new(
			boxCf.Position.X + math.cos(angle) * BC.TieSpotRadius,
			bottomY + BC.DeckHeight,
			boxCf.Position.Z + math.sin(angle) * BC.TieSpotRadius
		)
		part.Parent = parent
		table.insert(list, part)
	end
	warn(
		"[Rocket] โมเดลบั้งไฟไม่มี Part TieSpot1.. — สร้างจุดมัดล่องหนให้รอบโมเดล ปรับตำแหน่งเองได้"
	)
	return list
end

local function collectEmitters(root: Instance, name: string): { ParticleEmitter }
	local list: { ParticleEmitter } = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("ParticleEmitter") and descendant.Name == name then
			table.insert(list, descendant)
		end
	end
	return list
end

local function bind(root: Model)
	model = root
	local body = root:FindFirstChild("Body")
	if body ~= nil and body:IsA("PVInstance") then
		flyer = body
	else
		flyer = root
	end
	local flyerNow = flyer :: PVInstance
	homeCFrame = flyerNow:GetPivot()
	homePosition = root:GetPivot().Position
	spots = collectSpots(root)
	if #spots == 0 then
		spots = createFallbackSpots(root, flyerNow)
	end
	fuseEmitters = collectEmitters(root, "FuseSparks")
	thrustEmitters = collectEmitters(root, "LaunchSmoke")
	for _, emitter in collectEmitters(root, "LaunchFlame") do
		table.insert(thrustEmitters, emitter)
	end
end

-- ===== API =====

-- เรียกครั้งเดียวตอนเริ่มเซิร์ฟเวอร์ (หลัง MapSetup.run) · ไม่สร้างซ้ำถ้ามีอยู่แล้ว
function Rocket.ensure()
	if model ~= nil and model.Parent ~= nil then
		return
	end
	local objects = MapSetup.getObjectsFolder()
	local existing = objects:FindFirstChild(BC.ModelName)
	if existing == nil then
		local pad = MapSetup.getMarkerPosition("RocketPad")
		if pad == nil then
			warn(
				"[Rocket] ไม่พบจุด RocketPad ใน MapMarkers — สร้างบั้งไฟไม่ได้"
			)
			return
		end
		local ground = MapSetup.groundOnTerrain(pad.X, pad.Z)
		if ground == nil then
			warn(
				"[Rocket] เรย์หาพื้นให้บั้งไฟไม่โดน Terrain — ใช้ความสูงของจุด RocketPad บั้งไฟอาจลอย/จม"
			)
			ground = Vector3.new(pad.X, pad.Y, pad.Z)
		end
		existing = buildRocket(objects, ground)
		warn(
			"[Rocket] สร้างบั้งไฟอัตโนมัติที่ Workspace."
				.. Config.Map.ObjectsFolderName
				.. "."
				.. BC.ModelName
				.. " — ลบทิ้งแล้วใส่ของตัวเองชื่อเดียวกันได้"
		)
	end
	if not existing:IsA("Model") then
		warn("[Rocket] Workspace.MapObjects." .. BC.ModelName .. " ต้องเป็น Model")
		return
	end
	bind(existing)
end

function Rocket.isReady(): boolean
	return model ~= nil and model.Parent ~= nil and flyer ~= nil
end

-- กึ่งกลางแท่น (ท่าตั้งต้น · ไม่ขยับตามตอนยิง) · nil = ยังไม่มีบั้งไฟ
function Rocket.getPosition(): Vector3?
	if not Rocket.isReady() then
		return nil
	end
	return homePosition
end

-- position อยู่ใกล้บั้งไฟไหม: ระยะแนวราบไม่เกิน range และความสูงต่างไม่เกิน VerticalTolerance
function Rocket.isNear(position: Vector3, range: number): boolean
	if not Rocket.isReady() then
		return false
	end
	local dx, dz = position.X - homePosition.X, position.Z - homePosition.Z
	if math.sqrt(dx * dx + dz * dz) > range then
		return false
	end
	return math.abs(position.Y - homePosition.Y) <= RC.VerticalTolerance
end

-- บันทึกการมัดยังใช้ได้ไหม: ต้องเป็นตัวละครตัวเดิมที่ยังอยู่ในเกม (เกิดใหม่/ตัวละครถูกลบ = การมัดเดิมเป็นโมฆะ)
-- ตัวละครใหม่จึงไม่ติดสถานะ "มัดแล้ว" (ไม่รับดาเมจ ไม่ถูกล็อกการถือของ) จากตัวเก่า
local function recordValid(player: Player, record: TieRecord): boolean
	return record.root.Parent ~= nil and player.Character == record.root.Parent
end

function Rocket.isTied(player: Player): boolean
	local record = tied[player]
	return record ~= nil and recordValid(player, record)
end

function Rocket.tiedPlayers(): { Player }
	local list: { Player } = {}
	for player, record in tied do
		if recordValid(player, record) then
			table.insert(list, player)
		end
	end
	return list
end

function Rocket.tiedCount(): number
	return #Rocket.tiedPlayers()
end

function Rocket.spotCount(): number
	return #spots
end

function Rocket.freeSpotCount(): number
	return #spots - Rocket.tiedCount()
end

-- ปลดผู้เล่นออกจากจุดมัด (ออกเกม / จบภารกิจ) · restoreCharacter = true คืนการเดิน/ปลดตรึงตัวละคร
function Rocket.untie(player: Player, restoreCharacter: boolean?)
	local record = tied[player]
	if record == nil then
		return
	end
	tied[player] = nil
	if spotOwner[record.spotIndex] == player then
		spotOwner[record.spotIndex] = nil
	end
	if restoreCharacter and record.root.Parent ~= nil then
		record.root.Anchored = false
		AntiTeleport.reset(player)
		local humanoid = record.humanoid
		if humanoid ~= nil and humanoid.Parent ~= nil then
			humanoid.WalkSpeed = record.walkSpeed
			humanoid.JumpHeight = record.jumpHeight
			humanoid.JumpPower = record.jumpPower
		end
	end
end

-- ล้างการมัดที่เป็นโมฆะ: ตัวละครเปลี่ยน/หาย หรือ isAlive(player) คืน false (ตายแล้ว) · คืนจำนวนที่ล้าง
-- Mission เรียกทุกรอบนับถอยหลังและก่อนคิดรางวัล · คืนจุดมัดให้คนอื่นใช้ได้
function Rocket.validate(isAlive: ((Player) -> boolean)?): number
	local stale: { Player } = {}
	for player, record in tied do
		if not recordValid(player, record) or (isAlive ~= nil and not isAlive(player)) then
			table.insert(stale, player)
		end
	end
	for _, player in stale do
		Rocket.untie(player, true)
	end
	return #stale
end

-- มัดผู้เล่นเข้าจุดมัดว่างที่ใกล้ที่สุด · ตรึงตัว (ขยับไม่ได้ ยิงได้) · คืน false ถ้าไม่มีที่ว่าง/ไม่มีตัวละคร/มัดไปแล้ว
function Rocket.tie(player: Player): boolean
	local activeFlyer = flyer
	if activeFlyer == nil then
		return false
	end
	Rocket.validate(nil) -- เคลียร์การมัดเก่าที่ตัวละครหายไปแล้ว ไม่ให้กินจุดมัด
	if tied[player] ~= nil then
		return false
	end
	local root = rootOf(player)
	if root == nil then
		return false
	end
	local bestIndex: number? = nil
	local bestDistance = math.huge
	for index, spot in spots do
		if spotOwner[index] == nil then
			local d = (spot.Position - root.Position).Magnitude
			if d < bestDistance then
				bestDistance = d
				bestIndex = index
			end
		end
	end
	if bestIndex == nil then
		return false
	end

	local spot = spots[bestIndex]
	local standPosition = spot.Position + Vector3.new(0, RC.TieRootHeight, 0)
	-- หันออกจากตัวบั้งไฟ (ไปทางที่ลิงจะมา)
	local outward = Vector3.new(spot.Position.X - homePosition.X, 0, spot.Position.Z - homePosition.Z)
	if outward.Magnitude < 0.1 then
		outward = Vector3.new(0, 0, 1)
	end
	local cframe = CFrame.lookAt(standPosition, standPosition + outward.Unit)

	local humanoid = if player.Character ~= nil then player.Character:FindFirstChildOfClass("Humanoid") else nil
	tied[player] = {
		spotIndex = bestIndex,
		relative = activeFlyer:GetPivot():ToObjectSpace(cframe),
		root = root,
		humanoid = humanoid,
		walkSpeed = if humanoid ~= nil then humanoid.WalkSpeed else Config.Player.WalkSpeed,
		jumpHeight = if humanoid ~= nil then humanoid.JumpHeight else 0,
		jumpPower = if humanoid ~= nil then humanoid.JumpPower else 0,
	}
	spotOwner[bestIndex] = player

	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = cframe
	root.Anchored = true
	AntiTeleport.reset(player)
	if humanoid ~= nil then
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
	end
	return true
end

local function setEmitters(list: { ParticleEmitter }, enabled: boolean)
	for _, emitter in list do
		if emitter.Parent ~= nil then
			emitter.Enabled = enabled
		end
	end
end

-- สายชนวนมีประกายหรือไม่ (จุดชนวนแล้ว = true)
function Rocket.setLit(lit: boolean)
	setEmitters(fuseEmitters, lit)
end

-- ควัน/เปลวไฟใต้ฐาน
function Rocket.setThrust(on: boolean)
	setEmitters(thrustEmitters, on)
end

-- ยิงบั้งไฟขึ้นฟ้าตรง ๆ rise stud ใน seconds วิ (ออกตัวช้า เร่งขึ้นเรื่อย ๆ) พร้อมคนที่มัดตัวไว้
-- ต้องเรียกจากเธรดที่ yield ได้ · คืน false ถ้า stillValid() เป็น false ระหว่างทาง (ผู้เรียกต้องเรียก Rocket.reset เอง)
function Rocket.launch(seconds: number, rise: number, stillValid: () -> boolean): boolean
	local activeFlyer = flyer
	if activeFlyer == nil then
		return true
	end
	local start = activeFlyer:GetPivot()
	Rocket.setLit(false)
	Rocket.setThrust(true)
	local elapsed = 0
	while elapsed < seconds do
		local dt = RunService.Heartbeat:Wait()
		if not stillValid() then
			return false
		end
		elapsed += dt
		local alpha = math.min(elapsed / seconds, 1)
		local cframe = start + Vector3.new(0, rise * alpha * alpha, 0)
		activeFlyer:PivotTo(cframe)
		for player, record in tied do
			if recordValid(player, record) then
				record.root.CFrame = cframe * record.relative
				record.root.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end
	return true
end

-- คืนทุกอย่างเป็นท่าตั้งต้น: ปลดทุกคน ปิดควัน วางบั้งไฟกลับฐาน (จบภารกิจ / เริ่มเซิร์ฟเวอร์)
function Rocket.reset()
	local players: { Player } = {}
	for player in tied do
		table.insert(players, player)
	end
	for _, player in players do
		Rocket.untie(player, true)
	end
	spotOwner = {}
	Rocket.setLit(false)
	Rocket.setThrust(false)
	local activeFlyer = flyer
	if activeFlyer ~= nil and activeFlyer.Parent ~= nil then
		activeFlyer:PivotTo(homeCFrame)
	end
end

Players.PlayerRemoving:Connect(function(player: Player)
	Rocket.untie(player, false) -- ออกเกม: แค่คืนจุดมัด (ตัวละครหายไปเอง)
end)

-- ตัวละครถูกลบ/เกิดใหม่ (ตาย รีเซ็ต) → ปล่อยจุดมัดทันที (ไม่ปล่อยให้ผีมัดค้าง)
local function watchCharacterRemoving(player: Player)
	player.CharacterRemoving:Connect(function()
		Rocket.untie(player, false)
	end)
end
Players.PlayerAdded:Connect(watchCharacterRemoving)
for _, existingPlayer in Players:GetPlayers() do
	watchCharacterRemoving(existingPlayer)
end

return Rocket
