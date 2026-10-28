--!strict
-- Lobby (เซิร์ฟเวอร์): ห้องรอลอยฟ้า + หนังสติ๊กยักษ์
-- - ถ้าไม่มี Workspace.Lobby จะสร้างให้เองจาก Part ล้วน ๆ (ตัวเลขทั้งหมดอยู่ใน Config.Lobby)
-- - ถ้าเจ้าของทำ Workspace.Lobby เองแล้ว ใช้ของเจ้าของ: ต้องมี Part ชื่อ "LobbySpawn" และ "SlingshotPouch"
-- - ไม่ยุ่งกับกติกาภารกิจ (อยู่ใน Mission.luau) — ไฟล์นี้ตอบแค่ "จุดเกิดอยู่ไหน / ถุงหนังสติ๊กอยู่ไหน / หลุดออกนอกห้องไหม"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local LC = Config.Lobby

type Bounds = {
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	minY: number,
}

local Lobby = {}

local lobbyRoot: Instance? = nil
local spawnPart: BasePart? = nil
local pouchPart: BasePart? = nil
local bounds: Bounds? = nil
local rng = Random.new()

-- ===== ตัวช่วยสร้าง Part =====

local function makePart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- แท่งเชื่อมจุด a ไป b (ใช้ทำแถบยางหนังสติ๊ก)
local function makeBeam(name: string, a: Vector3, b: Vector3, thickness: number, color: Color3, parent: Instance)
	local length = (b - a).Magnitude
	local beam = makePart(
		name,
		Vector3.new(thickness, thickness, length),
		CFrame.lookAt((a + b) / 2, b),
		color,
		Enum.Material.Fabric,
		parent
	)
	beam.CanCollide = false
end

-- ===== สร้างห้องรอมาตรฐาน =====

local function buildSlingshot(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Slingshot"
	model.Parent = parent

	local baseSize = LC.SlingshotBaseSize
	local baseCenter = LC.Center + LC.SlingshotOffset
	local baseTopY = baseCenter.Y + baseSize.Y / 2
	makePart("Base", baseSize, CFrame.new(baseCenter), LC.SlingshotBaseColor, Enum.Material.WoodPlanks, model)

	-- ถุงที่ผู้เล่นยืนก่อนถูกยิง อยู่ถอยไปทางเหนือของเสา (ดึงยางไปข้างหลัง) ยิงไปทางใต้ (+Z)
	local pouchCenter = Vector3.new(baseCenter.X, baseTopY, baseCenter.Z) + LC.SlingshotPouchOffset
	local pouch = makePart(
		"SlingshotPouch",
		LC.SlingshotPouchSize,
		CFrame.new(pouchCenter),
		LC.SlingshotPouchColor,
		Enum.Material.Fabric,
		model
	)
	pouch.CanCollide = false -- ผู้เล่นถูกตรึงอยู่บนถุงตอนยิง ไม่ต้องชน

	for _, side in { -1, 1 } do
		local postCenter = Vector3.new(
			baseCenter.X + side * LC.SlingshotPostSpacing / 2,
			baseTopY + LC.SlingshotPostSize.Y / 2,
			baseCenter.Z + LC.SlingshotPostZ
		)
		makePart(
			"Post" .. (if side < 0 then "L" else "R"),
			LC.SlingshotPostSize,
			CFrame.new(postCenter),
			LC.SlingshotPostColor,
			Enum.Material.Wood,
			model
		)
		-- แถบยางจากยอดเสาไปขอบถุงด้านเดียวกัน
		local postTop = postCenter + Vector3.new(0, LC.SlingshotPostSize.Y / 2, 0)
		local pouchEdge = pouchCenter + Vector3.new(side * LC.SlingshotPouchSize.X / 2, LC.SlingshotPouchSize.Y / 2, 0)
		makeBeam(
			"Band" .. (if side < 0 then "L" else "R"),
			postTop,
			pouchEdge,
			LC.SlingshotBandThickness,
			LC.SlingshotBandColor,
			model
		)
	end
end

local function buildDefaultLobby(): Model
	local model = Instance.new("Model")
	model.Name = "Lobby"
	model:SetAttribute("BuiltByCode", true)

	local center = LC.Center
	local floorSize = LC.FloorSize
	local floorTopY = center.Y + floorSize.Y / 2
	makePart("Floor", floorSize, CFrame.new(center), LC.FloorColor, Enum.Material.Concrete, model)

	-- รั้วรอบแท่น 4 ด้าน (สูงกว่าความสูงกระโดด)
	local halfX, halfZ = floorSize.X / 2, floorSize.Z / 2
	local t = LC.RailThickness
	local railY = floorTopY + LC.RailHeight / 2
	local function addRail(name: string, size: Vector3, position: Vector3)
		local part = makePart(name, size, CFrame.new(position), LC.RailColor, Enum.Material.Glass, model)
		part.Transparency = LC.RailTransparency
	end
	local longRail = Vector3.new(floorSize.X, LC.RailHeight, t)
	local sideRail = Vector3.new(t, LC.RailHeight, floorSize.Z - 2 * t)
	addRail("RailNorth", longRail, Vector3.new(center.X, railY, center.Z - halfZ + t / 2))
	addRail("RailSouth", longRail, Vector3.new(center.X, railY, center.Z + halfZ - t / 2))
	addRail("RailWest", sideRail, Vector3.new(center.X - halfX + t / 2, railY, center.Z))
	addRail("RailEast", sideRail, Vector3.new(center.X + halfX - t / 2, railY, center.Z))

	-- จุดเกิดของผู้เล่น (Neutral = ทุกคนเกิดได้ · Duration 0 = ไม่มีโล่กันตายตอนเกิด)
	local pad = Instance.new("SpawnLocation")
	pad.Name = "LobbySpawn"
	pad.Size = LC.SpawnPadSize
	pad.Anchored = true
	pad.Neutral = true
	pad.Duration = 0
	pad.CanCollide = true
	pad.Color = LC.SpawnPadColor
	pad.Material = Enum.Material.SmoothPlastic
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.BottomSurface = Enum.SurfaceType.Smooth
	pad.Position =
		Vector3.new(center.X + LC.SpawnPadOffset.X, floorTopY + LC.SpawnPadSize.Y / 2, center.Z + LC.SpawnPadOffset.Z)
	pad.Parent = model

	buildSlingshot(model)
	return model
end

-- ===== ขอบเขตห้อง (ไว้ตรวจว่าผู้เล่นหลุดออกนอกห้อง) =====

-- กล่องครอบ Part ทั้งหมดในห้อง (คิดการหมุนแบบหยาบ ๆ พอสำหรับตรวจตกแท่น)
local function computeBounds(root: Instance): Bounds
	local minX, maxX, minZ, maxZ, minY = math.huge, -math.huge, math.huge, -math.huge, math.huge
	local found = false
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			found = true
			local cf, half = descendant.CFrame, descendant.Size / 2
			local right, up, look = cf.RightVector, cf.UpVector, cf.LookVector
			local extentX = math.abs(right.X) * half.X + math.abs(up.X) * half.Y + math.abs(look.X) * half.Z
			local extentY = math.abs(right.Y) * half.X + math.abs(up.Y) * half.Y + math.abs(look.Y) * half.Z
			local extentZ = math.abs(right.Z) * half.X + math.abs(up.Z) * half.Y + math.abs(look.Z) * half.Z
			minX = math.min(minX, cf.Position.X - extentX)
			maxX = math.max(maxX, cf.Position.X + extentX)
			minZ = math.min(minZ, cf.Position.Z - extentZ)
			maxZ = math.max(maxZ, cf.Position.Z + extentZ)
			minY = math.min(minY, cf.Position.Y - extentY)
		end
	end
	if not found then
		-- ห้องของเจ้าของที่ไม่มี Part เลย: ใช้ขนาดมาตรฐานรอบ Config.Lobby.Center
		local c, s = LC.Center, LC.FloorSize
		return {
			minX = c.X - s.X / 2,
			maxX = c.X + s.X / 2,
			minZ = c.Z - s.Z / 2,
			maxZ = c.Z + s.Z / 2,
			minY = c.Y - s.Y / 2,
		}
	end
	return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ, minY = minY }
end

local function findPart(root: Instance, name: string): BasePart?
	local found = root:FindFirstChild(name, true)
	if found ~= nil and found:IsA("BasePart") then
		return found
	end
	return nil
end

-- ===== API =====

-- สร้าง/ค้นหาห้องรอ (เรียกครั้งเดียวตอนเริ่มเซิร์ฟเวอร์ ก่อนผู้เล่นเกิด)
function Lobby.build()
	local root: Instance
	local existing = Workspace:FindFirstChild("Lobby")
	if existing ~= nil then
		root = existing
	else
		local model = buildDefaultLobby()
		model.Parent = Workspace
		root = model
	end
	lobbyRoot = root
	spawnPart = findPart(root, "LobbySpawn")
	pouchPart = findPart(root, "SlingshotPouch")
	bounds = computeBounds(root)
	if spawnPart == nil then
		warn(
			"[Lobby] ไม่พบ Part ชื่อ LobbySpawn ใน Workspace.Lobby — ใช้จุดกึ่งกลาง Config.Lobby.Center แทน"
		)
	end
	if pouchPart == nil then
		warn(
			"[Lobby] ไม่พบ Part ชื่อ SlingshotPouch ใน Workspace.Lobby — ใช้จุดหน้าหนังสติ๊กมาตรฐานแทน"
		)
	end
end

function Lobby.getInstance(): Instance?
	return lobbyRoot
end

-- SpawnLocation ของห้องรอ (ไว้ตั้ง Player.RespawnLocation) — nil ถ้าห้องของเจ้าของใช้ Part ธรรมดา
function Lobby.getSpawnLocation(): SpawnLocation?
	local part = spawnPart
	if part ~= nil and part:IsA("SpawnLocation") then
		return part
	end
	return nil
end

-- จุดยืนสุ่มบนแผ่นเกิด (ตำแหน่งของ HumanoidRootPart)
function Lobby.randomSpawnPosition(): Vector3
	local part = spawnPart
	if part == nil then
		return LC.Center + Vector3.new(0, LC.FloorSize.Y / 2 + LC.StandHeight, 0)
	end
	local halfX = math.max(part.Size.X / 2 - LC.SpawnPadEdgeMargin, 0)
	local halfZ = math.max(part.Size.Z / 2 - LC.SpawnPadEdgeMargin, 0)
	local local3 =
		Vector3.new(rng:NextNumber(-1, 1) * halfX, part.Size.Y / 2 + LC.StandHeight, rng:NextNumber(-1, 1) * halfZ)
	return part.CFrame:PointToWorldSpace(local3)
end

-- จุดยืนกลางถุงหนังสติ๊ก (ตำแหน่งของ HumanoidRootPart) · แกน X ของ CFrame นี้ = แนวที่ผู้เล่นยืนเรียงกัน
function Lobby.getPouchStandCFrame(): CFrame
	local part = pouchPart
	if part == nil then
		local base = LC.Center + LC.SlingshotOffset
		local top = base.Y + LC.SlingshotBaseSize.Y / 2
		return CFrame.new(base.X, top, base.Z) * CFrame.new(LC.SlingshotPouchOffset + Vector3.new(0, LC.StandHeight, 0))
	end
	return part.CFrame * CFrame.new(0, part.Size.Y / 2 + LC.StandHeight, 0)
end

-- ตำแหน่งนี้หลุดออกนอกห้องรอ (หรือตกต่ำกว่าฐาน) ไหม
function Lobby.isOutside(position: Vector3): boolean
	local b = bounds
	if b == nil then
		return false
	end
	local margin = LC.OutsideMarginStuds
	return position.X < b.minX - margin
		or position.X > b.maxX + margin
		or position.Z < b.minZ - margin
		or position.Z > b.maxZ + margin
		or position.Y < b.minY - LC.FallResetBelowStuds
end

return Lobby
