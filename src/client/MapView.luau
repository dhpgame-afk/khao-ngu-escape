--!strict
-- MapView: แผนที่มองจากด้านบนของแมพทั้งหมด (ใช้ร่วมกันระหว่างหน้าห้องรอ LobbyUi กับหน้าเล็งหนังสติ๊ก RescueUi)
-- - วาดแค่กรอบ + จุดสำคัญ (กุฏิ/รังลิง/ฐานบั้งไฟ) + ตัวช่วยแปลงพิกัดโลก ↔ ตำแหน่งบนแผนที่ · ไม่รับอินพุตเอง
-- - เหนือ = ด้านบนของแผนที่ (−Z) · ตะวันออก = ขวา (+X) เหมือน Config.Map
-- - ใช้ Scale ทั้งหมด + UIAspectRatioConstraint ตามสัดส่วนแมพจริง

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local FONT = Enum.Font.GothamBold
local WHITE = Color3.fromRGB(255, 255, 255)

local MapView = {}

-- สีจุดบนแผนที่
MapView.COLOR_KUTI = Color3.fromRGB(255, 213, 74)
MapView.COLOR_NEST = Color3.fromRGB(230, 70, 60)
MapView.COLOR_ROCKET = Color3.fromRGB(80, 170, 255)
MapView.COLOR_LANDING = Color3.fromRGB(90, 230, 120)

export type View = {
	frame: Frame,
	worldToMap: (x: number, z: number) -> UDim2,
	mapToWorld: (u: number, v: number) -> (number, number), -- u, v = 0–1 บนแผนที่ → พิกัดโลก (x, z)
	makeDot: (name: string, color: Color3, sizeScale: number, zIndex: number) -> Frame,
	setMarkers: (markers: any) -> (), -- markers จาก MissionState: { {name, x, z} }
}

function MapView.colorHex(color: Color3): string
	-- %x ต้องการจำนวนเต็ม จึงปัดค่าสี 0–1 เป็น 0–255 ก่อน
	return string.format(
		"#%02x%02x%02x",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

function MapView.markerColor(name: string): Color3
	if name == "Kuti" then
		return MapView.COLOR_KUTI
	elseif name == "RocketPad" then
		return MapView.COLOR_ROCKET
	end
	return MapView.COLOR_NEST
end

local function addCorner(inst: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = inst
end

function MapView.create(parent: Instance, position: UDim2, size: UDim2, anchor: Vector2?): View
	local mapWidth = 2 * Config.Map.HalfWidthStuds
	local mapDepth = 2 * Config.Map.HalfDepthStuds

	local frame = Instance.new("Frame")
	frame.Name = "Map"
	frame.AnchorPoint = anchor or Vector2.zero
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = Color3.fromRGB(40, 70, 48)
	frame.BorderSizePixel = 0
	frame.Parent = parent
	addCorner(frame, 0.03)
	local stroke = Instance.new("UIStroke")
	stroke.Color = WHITE
	stroke.Transparency = 0.5
	stroke.Thickness = 2
	stroke.Parent = frame
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = mapWidth / mapDepth -- แมพกว้างกว่าสูง ≈ 970 × 640
	ratio.Parent = frame

	local northLabel = Instance.new("TextLabel")
	northLabel.Name = "North"
	northLabel.BackgroundTransparency = 1
	northLabel.Position = UDim2.fromScale(0.4, 0)
	northLabel.Size = UDim2.fromScale(0.2, 0.08)
	northLabel.Font = FONT
	northLabel.Text = "เหนือ"
	northLabel.TextColor3 = WHITE
	northLabel.TextStrokeTransparency = 0.6
	northLabel.TextTransparency = 0.3
	northLabel.TextScaled = true
	northLabel.ZIndex = 5
	northLabel.Parent = frame
	local northLimit = Instance.new("UITextSizeConstraint")
	northLimit.MaxTextSize = 16
	northLimit.MinTextSize = 8
	northLimit.Parent = northLabel

	local function worldToMap(x: number, z: number): UDim2
		return UDim2.fromScale(
			math.clamp((x + Config.Map.HalfWidthStuds) / mapWidth, 0, 1),
			math.clamp((z + Config.Map.HalfDepthStuds) / mapDepth, 0, 1)
		)
	end

	local function mapToWorld(u: number, v: number): (number, number)
		return -Config.Map.HalfWidthStuds + u * mapWidth, -Config.Map.HalfDepthStuds + v * mapDepth
	end

	local function makeDot(name: string, color: Color3, sizeScale: number, zIndex: number): Frame
		local dot = Instance.new("Frame")
		dot.Name = name
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Size = UDim2.fromScale(sizeScale, sizeScale)
		dot.BackgroundColor3 = color
		dot.BorderSizePixel = 0
		dot.ZIndex = zIndex
		dot.Parent = frame
		addCorner(dot, 0.5)
		local dotRatio = Instance.new("UIAspectRatioConstraint")
		dotRatio.AspectRatio = 1
		dotRatio.Parent = dot
		return dot
	end

	-- สร้างจุดสำคัญใหม่เมื่อรายการเปลี่ยนเท่านั้น (เทียบจากกุญแจข้อความ)
	local markerDots: { [string]: Frame } = {}
	local lastMarkerKey = ""
	local function setMarkers(markers: any)
		if type(markers) ~= "table" then
			return
		end
		local key = ""
		for _, m in markers do
			if type(m) == "table" and type(m.name) == "string" and type(m.x) == "number" and type(m.z) == "number" then
				key ..= m.name .. ":" .. math.floor(m.x) .. ":" .. math.floor(m.z) .. ";"
			end
		end
		if key == lastMarkerKey then
			return
		end
		lastMarkerKey = key
		for _, dot in markerDots do
			dot:Destroy()
		end
		markerDots = {}
		for _, m in markers do
			if type(m) == "table" and type(m.name) == "string" and type(m.x) == "number" and type(m.z) == "number" then
				local dot = makeDot(m.name, MapView.markerColor(m.name), 0.045, 3)
				dot.Position = worldToMap(m.x, m.z)
				markerDots[m.name] = dot
			end
		end
	end

	return {
		frame = frame,
		worldToMap = worldToMap,
		mapToWorld = mapToWorld,
		makeDot = makeDot,
		setMarkers = setMarkers,
	}
end

return MapView
