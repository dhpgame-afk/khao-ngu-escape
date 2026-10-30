--!strict
-- MapSetup: เตรียมแมพตอนเริ่มเซิร์ฟเวอร์ (ต้องเรียกก่อนระบบอื่นทั้งหมด — Mission / Monkeys อ่านจุดสำคัญจากที่นี่)
-- 1) จุดสำคัญ Workspace.MapMarkers (Kuti, Nest1–4, RocketPad): สร้างเฉพาะจุดที่ยังไม่มี · ไม่ย้าย/ไม่ทับจุดที่มีอยู่แล้ว
-- 2) กุฏิ Workspace.MapObjects.<Config.Kuti.Name>: สร้างจาก Part ถ้ายังไม่มี (เจ้าของใส่ของตัวเองแทนได้)
-- 3) กำแพงล่องหนรอบแมพ Workspace.MapObjects.<Config.Boundary.FolderName>: สร้างถ้ายังไม่มี (บั้งไฟสร้างโดย Rocket.ensure)
-- ตัวเลขทั้งหมดอยู่ใน Config.Map / Config.Kuti

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local MapCfg = Config.Map
local KutiCfg = Config.Kuti
local BoundaryCfg = Config.Boundary
local LaunchCfg = Config.Launch

type MarkerDef = {
	label: string,
	x: number,
	z: number,
	color: Color3,
	size: Vector3,
}

local MapSetup = {}

-- ===== พื้นดิน =====

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { Workspace.Terrain }

-- ยิงเรย์ลงหาผิว Terrain ที่ (x, z) · คืน nil ถ้าไม่โดน (นับเฉพาะ Terrain ไม่นับกุฏิ/ต้นไม้)
function MapSetup.groundOnTerrain(x: number, z: number): Vector3?
	local result = Workspace:Raycast(
		Vector3.new(x, LaunchCfg.RaycastStartHeight, z),
		Vector3.new(0, -LaunchCfg.RaycastLength, 0),
		terrainParams
	)
	if result ~= nil then
		return result.Position
	end
	return nil
end

-- ===== โฟลเดอร์ =====

local function getOrCreateFolder(name: string): Instance
	local existing = Workspace:FindFirstChild(name)
	if existing ~= nil then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = Workspace
	return folder
end

-- โฟลเดอร์สิ่งถาวรบนแมพ (กุฏิ พระ) — ไม่ถูกล้างตอนจบภารกิจ
function MapSetup.getObjectsFolder(): Instance
	return getOrCreateFolder(MapCfg.ObjectsFolderName)
end

-- ตำแหน่งจุดสำคัญจาก MapMarkers · nil ถ้าไม่มี
function MapSetup.getMarkerPosition(name: string): Vector3?
	local folder = Workspace:FindFirstChild(MapCfg.MarkersFolderName)
	if folder == nil then
		return nil
	end
	local inst = folder:FindFirstChild(name)
	if inst == nil then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	return nil
end

-- ===== จุดสำคัญ =====

local function addMarkerLabel(part: BasePart, text: string)
	local gui = Instance.new("BillboardGui")
	gui.Size = MapCfg.MarkerLabelSize
	gui.StudsOffset = MapCfg.MarkerLabelStudsOffset
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Text = text
	label.Parent = gui
	gui.Parent = part
end

local function createMarker(folder: Instance, name: string, def: MarkerDef): number
	local ground = MapSetup.groundOnTerrain(def.x, def.z)
	local groundY = if ground ~= nil then ground.Y else LaunchCfg.FallbackGroundY
	if ground == nil then
		warn(
			"[MapSetup] เรย์ไม่โดน Terrain ที่จุด "
				.. name
				.. " — ใช้ความสูงสำรอง ตรวจตำแหน่งจุดนี้"
		)
	end

	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = def.color
	part.Size = def.size
	part.Position = Vector3.new(def.x, groundY + def.size.Y / 2, def.z)
	if MapCfg.MarkersVisible then
		part.Transparency = MapCfg.MarkerVisibleTransparency
		addMarkerLabel(part, def.label)
	else
		part.Transparency = 1
	end
	part.Parent = folder
	return groundY
end

-- จุดที่เจ้าของวางไว้แล้ว: ไม่ย้าย ไม่ลบ · แค่ซ่อนภาพตอนเล่น (ถ้าไม่ได้เปิด MarkersVisible) — ไม่มีผลกับไฟล์แมพที่เซฟ
local function hideExistingMarker(inst: Instance)
	if MapCfg.MarkersVisible then
		return
	end
	if inst:IsA("BasePart") then
		inst.Transparency = 1
		inst.CanCollide = false
		inst.CanQuery = false
	end
	for _, descendant in inst:GetDescendants() do
		if descendant:IsA("BillboardGui") then
			descendant.Enabled = false
		end
	end
end

local function ensureMarkers()
	local folder = getOrCreateFolder(MapCfg.MarkersFolderName)
	local defs = MapCfg.Markers :: any
	local createdNames: { string } = {}
	for _, name in MapCfg.MarkerNames do
		local existing = folder:FindFirstChild(name)
		if existing ~= nil then
			hideExistingMarker(existing)
		else
			local def: MarkerDef? = defs[name]
			if def == nil then
				warn(
					"[MapSetup] Config.Map.Markers ไม่มีค่าเริ่มต้นของจุด "
						.. name
				)
			else
				createMarker(folder, name, def)
				table.insert(createdNames, name)
			end
		end
	end
	if #createdNames > 0 then
		warn(
			"[MapSetup] สร้างจุดสำคัญที่ยังไม่มีให้อัตโนมัติ ("
				.. #createdNames
				.. " จุด): "
				.. table.concat(createdNames, ", ")
				.. " — ย้ายได้ใน Workspace."
				.. MapCfg.MarkersFolderName
		)
	end
end

-- ===== กุฏิ =====

-- ใช้ตอนวาง Part ของกุฏิทุกชิ้น: นิ่ง ชนได้ กระสุนชนได้ (CanQuery) เหมือนฉากทั่วไป
local function addBlock(
	model: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

-- ความสูงต่ำสุด/สูงสุดของพื้นดินใต้รอยเท้ากุฏิ (สุ่มตัวอย่างตาราง 5×5 รวมมุมทั้ง 4 + ตรงกลาง) · nil ถ้าเรย์ไม่โดนเลย
local function groundRangeUnderFootprint(x: number, z: number): (number?, number?)
	local lowest: number? = nil
	local highest: number? = nil
	for _, fx in { -0.5, -0.25, 0, 0.25, 0.5 } do
		for _, fz in { -0.5, -0.25, 0, 0.25, 0.5 } do
			local ground = MapSetup.groundOnTerrain(x + fx * KutiCfg.Width, z + fz * KutiCfg.Depth)
			if ground ~= nil then
				if lowest == nil or ground.Y < lowest then
					lowest = ground.Y
				end
				if highest == nil or ground.Y > highest then
					highest = ground.Y
				end
			end
		end
	end
	return lowest, highest
end

-- ตำแหน่ง Z (โลก) ของปลายล่างสุดของบันไดกุฏิ · nil ถ้ากุฏิไม่ได้สร้างด้วยโค้ด (เจ้าของทำเอง)
-- Monk ใช้วางพระให้ยืนพ้นบันไดเสมอ ไม่ว่าบันไดจะยาวเท่าไร (ขึ้นกับความสูงพื้นกุฏิ/ความลาดของเนิน)
local builtStairFootZ: number? = nil
function MapSetup.getKutiStairFootZ(): number?
	return builtStairFootZ
end

local function buildKuti(parent: Instance, kutiMarker: Vector3): Model
	local x, z = kutiMarker.X, kutiMarker.Z
	local sampledLowest, sampledHighest = groundRangeUnderFootprint(x, z)
	if sampledLowest == nil or sampledHighest == nil then
		warn(
			"[MapSetup] เรย์ไม่โดน Terrain ใต้กุฏิ — ใช้ความสูงของจุด Kuti แทน กุฏิอาจลอย/จม"
		)
	end
	local lowestY: number = sampledLowest or kutiMarker.Y
	local highestY: number = sampledHighest or kutiMarker.Y
	-- อิง "จุดสูงสุด" ของพื้นใต้รอยเท้า (เดิมอิงจุดต่ำสุด → ด้านเนินสูงฝังดิน) · แกน +Z = หน้าประตู (ใต้)
	-- พื้นกุฏิ = จุดสูงสุด + ใต้ถุน + ยกเพิ่ม (ExtraLift) จึงลอยพ้นดินทุกมุมแน่นอน
	local base = CFrame.new(x, highestY, z)
	local halfW, halfD = KutiCfg.Width / 2, KutiCfg.Depth / 2
	local wallT = KutiCfg.WallThickness

	local model = Instance.new("Model")
	model.Name = KutiCfg.Name
	-- ให้ client เห็นกุฏิตลอด (StreamingEnabled) ไม่งั้นเสาแสง/ป้ายหายตอนอยู่ไกล
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	-- ความสูงพื้นกุฏิ (สัมพัทธ์กับ highestY = จุดสูงสุดของพื้นดินใต้กุฏิ)
	local floorBottom = KutiCfg.StiltHeight + KutiCfg.ExtraLift
	local floorTop = floorBottom + KutiCfg.FloorThickness
	local wallTop = floorTop + KutiCfg.WallHeight
	local lowestRel = lowestY - highestY -- ≤ 0

	-- ใต้ถุน: เสา 2 แถว (หน้า/หลัง) ยาวลงถึงพื้นดินจริง ณ จุดของเสาแต่ละต้น แล้วฝังเพิ่ม (StiltBury) กันลอยเมื่อพื้นลาด
	local stiltSize = KutiCfg.StiltSize
	for row = -1, 1, 2 do
		for i = 1, KutiCfg.StiltCountX do
			local t = if KutiCfg.StiltCountX > 1 then (i - 1) / (KutiCfg.StiltCountX - 1) else 0.5
			local px = -halfW + stiltSize / 2 + t * (KutiCfg.Width - stiltSize)
			local pz = row * (halfD - stiltSize / 2)
			local stiltGround = MapSetup.groundOnTerrain(x + px, z + pz)
			local groundRel = if stiltGround ~= nil then stiltGround.Y - highestY else lowestRel
			local stiltBottom = groundRel - KutiCfg.StiltBury
			local stiltLength = floorBottom - stiltBottom
			addBlock(
				model,
				"Stilt",
				Vector3.new(stiltSize, stiltLength, stiltSize),
				base * CFrame.new(px, (floorBottom + stiltBottom) / 2, pz),
				KutiCfg.PostColor,
				Enum.Material.Wood
			)
		end
	end

	-- พื้น (ชิ้นหลัก ใช้เป็น PrimaryPart)
	local floor = addBlock(
		model,
		"Floor",
		Vector3.new(KutiCfg.Width, KutiCfg.FloorThickness, KutiCfg.Depth),
		base * CFrame.new(0, floorBottom + KutiCfg.FloorThickness / 2, 0),
		KutiCfg.FloorColor,
		Enum.Material.WoodPlanks
	)
	model.PrimaryPart = floor

	-- ผนัง: หลัง · ซ้าย/ขวา · หน้า (เว้นช่องประตูตรงกลาง + คานเหนือประตู)
	local wallCenterY = floorTop + KutiCfg.WallHeight / 2
	local innerWidth = KutiCfg.Width - 2 * wallT
	addBlock(
		model,
		"WallBack",
		Vector3.new(innerWidth, KutiCfg.WallHeight, wallT),
		base * CFrame.new(0, wallCenterY, -(halfD - wallT / 2)),
		KutiCfg.WallColor,
		Enum.Material.Wood
	)
	for _, side in { -1, 1 } do
		addBlock(
			model,
			"WallSide",
			Vector3.new(wallT, KutiCfg.WallHeight, KutiCfg.Depth),
			base * CFrame.new(side * (halfW - wallT / 2), wallCenterY, 0),
			KutiCfg.WallColor,
			Enum.Material.Wood
		)
	end
	local frontSegmentWidth = (innerWidth - KutiCfg.DoorWidth) / 2
	for _, side in { -1, 1 } do
		addBlock(
			model,
			"WallFront",
			Vector3.new(frontSegmentWidth, KutiCfg.WallHeight, wallT),
			base * CFrame.new(side * (KutiCfg.DoorWidth / 2 + frontSegmentWidth / 2), wallCenterY, halfD - wallT / 2),
			KutiCfg.WallColor,
			Enum.Material.Wood
		)
	end
	local lintelHeight = KutiCfg.WallHeight - KutiCfg.DoorHeight
	addBlock(
		model,
		"DoorLintel",
		Vector3.new(KutiCfg.DoorWidth, lintelHeight, wallT),
		base * CFrame.new(0, floorTop + KutiCfg.DoorHeight + lintelHeight / 2, halfD - wallT / 2),
		KutiCfg.WallColor,
		Enum.Material.Wood
	)

	-- บันไดหน้าประตู (ผู้เล่นเดินขึ้นไปถวายอาหาร/เข้ากุฏิ):
	-- จำนวนขั้นคิดจากความสูงพื้นกุฏิเหนือพื้นดินที่ปลายบันได ให้แต่ละขั้นสูงไม่เกิน StepMaxRise (เดินขึ้นได้ ไม่ต้องกระโดด)
	-- ขั้นบนสุดชิดพื้นกุฏิ ขั้นล่างสุดสูงจากดินหนึ่งขั้น · ขั้นเป็นแท่งยาวลงถึงพื้นดิน (พื้นลาดก็ไม่มีช่องว่างใต้ขั้น)
	local function footGroundRel(count: number): number
		local foot = MapSetup.groundOnTerrain(x, z + halfD + count * KutiCfg.StepDepth)
		return if foot ~= nil then foot.Y - highestY else lowestRel
	end
	local stepCount = KutiCfg.StepCount
	for _ = 1, 3 do -- ปลายบันไดขยับตามจำนวนขั้น (พื้นลาด) จึงวนคำนวณซ้ำให้นิ่ง
		local rise = math.max(floorTop - footGroundRel(stepCount), 0)
		local needed = math.clamp(math.ceil(rise / KutiCfg.StepMaxRise) - 1, KutiCfg.StepCount, KutiCfg.StepMaxCount)
		if needed == stepCount then
			break
		end
		stepCount = needed
	end
	local stepRise = math.max(floorTop - footGroundRel(stepCount), 1) / (stepCount + 1)
	builtStairFootZ = z + halfD + stepCount * KutiCfg.StepDepth
	for i = 1, stepCount do
		local stepTop = floorTop - i * stepRise
		local stepZ = halfD + (i - 0.5) * KutiCfg.StepDepth
		local ground = MapSetup.groundOnTerrain(x, z + stepZ)
		local groundRel = if ground ~= nil then ground.Y - highestY else lowestRel
		local stepBottom = math.min(groundRel, stepTop - 0.5) - 1
		addBlock(
			model,
			"Step",
			Vector3.new(KutiCfg.StepWidth, stepTop - stepBottom, KutiCfg.StepDepth),
			base * CFrame.new(0, (stepTop + stepBottom) / 2, stepZ),
			KutiCfg.StepColor,
			Enum.Material.WoodPlanks
		)
	end

	-- หลังคาจั่วสองด้าน ชัน สีกระเบื้องแดงเข้ม
	local rise = KutiCfg.RoofRise
	local run = halfD + KutiCfg.RoofOverhang
	local roofBaseY = wallTop - KutiCfg.RoofSink -- ขอบล่างของชายคา
	local slopeAngle = math.atan2(rise, run)
	local slopeLength = math.sqrt(run * run + rise * rise)
	local roofWidth = KutiCfg.Width + 2 * KutiCfg.RoofGableOverhang
	local slabCenterY = roofBaseY + rise / 2 + KutiCfg.RoofThickness / 2
	-- แผ่นหน้า (+Z) ปลายนอกต้องต่ำลง = หมุน +มุมรอบ X · แผ่นหลัง (-Z) หมุน -มุม
	for _, side in { 1, -1 } do
		addBlock(
			model,
			"Roof",
			Vector3.new(roofWidth, KutiCfg.RoofThickness, slopeLength),
			base * CFrame.new(0, slabCenterY, side * run / 2) * CFrame.Angles(side * slopeAngle, 0, 0),
			KutiCfg.RoofColor,
			Enum.Material.Slate
		)
	end

	-- หน้าจั่ว: อุดสามเหลี่ยมด้วยบล็อกซ้อนชั้นแคบลงเรื่อย ๆ (ซ้าย/ขวา)
	local gableHeight = (roofBaseY + rise) - wallTop
	local layerHeight = gableHeight / KutiCfg.GableLayers
	for layer = 0, KutiCfg.GableLayers - 1 do
		local layerBottom = wallTop + layer * layerHeight
		local layerTop = layerBottom + layerHeight
		-- ครึ่งความกว้าง (แกน Z) ที่ใต้หลังคาเหลืออยู่ ณ ขอบบนของชั้นนี้ · หักเผื่อเล็กน้อยไม่ให้โผล่พ้นหลังคา
		local halfSpan = math.min(halfD, run * (1 - (layerTop - roofBaseY) / rise) - 0.2)
		if halfSpan > 0.3 then
			for _, side in { -1, 1 } do
				addBlock(
					model,
					"Gable",
					Vector3.new(wallT, layerHeight, halfSpan * 2),
					base * CFrame.new(side * (halfW - wallT / 2), (layerBottom + layerTop) / 2, 0),
					KutiCfg.WallColor,
					Enum.Material.Wood
				)
			end
		end
	end

	-- สันหลังคา (ลูกบาศก์หมุน 45° เป็นสันแหลม)
	local ridgeY = roofBaseY + rise + KutiCfg.RoofThickness / 2
	local ridge = addBlock(
		model,
		"Ridge",
		Vector3.new(roofWidth + 0.4, KutiCfg.RidgeThickness, KutiCfg.RidgeThickness),
		base * CFrame.new(0, ridgeY, 0) * CFrame.Angles(math.pi / 4, 0, 0),
		KutiCfg.RoofColor,
		Enum.Material.Slate
	)

	-- ปลายสันหลังคางอนขึ้นสองข้าง (ช่อฟ้าแบบง่าย)
	local tilt = math.rad(KutiCfg.FinialTiltDegrees)
	for _, side in { -1, 1 } do
		local finial = addBlock(
			model,
			"Finial",
			KutiCfg.FinialSize,
			base
				* CFrame.new(side * (roofWidth / 2), ridgeY + KutiCfg.FinialSize.Y / 2 - 0.6, 0)
				* CFrame.Angles(0, 0, -side * tilt),
			KutiCfg.FinialColor,
			Enum.Material.Metal
		)
		finial.CanCollide = false
	end

	-- ป้ายชื่อ "กุฏิ" ลอยเหนือสันหลังคา
	local gui = Instance.new("BillboardGui")
	gui.Name = "KutiLabel"
	gui.Size = KutiCfg.LabelSize
	gui.StudsOffset = Vector3.new(0, KutiCfg.LabelAbove, 0)
	gui.AlwaysOnTop = KutiCfg.LabelAlwaysOnTop
	gui.MaxDistance = KutiCfg.LabelMaxDistance
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Text = KutiCfg.LabelText
	text.Parent = gui
	gui.Parent = ridge

	-- เสาแสงจาง ๆ เห็นกุฏิจากไกล: ไม่ชน ไม่ถูกกระสุน ไม่ทอดเงา
	if KutiCfg.BeamEnabled then
		local beam = Instance.new("Part")
		beam.Name = "KutiBeam"
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.CanTouch = false
		beam.CastShadow = false
		beam.Material = Enum.Material.Neon
		beam.Color = KutiCfg.BeamColor
		beam.Transparency = KutiCfg.BeamTransparency
		beam.Size = Vector3.new(KutiCfg.BeamWidth, KutiCfg.BeamHeight, KutiCfg.BeamWidth)
		beam.CFrame = base * CFrame.new(0, ridgeY + KutiCfg.BeamHeight / 2, 0)
		beam.Parent = model
	end

	model.Parent = parent
	return model
end

local function ensureKuti()
	local objects = MapSetup.getObjectsFolder()
	if objects:FindFirstChild(KutiCfg.Name) ~= nil then
		return -- เจ้าของทำเอง/มีอยู่แล้ว ใช้ของเดิม
	end
	local kutiMarker = MapSetup.getMarkerPosition("Kuti")
	if kutiMarker == nil then
		warn(
			"[MapSetup] ไม่พบจุด Kuti ใน MapMarkers — สร้างกุฏิไม่ได้"
		)
		return
	end
	buildKuti(objects, kutiMarker)
	warn(
		"[MapSetup] สร้างกุฏิอัตโนมัติที่ Workspace."
			.. MapCfg.ObjectsFolderName
			.. "."
			.. KutiCfg.Name
			.. " — ลบทิ้งแล้วใส่ของตัวเองชื่อเดียวกันได้"
	)
end

-- ===== กำแพงล่องหนรอบแมพ =====

-- 4 ด้านชิดขอบแมพ (ขอบด้านในอยู่ที่ ±HalfWidth / ±HalfDepth) หนา Thickness ยื่นออกนอกแมพ · สูงจาก BottomY ถึง BottomY + Height
-- Transparency 1 + CanCollide true (กันคนเดินออก) + CanQuery false (กระสุน/เรย์ทะลุ ไม่บังเรย์หาพื้นของระบบอื่น) + Anchored
local function ensureBoundary()
	local objects = MapSetup.getObjectsFolder()
	if objects:FindFirstChild(BoundaryCfg.FolderName) ~= nil then
		return -- เจ้าของทำเอง/มีอยู่แล้ว ใช้ของเดิม
	end
	local folder = Instance.new("Folder")
	folder.Name = BoundaryCfg.FolderName

	local halfW, halfD = MapCfg.HalfWidthStuds, MapCfg.HalfDepthStuds
	local t = BoundaryCfg.Thickness
	local centerY = BoundaryCfg.BottomY + BoundaryCfg.Height / 2
	-- เหนือ/ใต้ยาวเต็มความกว้างรวมความหนาของด้านข้าง (ไม่เหลือมุมโหว่) · ตะวันออก/ตะวันตกยาวเท่าความลึกแมพ
	local walls = {
		{
			name = "WallNorth",
			size = Vector3.new(2 * halfW + 2 * t, BoundaryCfg.Height, t),
			x = 0,
			z = -(halfD + t / 2),
		},
		{ name = "WallSouth", size = Vector3.new(2 * halfW + 2 * t, BoundaryCfg.Height, t), x = 0, z = halfD + t / 2 },
		{ name = "WallWest", size = Vector3.new(t, BoundaryCfg.Height, 2 * halfD), x = -(halfW + t / 2), z = 0 },
		{ name = "WallEast", size = Vector3.new(t, BoundaryCfg.Height, 2 * halfD), x = halfW + t / 2, z = 0 },
	}
	for _, wall in walls do
		local part = Instance.new("Part")
		part.Name = wall.name
		part.Anchored = true
		part.CanCollide = true
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = wall.size
		part.Position = Vector3.new(wall.x, centerY, wall.z)
		part.Parent = folder
	end
	folder.Parent = objects
end

-- เรียกครั้งเดียวตอนเริ่มเซิร์ฟเวอร์ ก่อนระบบอื่นทั้งหมด · แต่ละขั้นครอบ pcall: พังขั้นหนึ่งไม่ล้มเซิร์ฟเวอร์
function MapSetup.run()
	local okMarkers, errMarkers = pcall(ensureMarkers)
	if not okMarkers then
		warn("[MapSetup] สร้างจุดสำคัญไม่สำเร็จ:", errMarkers)
	end
	local okKuti, errKuti = pcall(ensureKuti)
	if not okKuti then
		warn("[MapSetup] สร้างกุฏิไม่สำเร็จ:", errKuti)
	end
	local okBoundary, errBoundary = pcall(ensureBoundary)
	if not okBoundary then
		warn("[MapSetup] สร้างกำแพงรอบแมพไม่สำเร็จ:", errBoundary)
	end
end

return MapSetup
