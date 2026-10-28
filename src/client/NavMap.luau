--!strict
-- NavMap: แผนที่นำทางสไตล์ม้วนกระดาษขุมทรัพย์ — โชว์เฉพาะตอน "กดปุ่ม แผนที่ ค้างไว้" (หรือกด M ค้างบนคอม) ปล่อยแล้วซ่อน
-- - ฝั่ง client ล้วน ไม่มี remote: อ่านจาก MissionState (ผ่าน onSnapshot) · ตำแหน่งเพื่อนจาก RescueUi.getMates() · ของจาก Workspace.MissionObjects
-- - วาดจาก GUI ล้วน (Frame + UICorner + UIGradient) ไม่ใช้ภาพจาก asset · ทุกตัวเลขอยู่ใน Config.NavMap
-- - ตัวแผ่นไม่รับอินพุต (Active = false) ผู้เล่นเลยกดปุ่มค้างด้วยนิ้วหนึ่ง แล้วใช้จอยเดินด้วยอีกนิ้วได้
-- - ปิดอยู่ = ไม่ทำงานอะไรเลย (ไม่เชื่อม RenderStepped) · เปิดอยู่ = อัปเดตตำแหน่งตาม Config.NavMap.UpdateHz ส่วนทิศลูกศรหมุนทุกเฟรม (ถูกมาก)
-- - ตำแหน่งบนแผนที่คิดเป็นสัดส่วน 0–1 ของแผนที่จริง · เหนือ = ขึ้นบน (−Z) เหมือน MapView

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Hud = require(script.Parent.Hud)
local MapView = require(script.Parent.MapView)
local RescueUi = require(script.Parent.RescueUi)

local NM = Config.NavMap

-- กว้าง ÷ สูง ของแผนที่จริง (ใช้คำนวณทิศ/ความยาวเส้นให้ไม่เบี้ยว เพราะพิกัดบนแผนที่เป็นสัดส่วนคนละแกน)
local MAP_ASPECT = Config.Map.HalfWidthStuds / Config.Map.HalfDepthStuds

local ITEM_COLORS: { [string]: Color3 } = NM.ItemColors

export type Api = {
	onSnapshot: (snapshot: { [string]: any }) -> (), -- MissionState: phase / inLobby / offered / markers
}

local NavMap = {}

-- ===== ตัวช่วยสร้าง GUI =====

local function addCorner(inst: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = inst
end

local function addStroke(inst: GuiObject, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = inst
end

-- Frame จัดกึ่งกลางที่จุด position (สัดส่วนของพ่อ)
local function newFrame(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	color: Color3,
	zIndex: number
): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	frame.Parent = parent
	return frame
end

-- กล่องโปร่งใสสี่เหลี่ยมจัตุรัส (aspect 1:1) ขนาดเทียบความสูงแผนที่ ไว้ใส่รูปทรงข้างใน
local function newIcon(parent: Instance, name: string, sizeScale: number, zIndex: number): Frame
	local icon =
		newFrame(parent, name, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(sizeScale, sizeScale), NM.InkColor, zIndex)
	icon.BackgroundTransparency = 1
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = icon
	return icon
end

local function styleInkLabel(label: TextLabel)
	label.TextColor3 = NM.InkColor
	label.TextStrokeColor3 = NM.InkStrokeColor
	label.TextStrokeTransparency = 0.5
end

-- ป้ายชื่อใต้ไอคอนบนแผนที่ (กุฏิ / รังลิง / บั้งไฟ)
local function addMarkerLabel(icon: Frame, text: string)
	local label = Hud.makeLabel(icon, "Label", text, UDim2.fromScale(0.5, 1.05), UDim2.fromScale(3.6, 0.95))
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.ZIndex = icon.ZIndex
	styleInkLabel(label)
	local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
	if limit ~= nil then
		limit.MaxTextSize = 16
		limit.MinTextSize = 9
	end
end

-- ===== ส่วนประกอบของแผ่นกระดาษ =====

local function buildRoll(parent: Instance, name: string, centerX: number)
	local roll = newFrame(
		parent,
		name,
		UDim2.fromScale(centerX, 0.5),
		UDim2.fromScale(NM.RollWidth, 1),
		Color3.fromRGB(255, 255, 255),
		3
	)
	addCorner(roll, 0.5) -- ปลายมน (รัศมีเต็มของด้านที่สั้นกว่า = แท่งกลม)
	addStroke(roll, NM.EdgeColor, 2)
	local gradient = Instance.new("UIGradient")
	-- แสงตกกลางแกนม้วน ให้ดูเป็นแท่งกลม
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, NM.RollColor),
		ColorSequenceKeypoint.new(0.5, NM.RollLightColor),
		ColorSequenceKeypoint.new(1, NM.RollColor),
	})
	gradient.Rotation = 0
	gradient.Parent = roll
end

local function buildCompass(parent: Instance)
	local compass = newFrame(
		parent,
		"Compass",
		UDim2.fromScale(NM.CompassCenter.X, NM.CompassCenter.Y),
		-- กว้าง/สูงเทียบแผ่น: คูณ ScrollAspect ให้เป็นวงกลมพอดี
		UDim2.fromScale(NM.CompassSize, NM.CompassSize * NM.ScrollAspect),
		NM.InkStrokeColor,
		4
	)
	addCorner(compass, 0.5)
	addStroke(compass, NM.InkColor, 2)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = compass
	newFrame(compass, "LineV", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.07, 0.8), NM.InkColor, 5)
	newFrame(compass, "LineH", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.8, 0.07), NM.InkColor, 5)
	local needle =
		newFrame(compass, "Needle", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.34, 0.34), NM.TargetColor, 6)
	needle.Rotation = 45
	addStroke(needle, NM.InkColor, 1)
	-- ตัว N ชี้ทิศเหนือ = ขึ้นบนของแผนที่ เสมอ
	local north = Hud.makeLabel(compass, "North", "N", UDim2.fromScale(0.5, -0.24), UDim2.fromScale(0.8, 0.45))
	north.AnchorPoint = Vector2.new(0.5, 0.5)
	north.ZIndex = 6
	styleInkLabel(north)
	north.TextColor3 = NM.TargetColor
end

-- แต่งแมพให้ดูเป็นแผนที่ขุมทรัพย์: ต้นไม้เป็นกลุ่ม + แม่น้ำคดเคี้ยว (วาดครั้งเดียว ไม่เกี่ยวกับภูมิประเทศจริง)
local function buildDecorations(view: MapView.View)
	local land = view.frame
	-- แม่น้ำ: ต่อชิ้นส่วนสั้น ๆ ตามเส้นคลื่น sin · คิดเป็นหน่วย "ความสูงแผนที่ = 1" เพื่อให้มุมไม่เบี้ยว
	local segments = NM.RiverSegments
	local function riverPoint(i: number): Vector2
		local v = i / segments
		local u = NM.RiverStartU
			+ (NM.RiverEndU - NM.RiverStartU) * v
			+ NM.RiverAmplitude * math.sin(v * NM.RiverWaves * 2 * math.pi)
		return Vector2.new(u, v)
	end
	for i = 0, segments - 1 do
		local a, b = riverPoint(i), riverPoint(i + 1)
		local dx, dy = (b.X - a.X) * MAP_ASPECT, b.Y - a.Y
		local length = math.sqrt(dx * dx + dy * dy)
		local piece = newFrame(
			land,
			"River" .. i,
			UDim2.fromScale((a.X + b.X) / 2, (a.Y + b.Y) / 2),
			UDim2.fromScale(length * 1.15 / MAP_ASPECT, NM.RiverThickness), -- ยืดนิดให้ต่อกันสนิท
			NM.RiverColor,
			1
		)
		piece.Rotation = math.deg(math.atan2(dy, dx))
		addCorner(piece, 0.5)
	end
	for clusterIndex, center in NM.TreeClusters do
		for treeIndex, offset in NM.TreeOffsets do
			local tree = view.makeDot("Tree" .. clusterIndex .. "_" .. treeIndex, NM.TreeColor, NM.TreeSize, 1)
			tree.Position = UDim2.fromScale(center.X + offset.X / MAP_ASPECT, center.Y + offset.Y)
			addStroke(tree, NM.TreeDarkColor, 1)
		end
	end
end

-- ไอคอนจุดสำคัญ: กุฏิ = หลังคาแดง + ตัวเรือนเหลือง · บั้งไฟ = ตัวบั้งไฟมีหัวแดง · รังลิง = วงกลมน้ำตาล
local function buildMarkerIcon(land: Instance, name: string): Frame
	local icon = newIcon(land, name, NM.MarkerSize, 6)
	if name == "Kuti" then
		local body = newFrame(icon, "Body", UDim2.fromScale(0.5, 0.72), UDim2.fromScale(0.8, 0.5), NM.KutiBodyColor, 1)
		addStroke(body, NM.InkColor, 1)
		local roof = newFrame(icon, "Roof", UDim2.fromScale(0.5, 0.3), UDim2.fromScale(1.1, 0.34), NM.KutiRoofColor, 2)
		addCorner(roof, 0.3)
		addStroke(roof, NM.InkColor, 1)
		addMarkerLabel(icon, "กุฏิ")
	elseif name == "RocketPad" then
		local body = newFrame(icon, "Body", UDim2.fromScale(0.5, 0.55), UDim2.fromScale(0.42, 0.95), NM.RocketColor, 1)
		addCorner(body, 0.5)
		addStroke(body, NM.InkColor, 1)
		local nose =
			newFrame(icon, "Nose", UDim2.fromScale(0.5, 0.2), UDim2.fromScale(0.26, 0.26), NM.RocketNoseColor, 2)
		addCorner(nose, 0.5)
		addMarkerLabel(icon, "บั้งไฟ")
	else
		local circle = newFrame(icon, "Circle", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1), NM.NestColor, 1)
		addCorner(circle, 0.5)
		addStroke(circle, NM.InkColor, 1.5)
		addMarkerLabel(icon, "รังลิง")
	end
	return icon
end

-- ไอคอนของ (ตะกร้า = สี่เหลี่ยม · ถุงเงิน = วงกลม · ขนม = สี่เหลี่ยมเอียง)
local function buildItemIcon(land: Instance, kind: string, color: Color3): Frame
	local icon = newIcon(land, "Item_" .. kind, NM.ItemSize, 7)
	icon.BackgroundTransparency = 0
	icon.BackgroundColor3 = color
	addStroke(icon, NM.InkColor, 1)
	if kind == "MoneyBag" then
		addCorner(icon, 0.5)
	elseif kind == "SnackPack" then
		icon.Rotation = 45
	else
		addCorner(icon, 0.2)
	end
	return icon
end

-- ลูกศรผู้เล่น: วงกลม + หัวลูกศรชี้ขึ้น (หมุนทั้งกล่องตามทิศกล้อง)
local function buildPlayerIcon(land: Instance): Frame
	local icon = newIcon(land, "Player", NM.PlayerSize, 10)
	local tip = newFrame(icon, "Tip", UDim2.fromScale(0.5, 0.22), UDim2.fromScale(0.5, 0.5), NM.PlayerColor, 1)
	tip.Rotation = 45
	addStroke(tip, NM.PlayerOutline, 1.5)
	local body = newFrame(icon, "Body", UDim2.fromScale(0.5, 0.58), UDim2.fromScale(0.62, 0.62), NM.PlayerColor, 2)
	addCorner(body, 0.5)
	addStroke(body, NM.PlayerOutline, 1.5)
	return icon
end

-- กากบาทแดง = เป้าหมายปัจจุบัน
local function buildTargetIcon(land: Instance): Frame
	local icon = newIcon(land, "TargetX", NM.TargetSize, 8)
	for index, angle in { 45, -45 } do
		local bar = newFrame(
			icon,
			"Bar" .. index,
			UDim2.fromScale(0.5, 0.5),
			UDim2.fromScale(1.25, NM.TargetBarThickness),
			NM.TargetColor,
			1
		)
		bar.Rotation = angle
		addCorner(bar, 0.3)
		addStroke(bar, NM.InkColor, 1)
	end
	icon.Visible = false
	return icon
end

local function pivotPositionOf(inst: Instance): Vector3?
	if inst:IsA("Model") then
		return inst:GetPivot().Position
	elseif inst:IsA("BasePart") then
		return inst.Position
	end
	return nil
end

-- ===== เริ่มระบบ =====

function NavMap.start(rescue: RescueUi.Api): Api
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "NavMap"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- เลี่ยงรอยบาก/ขอบจอ
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = NM.DisplayOrder
	gui.Parent = playerGui

	-- ===== ปุ่มกดค้าง =====
	local button = Hud.makeButton(gui, "NavMapButton", NM.ButtonText, NM.ButtonCenter, NM.ButtonSize, true)
	button.BackgroundColor3 = NM.ButtonColor
	button.Visible = false

	-- ===== แผ่นกระดาษ (ไม่ Active · ไม่บังจอยเดิน) =====
	local scroll = Instance.new("Frame")
	scroll.Name = "Scroll"
	scroll.AnchorPoint = Vector2.new(0.5, 0.5)
	scroll.Position = UDim2.fromScale(0.5, NM.CenterY)
	scroll.Size = UDim2.fromScale(NM.WidthFraction, NM.HeightFraction)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Active = false
	scroll.Visible = false
	scroll.Parent = gui
	local scrollRatio = Instance.new("UIAspectRatioConstraint")
	scrollRatio.AspectRatio = NM.ScrollAspect
	scrollRatio.Parent = scroll

	local paper = newFrame(
		scroll,
		"Paper",
		UDim2.fromScale(0.5, 0.5),
		UDim2.fromScale(1 - 2 * NM.PaperInsetX, 1 - 2 * NM.PaperInsetY),
		Color3.fromRGB(255, 255, 255),
		1
	)
	paper.BackgroundTransparency = NM.PaperTransparency
	addCorner(paper, 0.03)
	addStroke(paper, NM.EdgeColor, 2)
	local paperGradient = Instance.new("UIGradient")
	paperGradient.Color = ColorSequence.new(NM.PaperColorTop, NM.PaperColorBottom)
	paperGradient.Rotation = 90
	paperGradient.Parent = paper

	buildRoll(scroll, "RollLeft", NM.RollWidth / 2)
	buildRoll(scroll, "RollRight", 1 - NM.RollWidth / 2)

	local title =
		Hud.makeLabel(scroll, "Title", NM.TitleText, UDim2.fromScale(0.5, NM.TitleCenterY), UDim2.fromScale(0.5, 0.08))
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.ZIndex = 4
	styleInkLabel(title)

	local distanceLabel =
		Hud.makeLabel(scroll, "Distance", "", UDim2.fromScale(0.5, NM.DistanceCenterY), UDim2.fromScale(0.5, 0.075))
	distanceLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	distanceLabel.ZIndex = 4
	styleInkLabel(distanceLabel)
	distanceLabel.BackgroundColor3 = NM.InkStrokeColor
	distanceLabel.BackgroundTransparency = 0.3
	addCorner(distanceLabel, 0.3)

	buildCompass(scroll)

	-- ===== แผนที่จริง (ใช้ MapView เอาตัวแปลงพิกัดโลก → แผนที่ · ล้างสี/ป้ายเดิมของห้องรอออก) =====
	local view = MapView.create(
		scroll,
		UDim2.fromScale(0.5, NM.LandCenterY),
		UDim2.fromScale(NM.LandWidthFraction, NM.LandHeightFraction),
		Vector2.new(0.5, 0.5)
	)
	local land = view.frame
	land.ZIndex = 2
	land.BackgroundColor3 = NM.LandColor
	land.BackgroundTransparency = NM.LandTransparency
	for _, child in land:GetChildren() do
		if child:IsA("UIStroke") then
			child.Color = NM.EdgeColor
			child.Transparency = 0
		elseif child.Name == "North" then
			child:Destroy() -- ป้าย "เหนือ" ของ MapView · แผนที่นี้ใช้เข็มทิศแทน
		end
	end
	buildDecorations(view)

	-- เส้นประเดินทาง: สร้างครบชุดไว้ก่อน แล้วใช้ซ้ำ (ซ่อนที่เกิน) ไม่สร้างใหม่ทุกครั้งที่อัปเดต
	local dashes: { Frame } = {}
	for i = 1, NM.DashPoolSize do
		local dash = newFrame(
			land,
			"Dash" .. i,
			UDim2.fromScale(0.5, 0.5),
			UDim2.fromScale(0.02, NM.DashThickness),
			NM.InkColor,
			5
		)
		addCorner(dash, 0.5)
		dash.Visible = false
		dashes[i] = dash
	end
	local dashesShown = 0
	local lastDashKey = ""

	local targetIcon = buildTargetIcon(land)
	local playerIcon = buildPlayerIcon(land)
	playerIcon.Visible = false

	-- ===== สถานะที่ได้จากเซิร์ฟเวอร์ =====
	local active = false -- อยู่ในภารกิจ (ช่วง InMission และเป็นผู้ร่วมภารกิจ)
	local offered = false
	local markerPositions: { [string]: Vector2 } = {} -- ชื่อจุด → (x, z) โลก
	local markerIcons: { [string]: Frame } = {}
	local allowedMarkers: { [string]: boolean } = {}
	for _, markerName in Config.Map.MarkerNames do
		allowedMarkers[markerName] = true
	end

	local mateDots: { [number]: Frame } = {}
	local mateColors: { [number]: Color3 } = {}
	local mateColorCount = 0
	local itemIcons: { [Instance]: Frame } = {}

	-- ===== อ่านสถานะตัวเอง =====
	local function ownRoot(): BasePart?
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

	-- ใช้แผนที่ได้เมื่ออยู่ในภารกิจ และยังไม่ตาย (ปกติหรือล้ม)
	local function canUse(): boolean
		if not active then
			return false
		end
		local character = player.Character
		if character == nil then
			return false
		end
		local state = character:GetAttribute("State")
		if type(state) ~= "string" then
			return true -- ยังไม่ตั้งค่า = ปกติ (เหมือน MissionHud)
		end
		return state == "Alive" or state == "Downed"
	end

	-- ===== เส้นประ =====
	local function hideDashes()
		for i = 1, dashesShown do
			dashes[i].Visible = false
		end
		dashesShown = 0
		lastDashKey = ""
	end

	-- ax, ay / bx, by = ตำแหน่งบนแผนที่ (0–1) ของผู้เล่น / เป้าหมาย
	local function layoutDashes(ax: number, ay: number, bx: number, by: number)
		local key = string.format("%.4f|%.4f|%.4f|%.4f", ax, ay, bx, by)
		if key == lastDashKey then
			return
		end
		lastDashKey = key
		local dx, dy = (bx - ax) * MAP_ASPECT, by - ay -- หน่วย: ความสูงแผนที่ = 1
		local total = math.sqrt(dx * dx + dy * dy)
		local usable = total - NM.DashStartPad - NM.DashEndPad
		local count = 0
		if usable >= NM.DashLength then
			count = math.min(#dashes, math.floor((usable + NM.DashGap) / (NM.DashLength + NM.DashGap)))
		end
		local unitX, unitY = 0, 0
		if total > 0 then
			unitX, unitY = dx / total, dy / total
		end
		local rotation = math.deg(math.atan2(dy, dx))
		for i = 1, count do
			local distance = NM.DashStartPad + (i - 1) * (NM.DashLength + NM.DashGap) + NM.DashLength / 2
			local dash = dashes[i]
			dash.Position = UDim2.fromScale(ax + unitX * distance / MAP_ASPECT, ay + unitY * distance)
			dash.Size = UDim2.fromScale(NM.DashLength / MAP_ASPECT, NM.DashThickness)
			dash.Rotation = rotation
			dash.Visible = true
		end
		for i = count + 1, dashesShown do
			dashes[i].Visible = false
		end
		dashesShown = count
	end

	-- ===== เพื่อนร่วมทีม =====
	local function updateMates()
		local seen: { [number]: boolean } = {}
		for _, mate in rescue.getMates() do
			seen[mate.userId] = true
			local x, z = mate.x, mate.z
			local alive = mate.alive
			-- ถ้าตัวละครเพื่อนโหลดอยู่ฝั่งเรา (StreamingEnabled) ใช้ตำแหน่งสดแทนค่าเซิร์ฟเวอร์ที่อัปเดตทุก ~1 วิ
			local other = Players:GetPlayerByUserId(mate.userId)
			local character = if other ~= nil then other.Character else nil
			if character ~= nil then
				local mateRoot = character:FindFirstChild("HumanoidRootPart")
				if mateRoot ~= nil and mateRoot:IsA("BasePart") then
					x, z = mateRoot.Position.X, mateRoot.Position.Z
				end
				if character:GetAttribute("State") == "Dead" then
					alive = false
				end
			end
			local dot = mateDots[mate.userId]
			if dot == nil then
				mateColorCount += 1
				local palette = NM.MateColors
				mateColors[mate.userId] = palette[(mateColorCount - 1) % #palette + 1]
				dot = view.makeDot("Mate" .. mate.userId, mateColors[mate.userId], NM.MateSize, 9)
				addStroke(dot, NM.PlayerOutline, 1)
				mateDots[mate.userId] = dot
			end
			dot.Position = view.worldToMap(x, z)
			dot.BackgroundColor3 = if alive then mateColors[mate.userId] else NM.DeadMateColor
		end
		for userId, dot in mateDots do
			if not seen[userId] then
				dot:Destroy()
				mateDots[userId] = nil
			end
		end
	end

	-- ===== ของในภารกิจ (ตะกร้า / ถุงเงิน / ขนม) =====
	local function updateItems()
		local folder = Workspace:FindFirstChild(Config.Mission.ObjectsFolderName)
		local seen: { [Instance]: boolean } = {}
		if folder ~= nil then
			for _, child in folder:GetChildren() do
				local kind = child:GetAttribute("ItemKind")
				local position = pivotPositionOf(child)
				if type(kind) == "string" and position ~= nil and ITEM_COLORS[kind] ~= nil then
					seen[child] = true
					local icon = itemIcons[child]
					if icon == nil then
						icon = buildItemIcon(land, kind, ITEM_COLORS[kind])
						itemIcons[child] = icon
					end
					local at = view.worldToMap(position.X, position.Z)
					if child:GetAttribute("Held") == true then
						-- ของที่มีคนถือ: ขยับออกจากจุดคนถือนิดหน่อย ไม่ให้จุดคนบังมิดเห็นแต่ไม่เห็นของ
						at = UDim2.fromScale(at.X.Scale + 0.03 / MAP_ASPECT, at.Y.Scale - 0.03)
					end
					icon.Position = at
				end
			end
		end
		for inst, icon in itemIcons do
			if not seen[inst] then
				icon:Destroy()
				itemIcons[inst] = nil
			end
		end
	end

	-- ===== วาดทั้งแผนที่ (เรียกตามจังหวะ UpdateHz เท่านั้น) =====
	local lastDistanceText = ""
	local function updateMap()
		local targetName = if offered then "RocketPad" else "Kuti"
		local targetWorld = markerPositions[targetName]
		local root = ownRoot()

		local playerAt: UDim2? = nil
		if root ~= nil then
			playerAt = view.worldToMap(root.Position.X, root.Position.Z)
			playerIcon.Position = playerAt
		end
		playerIcon.Visible = playerAt ~= nil

		local targetAt: UDim2? = nil
		if targetWorld ~= nil then
			targetAt = view.worldToMap(targetWorld.X, targetWorld.Y)
			targetIcon.Position = targetAt
		end
		targetIcon.Visible = targetAt ~= nil

		if playerAt ~= nil and targetAt ~= nil then
			layoutDashes(playerAt.X.Scale, playerAt.Y.Scale, targetAt.X.Scale, targetAt.Y.Scale)
		elseif dashesShown > 0 then
			hideDashes()
		end

		-- ข้อความระยะทาง (คิดจากพิกัดโลกจริง ไม่ใช่พิกัดที่ถูกบีบในกรอบแผนที่)
		local text = NM.NoTargetText
		if root ~= nil and targetWorld ~= nil then
			local dx, dz = targetWorld.X - root.Position.X, targetWorld.Y - root.Position.Z
			local meters = math.floor(math.sqrt(dx * dx + dz * dz) * Config.Map.MetersPerStud + 0.5)
			text = "อีก " .. meters .. " ม. " .. (if offered then NM.DistanceToRocket else NM.DistanceToKuti)
		end
		if text ~= lastDistanceText then
			lastDistanceText = text
			distanceLabel.Text = text
		end

		updateMates()
		updateItems()
	end

	-- หมุนลูกศรตามทิศที่กล้องมอง (เหนือ = ขึ้นบน · หมุนตามเข็ม = ตะวันออก)
	local function updateHeading()
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return
		end
		local look = camera.CFrame.LookVector
		if look.X * look.X + look.Z * look.Z < 0.0001 then
			return -- มองดิ่งขึ้น/ลง ไม่มีทิศ
		end
		playerIcon.Rotation = math.deg(math.atan2(look.X, -look.Z))
	end

	-- ===== เปิด/ปิดแผนที่ =====
	local heldByButton = false
	local heldByKey = false
	local isOpen = false
	local openConnection: RBXScriptConnection? = nil
	local sinceUpdate = 0

	local function setOpen(open: boolean)
		if open == isOpen then
			return
		end
		isOpen = open
		scroll.Visible = open
		if open then
			sinceUpdate = 0
			updateMap()
			updateHeading()
			openConnection = RunService.RenderStepped:Connect(function(dt: number)
				updateHeading()
				sinceUpdate += dt
				if sinceUpdate >= 1 / NM.UpdateHz then
					sinceUpdate = 0
					updateMap()
				end
			end)
		else
			local connection = openConnection
			if connection ~= nil then
				connection:Disconnect()
				openConnection = nil
			end
		end
	end

	-- ตัดสินปุ่ม/แผนที่ใหม่: ใช้ไม่ได้ (ตาย/ออกภารกิจ) = ซ่อนปุ่ม + เลิกถือค้าง + ปิดแผนที่
	local lastButtonVisible = false
	local function refresh()
		local usable = canUse()
		if usable ~= lastButtonVisible then
			lastButtonVisible = usable
			button.Visible = usable
		end
		if not usable then
			heldByButton = false
			heldByKey = false
		end
		setOpen(usable and (heldByButton or heldByKey))
	end

	-- กดค้าง/ปล่อย: bindHold ฟังการปล่อยจากตัว input เอง แม้นิ้วลากออกนอกปุ่มก็ถือว่าปล่อย
	Hud.bindHold(button, function()
		heldByButton = true
		refresh()
	end, function()
		heldByButton = false
		refresh()
	end)

	-- คีย์ลัดบนคอม (มือถือใช้ปุ่มบนจอ)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard or input.KeyCode ~= NM.HoldKey then
			return
		end
		heldByKey = true
		refresh()
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == NM.HoldKey then
			heldByKey = false
			refresh()
		end
	end)
	-- สลับหน้าต่างระหว่างกดค้าง จะไม่ได้รับเหตุการณ์ปล่อย → ถือว่าปล่อยแล้ว กันแผนที่ค้าง
	UserInputService.WindowFocusReleased:Connect(function()
		heldByButton = false
		heldByKey = false
		refresh()
	end)

	-- ตรวจสถานะตัวละคร (ตาย/ล้ม/ฟื้น) เป็นระยะ — เบามาก ไม่แตะ GUI ถ้าไม่เปลี่ยน
	local sinceCheck = 0
	RunService.Heartbeat:Connect(function(dt: number)
		sinceCheck += dt
		if sinceCheck >= NM.ButtonCheckSeconds then
			sinceCheck = 0
			refresh()
		end
	end)

	return {
		onSnapshot = function(snapshot: { [string]: any })
			active = snapshot.phase == "InMission" and snapshot.inLobby ~= true
			offered = snapshot.offered == true
			local markers = snapshot.markers
			if type(markers) == "table" then
				for _, marker in markers do
					if
						type(marker) == "table"
						and type(marker.name) == "string"
						and allowedMarkers[marker.name] == true
						and type(marker.x) == "number"
						and type(marker.z) == "number"
					then
						local name: string = marker.name
						markerPositions[name] = Vector2.new(marker.x, marker.z)
						local icon = markerIcons[name]
						if icon == nil then
							icon = buildMarkerIcon(land, name)
							markerIcons[name] = icon
						end
						icon.Position = view.worldToMap(marker.x, marker.z)
					end
				end
			end
			refresh()
			if isOpen then
				updateMap() -- ถวายอาหารแล้วเป้าหมายเปลี่ยน: อัปเดตทันที ไม่ต้องรอรอบถัดไป
			end
		end,
	}
end

return NavMap
