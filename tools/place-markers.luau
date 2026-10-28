-- วางจุดสำคัญบนแมพ (ใช้ครั้งเดียวใน Studio — ไม่ใช่โค้ดในเกม)
-- วิธีใช้: คัดลอกทั้งไฟล์ → วางในช่อง Command Bar ใต้ Output ("Execute a command") → กด Enter
-- ได้โฟลเดอร์ Workspace.MapMarkers มีแท่งสีบอกตำแหน่ง ย้ายด้วยเครื่องมือ Move ได้ตามใจ
-- รันซ้ำได้: จุดที่มีอยู่แล้วจะไม่สร้างทับ (ลบจุดไหนทิ้งแล้วรันใหม่ = วางจุดนั้นใหม่ที่ค่าเริ่มต้น)
-- พิกัดอิงผังใน mockups/wireframe.html · กุฏิอยู่กลางแมพ (0,0) · ทิศเหนือ = Z ติดลบ

-- หมายเหตุ: เซิร์ฟเวอร์ (src/server/MapSetup.luau) สร้างจุดที่ยังไม่มีให้อัตโนมัติทุกครั้งที่เริ่มเกมอยู่แล้ว (แบบมองไม่เห็น)
-- สคริปต์นี้จึงใช้เฉพาะตอนอยากวางจุดแบบ "มองเห็นในโหมดแก้ไข" (แท่งสี+ป้าย) เพื่อลากย้ายใน Studio
-- ตำแหน่งเริ่มต้นอ่านจาก Config.Map.Markers (ต้องซิงก์ Rojo อยู่ ไม่งั้น require ไม่เจอ) — แก้ตัวเลขที่ Config ที่เดียว

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local MARKERS = {}
for _, name in Config.Map.MarkerNames do
	local def = (Config.Map.Markers :: any)[name]
	table.insert(MARKERS, { name = name, label = def.label, x = def.x, z = def.z, color = def.color, size = def.size })
end

local folder = workspace:FindFirstChild(Config.Map.MarkersFolderName)
if not folder then
	folder = Instance.new("Folder")
	folder.Name = Config.Map.MarkersFolderName
	folder.Parent = workspace
end

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { workspace.Terrain }

for _, m in MARKERS do
	if folder:FindFirstChild(m.name) then
		print("มีอยู่แล้ว ข้าม:", m.name)
		continue
	end
	local hit = workspace:Raycast(Vector3.new(m.x, 600, m.z), Vector3.new(0, -800, 0), params)
	local groundY = if hit then hit.Position.Y else 150

	local part = Instance.new("Part")
	part.Name = m.name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 0.4
	part.Material = Enum.Material.Neon
	part.Color = m.color
	part.Size = m.size
	part.Position = Vector3.new(m.x, groundY + m.size.Y / 2, m.z)

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 40)
	gui.StudsOffset = Vector3.new(0, 8, 0)
	gui.AlwaysOnTop = true
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0
	text.Text = m.label
	text.Parent = gui
	gui.Parent = part

	part.Parent = folder
	print("วางแล้ว:", m.name, "สูง", math.floor(groundY))
end

-- ยกแท่นเกิดขึ้นมาวางบนพื้นข้างกุฏิ (กันจมในภูเขา)
local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
if spawn then
	local hit = workspace:Raycast(Vector3.new(0, 600, 40), Vector3.new(0, -800, 0), params)
	if hit then
		spawn.Position = hit.Position + Vector3.new(0, spawn.Size.Y / 2 + 1, 0)
		print("ย้ายแท่นเกิดไปข้างกุฏิแล้ว")
	end
end
