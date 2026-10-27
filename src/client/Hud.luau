--!strict
-- Hud: สร้างหน้าจอขณะเล่น (มือถือเป็นหลัก) — ใช้ Scale ทั้งหมด + UIAspectRatioConstraint ให้ปุ่มกลม
-- โมดูลนี้ "วาด" อย่างเดียว ไม่ส่งคำขอไปเซิร์ฟเวอร์ (Controls.luau เป็นคนต่อสาย)

local Players = game:GetService("Players")

local Hud = {}

export type Refs = {
	gui: ScreenGui,
	fire: TextButton,
	aim: TextButton,
	reload: TextButton,
	throw: TextButton,
	context: TextButton,
	slots: { TextButton },
	crosshair: Frame,
	setHealth: (hp: number, maxHp: number) -> (),
	setMoney: (money: number) -> (),
	setAmmoText: (text: string) -> (),
	setSlotLabels: (labels: { string }, selected: number) -> (),
	setThrowEnabled: (enabled: boolean) -> (),
	setAimActive: (active: boolean) -> (),
	setContext: (visible: boolean, text: string) -> (),
	setProgress: (fraction: number?, text: string) -> (),
	setOverlay: (kind: string, secondsLeft: number) -> (),
}

local FONT = Enum.Font.GothamBold
local DARK = Color3.fromRGB(25, 28, 33)
local WHITE = Color3.fromRGB(255, 255, 255)

local function formatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function addTextSize(label: GuiObject, maxSize: number)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxSize
	constraint.MinTextSize = 8
	constraint.Parent = label
end

local function makeLabel(parent: Instance, name: string, text: string, position: UDim2, size: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = FONT
	label.Text = text
	label.TextColor3 = WHITE
	label.TextStrokeTransparency = 0.5
	label.TextScaled = true
	label.Parent = parent
	addTextSize(label, 28)
	return label
end

-- ปุ่มวางตามสัดส่วนจอ: center = ตำแหน่งกึ่งกลาง (0–1), sizeScale = ขนาดเทียบจอ
-- ปุ่มกลม (aspect 1:1) ถ้า round=true
local function makeButton(
	parent: Instance,
	name: string,
	text: string,
	center: Vector2,
	sizeScale: number,
	round: boolean
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(center.X, center.Y)
	button.Size = UDim2.fromScale(sizeScale, sizeScale)
	button.BackgroundColor3 = DARK
	button.BackgroundTransparency = 0.3
	button.AutoButtonColor = false
	button.Font = FONT
	button.Text = text
	button.TextColor3 = WHITE
	button.TextScaled = true
	button.Active = true
	button.Parent = parent
	addTextSize(button, 26)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.1, 0)
	pad.PaddingRight = UDim.new(0.1, 0)
	pad.PaddingTop = UDim.new(0.2, 0)
	pad.PaddingBottom = UDim.new(0.2, 0)
	pad.Parent = button

	local corner = Instance.new("UICorner")
	corner.CornerRadius = if round then UDim.new(0.5, 0) else UDim.new(0.2, 0)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = WHITE
	stroke.Transparency = 0.5
	stroke.Thickness = 2
	stroke.Parent = button

	if round then
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.AspectRatio = 1
		ratio.Parent = button
	end
	return button
end

function Hud.create(): Refs
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- เลี่ยงรอยบาก/ขอบจอ
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	-- แถบเลือด (บนซ้าย)
	local hpBack = Instance.new("Frame")
	hpBack.Name = "HealthBar"
	hpBack.Position = UDim2.fromScale(0.02, 0.03)
	hpBack.Size = UDim2.fromScale(0.28, 0.06)
	hpBack.BackgroundColor3 = DARK
	hpBack.BackgroundTransparency = 0.3
	hpBack.BorderSizePixel = 0
	hpBack.Parent = gui
	local hpCorner = Instance.new("UICorner")
	hpCorner.CornerRadius = UDim.new(0.3, 0)
	hpCorner.Parent = hpBack
	local hpFill = Instance.new("Frame")
	hpFill.Name = "Fill"
	hpFill.Size = UDim2.fromScale(1, 1)
	hpFill.BackgroundColor3 = Color3.fromRGB(80, 200, 100)
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpBack
	local hpFillCorner = Instance.new("UICorner")
	hpFillCorner.CornerRadius = UDim.new(0.3, 0)
	hpFillCorner.Parent = hpFill
	local hpText = makeLabel(hpBack, "Text", "เลือด 100", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
	hpText.ZIndex = 2

	-- เงิน (บนขวา)
	local moneyLabel = makeLabel(gui, "Money", "เงิน 0", UDim2.fromScale(0.70, 0.03), UDim2.fromScale(0.28, 0.06))
	moneyLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- จุดเล็งกลางจอ (มือถือไม่มีเมาส์)
	local crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	crosshair.Size = UDim2.fromScale(0.012, 0.012)
	crosshair.BackgroundColor3 = WHITE
	crosshair.BackgroundTransparency = 0.2
	crosshair.BorderSizePixel = 0
	crosshair.Parent = gui
	local chRatio = Instance.new("UIAspectRatioConstraint")
	chRatio.AspectRatio = 1
	chRatio.Parent = crosshair
	local chCorner = Instance.new("UICorner")
	chCorner.CornerRadius = UDim.new(0.5, 0)
	chCorner.Parent = crosshair

	-- ปุ่มฝั่งขวา (นิ้วโป้งขวา)
	local fire = makeButton(gui, "Fire", "ยิง", Vector2.new(0.86, 0.72), 0.26, true)
	fire.BackgroundColor3 = Color3.fromRGB(190, 60, 50)
	local aim = makeButton(gui, "Aim", "เล็ง", Vector2.new(0.66, 0.84), 0.13, true)
	local reload = makeButton(gui, "Reload", "เปลี่ยนแม็ก", Vector2.new(0.67, 0.64), 0.14, true)
	local throw = makeButton(gui, "Throw", "ขว้างประทัด", Vector2.new(0.80, 0.45), 0.14, true)
	-- ปุ่มตามสถานการณ์ (หยิบ/ชุบ/มัดตัว/ถวาย) = ปุ่มเดียว กลางขวา
	local context = makeButton(gui, "Context", "", Vector2.new(0.92, 0.33), 0.16, true)
	context.BackgroundColor3 = Color3.fromRGB(230, 160, 40)
	context.Visible = false

	-- แถบเลือกอาวุธ (ล่างกลาง-ซ้าย)
	local slotBar = Instance.new("Frame")
	slotBar.Name = "SlotBar"
	slotBar.AnchorPoint = Vector2.new(0.5, 1)
	slotBar.Position = UDim2.fromScale(0.40, 0.97)
	slotBar.Size = UDim2.fromScale(0.30, 0.10)
	slotBar.BackgroundTransparency = 1
	slotBar.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0.02, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = slotBar
	local slots: { TextButton } = {}
	for i = 1, 3 do
		local b = Instance.new("TextButton")
		b.Name = "Slot" .. i
		b.LayoutOrder = i
		b.Size = UDim2.fromScale(0.32, 1)
		b.BackgroundColor3 = DARK
		b.BackgroundTransparency = 0.3
		b.AutoButtonColor = false
		b.Font = FONT
		b.Text = tostring(i)
		b.TextColor3 = WHITE
		b.TextScaled = true
		b.Parent = slotBar
		addTextSize(b, 22)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.2, 0)
		c.Parent = b
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0.06, 0)
		p.PaddingRight = UDim.new(0.06, 0)
		p.PaddingTop = UDim.new(0.2, 0)
		p.PaddingBottom = UDim.new(0.2, 0)
		p.Parent = b
		local s = Instance.new("UIStroke")
		s.Name = "Stroke"
		s.Color = WHITE
		s.Transparency = 0.6
		s.Thickness = 2
		s.Parent = b
		slots[i] = b
	end

	-- กระสุน/ประทัด (เหนือแถบอาวุธ)
	local ammoLabel = makeLabel(gui, "Ammo", "", UDim2.fromScale(0.25, 0.80), UDim2.fromScale(0.30, 0.06))

	-- แถบความคืบหน้า (ชุบเพื่อน) กลางจอ
	local progressBack = Instance.new("Frame")
	progressBack.Name = "Progress"
	progressBack.AnchorPoint = Vector2.new(0.5, 0.5)
	progressBack.Position = UDim2.fromScale(0.5, 0.64)
	progressBack.Size = UDim2.fromScale(0.30, 0.05)
	progressBack.BackgroundColor3 = DARK
	progressBack.BackgroundTransparency = 0.3
	progressBack.BorderSizePixel = 0
	progressBack.Visible = false
	progressBack.Parent = gui
	local pbCorner = Instance.new("UICorner")
	pbCorner.CornerRadius = UDim.new(0.4, 0)
	pbCorner.Parent = progressBack
	local progressFill = Instance.new("Frame")
	progressFill.Name = "Fill"
	progressFill.Size = UDim2.fromScale(0, 1)
	progressFill.BackgroundColor3 = Color3.fromRGB(230, 160, 40)
	progressFill.BorderSizePixel = 0
	progressFill.Parent = progressBack
	local pfCorner = Instance.new("UICorner")
	pfCorner.CornerRadius = UDim.new(0.4, 0)
	pfCorner.Parent = progressFill
	local progressText = makeLabel(progressBack, "Text", "", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
	progressText.ZIndex = 2

	-- จอล้ม / จอตาย (ไม่มีภาพเลือด ใช้สีทึบโปร่งแสง)
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.Active = false
	overlay.ZIndex = 0
	overlay.Parent = gui
	local overlayText = makeLabel(overlay, "Text", "", UDim2.fromScale(0.15, 0.18), UDim2.fromScale(0.70, 0.14))
	addTextSize(overlayText, 40)

	-- ===== ฟังก์ชันอัปเดต =====
	local refs: Refs = {
		gui = gui,
		fire = fire,
		aim = aim,
		reload = reload,
		throw = throw,
		context = context,
		slots = slots,
		crosshair = crosshair,
		setHealth = function(hp: number, maxHp: number)
			local fraction = math.clamp(hp / math.max(maxHp, 1), 0, 1)
			hpFill.Size = UDim2.fromScale(fraction, 1)
			hpFill.BackgroundColor3 = if fraction > 0.4 then Color3.fromRGB(80, 200, 100) else Color3.fromRGB(220, 150, 40)
			hpText.Text = "เลือด " .. math.ceil(hp)
		end,
		setMoney = function(money: number)
			moneyLabel.Text = "เงิน " .. money
		end,
		setAmmoText = function(text: string)
			ammoLabel.Text = text
		end,
		setSlotLabels = function(labels: { string }, selected: number)
			for i, b in slots do
				b.Text = labels[i] or tostring(i)
				local stroke = b:FindFirstChild("Stroke")
				if stroke ~= nil and stroke:IsA("UIStroke") then
					stroke.Transparency = if i == selected then 0 else 0.6
					stroke.Thickness = if i == selected then 4 else 2
				end
				b.BackgroundTransparency = if i == selected then 0.05 else 0.4
			end
		end,
		setThrowEnabled = function(enabled: boolean)
			throw.BackgroundTransparency = if enabled then 0.3 else 0.75
			throw.TextTransparency = if enabled then 0 else 0.5
		end,
		setAimActive = function(active: boolean)
			aim.BackgroundColor3 = if active then Color3.fromRGB(60, 120, 200) else DARK
		end,
		setContext = function(visible: boolean, text: string)
			context.Visible = visible
			context.Text = text
		end,
		setProgress = function(fraction: number?, text: string)
			if fraction == nil then
				progressBack.Visible = false
				return
			end
			progressBack.Visible = true
			progressFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			progressText.Text = text
		end,
		setOverlay = function(kind: string, secondsLeft: number)
			if kind == "Downed" then
				overlay.Visible = true
				overlay.BackgroundColor3 = Color3.fromRGB(150, 90, 30)
				overlay.BackgroundTransparency = 0.6
				overlayText.Text = "ล้มแล้ว — รอเพื่อนมาชุบ " .. formatTime(secondsLeft)
			elseif kind == "Dead" then
				overlay.Visible = true
				overlay.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
				overlay.BackgroundTransparency = 0.35
				overlayText.Text = "ตายแล้ว — รอ " .. formatTime(secondsLeft)
			else
				overlay.Visible = false
			end
		end,
	}
	return refs
end

-- ปุ่มกดค้าง: onDown ตอนเริ่มแตะ/คลิก, onUp ตอนปล่อย (แม้นิ้วลากออกนอกปุ่มก็ถือว่าปล่อย)
function Hud.bindHold(button: GuiButton, onDown: () -> (), onUp: () -> ())
	button.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then
			return
		end
		onDown()
		local released = false
		local conn: RBXScriptConnection? = nil
		conn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End and not released then
				released = true
				if conn ~= nil then
					conn:Disconnect()
				end
				onUp()
			end
		end)
	end)
end

return Hud
