--!strict
-- LobbyUi: หน้าจอห้องรอ (มือถือเป็นหลัก — ใช้ Scale ทั้งหมด ปุ่มใหญ่ ข้อความไทย)
-- - ร้านปืน · แลกขนม · เงิน · แผนที่เลือกจุดลง (หัวห้อง) · ปุ่มพร้อม (x/N) + นับถอยหลัง
-- - client "โง่": ส่งแค่คำขอ แล้ววาดตามสถานะที่เซิร์ฟเวอร์ส่งมา (MissionState) · เซิร์ฟเวอร์ตรวจทุกอย่างอีกชั้น
-- - เห็นเฉพาะช่วง Lobby และซ่อนปุ่ม HUD ต่อสู้ (Hud.setCombatVisible) · ช่วงอื่นของคนที่รอ/กำลังถูกยิงแสดงข้อความแจ้ง

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Hud = require(script.Parent.Hud)
local MapView = require(script.Parent.MapView)

local FONT = Enum.Font.GothamBold
local DARK = Color3.fromRGB(25, 28, 33)
local WHITE = Color3.fromRGB(255, 255, 255)
local GREEN = Color3.fromRGB(60, 160, 90)
local ORANGE = Color3.fromRGB(215, 140, 40)
local GREY = Color3.fromRGB(90, 95, 105)
local BLUE = Color3.fromRGB(60, 120, 200)

local TOP_ROW_Y = 0.13 -- ใต้แถบปุ่มของ Roblox (IgnoreGuiInset = true) เหมือน Hud

type ShopRow = {
	id: string,
	button: TextButton,
}

local LobbyUi = {}

-- ===== ตัวช่วยสร้าง UI =====

local function addCorner(inst: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = inst
end

local function addTextLimit(inst: GuiObject, maxSize: number)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxSize
	constraint.MinTextSize = 8
	constraint.Parent = inst
end

local function makePanel(parent: Instance, name: string, position: UDim2, size: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = DARK
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Parent = parent
	addCorner(frame, 0.06)
	return frame
end

local function makeLabel(
	parent: Instance,
	name: string,
	text: string,
	position: UDim2,
	size: UDim2,
	maxTextSize: number
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = FONT
	label.Text = text
	label.TextColor3 = WHITE
	label.TextStrokeTransparency = 0.6
	label.TextScaled = true
	label.Parent = parent
	addTextLimit(label, maxTextSize)
	return label
end

local function makeButton(
	parent: Instance,
	name: string,
	text: string,
	position: UDim2,
	size: UDim2,
	color: Color3,
	maxTextSize: number
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = color
	button.AutoButtonColor = true
	button.Font = FONT
	button.Text = text
	button.TextColor3 = WHITE
	button.TextScaled = true
	button.Active = true
	button.Parent = parent
	addTextLimit(button, maxTextSize)
	addCorner(button, 0.2)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = button
	return button
end

-- ===== เริ่มระบบ =====

-- onSnapshot: ส่งต่อสถานะภารกิจที่เซิร์ฟเวอร์ส่งมา (MissionState) ให้ MissionHud ใช้ด้วย
function LobbyUi.start(
	hud: Hud.Refs,
	onSnapshot: ((snapshot: { [string]: any }) -> ())?
): { onData: (payload: any) -> () }
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local missionState = remotes:WaitForChild("MissionState") :: RemoteEvent
	local getMissionState = remotes:WaitForChild("GetMissionState") :: RemoteFunction
	local setReadyRemote = remotes:WaitForChild("MissionSetReady") :: RemoteEvent
	local setLandingRemote = remotes:WaitForChild("MissionSetLanding") :: RemoteEvent
	local buyGunRemote = remotes:WaitForChild("BuyGun") :: RemoteFunction
	local exchangeRemote = remotes:WaitForChild("ExchangeSnacks") :: RemoteFunction
	local selectGunRemote = remotes:WaitForChild("CombatSelectGun") :: RemoteEvent
	local combatStateRemote = remotes:WaitForChild("CombatState") :: RemoteEvent

	-- ข้อมูลของตัวเอง (มาจาก DataChanged เท่านั้น) และสถานะล่าสุดจากเซิร์ฟเวอร์
	local money = 0
	local snacks = 0
	local owned: { [string]: boolean } = {}
	local equippedGunId: string? = nil
	local snapshot: { [string]: any }? = nil
	local isLeader = false
	local busy = false -- กำลังรอผลซื้อ/แลก กันกดซ้ำ
	local toastToken = 0

	hud.setCombatVisible(false) -- เริ่มที่ห้องรอ: ซ่อนปุ่มต่อสู้จนกว่าจะรู้สถานะจริง

	local gui = Instance.new("ScreenGui")
	gui.Name = "Lobby"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- เลี่ยงรอยบาก/ขอบจอ
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2
	gui.Parent = playerGui

	local lobbyRoot = Instance.new("Frame")
	lobbyRoot.Name = "LobbyRoot"
	lobbyRoot.Size = UDim2.fromScale(1, 1)
	lobbyRoot.BackgroundTransparency = 1
	lobbyRoot.BorderSizePixel = 0
	lobbyRoot.Visible = false
	lobbyRoot.Parent = gui

	-- ข้อความกลางจอ (รอภารกิจจบ / กำลังถูกยิง)
	local noticeBack = makePanel(gui, "Notice", UDim2.fromScale(0.15, 0.40), UDim2.fromScale(0.70, 0.20))
	noticeBack.Visible = false
	local noticeText = makeLabel(noticeBack, "Text", "", UDim2.fromScale(0.04, 0.1), UDim2.fromScale(0.92, 0.8), 36)

	-- ===== เงิน =====
	local moneyLabel = makeLabel(
		lobbyRoot,
		"Money",
		"เงิน 0",
		UDim2.fromScale(0.70, TOP_ROW_Y),
		UDim2.fromScale(0.28, 0.06),
		28
	)
	moneyLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- ===== ร้านปืน =====
	local shopPanel = makePanel(lobbyRoot, "Shop", UDim2.fromScale(0.02, 0.14), UDim2.fromScale(0.33, 0.52))
	makeLabel(shopPanel, "Title", "ร้านปืน", UDim2.fromScale(0.04, 0.01), UDim2.fromScale(0.92, 0.09), 24)

	local gunIds: { string } = {}
	for id in Config.Guns do
		table.insert(gunIds, id)
	end
	table.sort(gunIds, function(a: string, b: string)
		local ga, gb = Config.Guns[a], Config.Guns[b]
		if ga == nil or gb == nil or ga.price == gb.price then
			return a < b
		end
		return ga.price < gb.price
	end)

	local shopRows: { ShopRow } = {}
	local priceLabels: { [string]: TextLabel } = {}
	local rowHeight = 0.28 -- ปุ่มสูง ≈ 0.92 × 0.28 × 0.52 ≈ 13% ของความสูงจอ แตะง่าย
	for index, id in gunIds do
		local def = Config.Guns[id]
		if def ~= nil then
			local top = 0.11 + (index - 1) * (rowHeight + 0.015)
			local row = Instance.new("Frame")
			row.Name = "Row_" .. id
			row.Position = UDim2.fromScale(0.03, top)
			row.Size = UDim2.fromScale(0.94, rowHeight)
			row.BackgroundTransparency = 1
			row.Parent = shopPanel
			local nameLabel =
				makeLabel(row, "Name", def.displayName, UDim2.fromScale(0, 0), UDim2.fromScale(0.54, 0.55), 22)
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			local priceLabel = makeLabel(
				row,
				"Price",
				if def.price == 0 then "ฟรี" else def.price .. " เงิน",
				UDim2.fromScale(0, 0.55),
				UDim2.fromScale(0.54, 0.42),
				18
			)
			priceLabel.TextXAlignment = Enum.TextXAlignment.Left
			priceLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
			priceLabels[id] = priceLabel
			local button = makeButton(
				row,
				"Action",
				"ซื้อ",
				UDim2.fromScale(0.58, 0.04),
				UDim2.fromScale(0.42, 0.92),
				BLUE,
				22
			)
			table.insert(shopRows, { id = id, button = button })
		end
	end

	-- ===== แลกขนม =====
	-- อยู่คอลัมน์ขวา ใต้ป้ายเงิน (พ้นโซนจอยสติ๊กซ้ายล่าง) · ปุ่มสูง ≈ 0.5 × 0.26 = 13% ของจอ
	local snackPanel = makePanel(lobbyRoot, "Snacks", UDim2.fromScale(0.80, 0.20), UDim2.fromScale(0.18, 0.26))
	local snackLabel = makeLabel(snackPanel, "Info", "", UDim2.fromScale(0.04, 0.03), UDim2.fromScale(0.92, 0.40), 20)
	snackLabel.TextWrapped = true
	local exchangeButton = makeButton(
		snackPanel,
		"Exchange",
		"แลกขนม",
		UDim2.fromScale(0.04, 0.46),
		UDim2.fromScale(0.92, 0.5),
		ORANGE,
		22
	)

	-- ข้อความตอบกลับสั้น ๆ (ซื้อสำเร็จ/เงินไม่พอ ฯลฯ)
	local toastLabel =
		makeLabel(lobbyRoot, "Toast", "", UDim2.fromScale(0.37, TOP_ROW_Y), UDim2.fromScale(0.32, 0.06), 22)
	toastLabel.TextColor3 = Color3.fromRGB(255, 235, 150)

	local function showToast(text: string)
		toastToken += 1
		local myToken = toastToken
		toastLabel.Text = text
		task.delay(3, function()
			if toastToken == myToken then
				toastLabel.Text = ""
			end
		end)
	end

	-- ===== แผนที่เลือกจุดลง =====
	local mapWidth = 2 * Config.Map.HalfWidthStuds
	local mapDepth = 2 * Config.Map.HalfDepthStuds
	local mapView = MapView.create(lobbyRoot, UDim2.fromScale(0.37, 0.20), UDim2.fromScale(0.41, 0.50))
	local mapFrame = mapView.frame

	local function requestLanding(worldX: number, worldZ: number)
		local s = snapshot
		if s == nil or s.phase ~= "Lobby" or not isLeader then
			return -- ไม่ใช่หัวห้อง: ดูได้อย่างเดียว (เซิร์ฟเวอร์ตรวจซ้ำอีกชั้น)
		end
		local endsAt = s.countdownEndsAt
		if type(endsAt) == "number" and endsAt > 0 then
			showToast(
				"กำลังนับถอยหลัง กดยกเลิกพร้อมก่อนถ้าจะเปลี่ยนจุดลง"
			)
			return
		end
		local limitX = Config.Map.HalfWidthStuds - Config.Map.LandingMarginStuds
		local limitZ = Config.Map.HalfDepthStuds - Config.Map.LandingMarginStuds
		setLandingRemote:FireServer(math.clamp(worldX, -limitX, limitX), math.clamp(worldZ, -limitZ, limitZ))
	end

	-- ช่องกริดโปร่งใสให้แตะ (แตะช่องไหน = จุดลงอยู่กลางช่องนั้น) — ไม่ต้องแปลงพิกัดนิ้ว จึงเที่ยงตรงทุกอุปกรณ์
	local cols, rows = Config.Lobby.MapGridCols, Config.Lobby.MapGridRows
	for col = 1, cols do
		for row = 1, rows do
			local cell = Instance.new("TextButton")
			cell.Name = "Cell"
			cell.Text = ""
			cell.AutoButtonColor = false
			cell.BorderSizePixel = 0
			cell.BackgroundColor3 = WHITE
			cell.BackgroundTransparency = if (col + row) % 2 == 0 then 0.93 else 1 -- ลายหมากรุกจาง ๆ บอกว่าแตะได้
			cell.Position = UDim2.fromScale((col - 1) / cols, (row - 1) / rows)
			cell.Size = UDim2.fromScale(1 / cols, 1 / rows)
			cell.ZIndex = 1
			cell.Parent = mapFrame
			local worldX = -Config.Map.HalfWidthStuds + (col - 0.5) / cols * mapWidth
			local worldZ = -Config.Map.HalfDepthStuds + (row - 0.5) / rows * mapDepth
			cell.Activated:Connect(function()
				requestLanding(worldX, worldZ)
			end)
		end
	end

	local landingDot = mapView.makeDot("Landing", MapView.COLOR_LANDING, 0.07, 4)
	local landingStroke = Instance.new("UIStroke")
	landingStroke.Color = WHITE
	landingStroke.Thickness = 2
	landingStroke.Parent = landingDot

	local hintLabel = makeLabel(lobbyRoot, "Hint", "", UDim2.fromScale(0.37, 0.71), UDim2.fromScale(0.41, 0.07), 20)
	hintLabel.TextWrapped = true
	local legendLabel = makeLabel(lobbyRoot, "Legend", "", UDim2.fromScale(0.37, 0.79), UDim2.fromScale(0.41, 0.05), 16)
	legendLabel.RichText = true
	legendLabel.Text = string.format(
		'<font color="%s">●</font> กุฏิ  <font color="%s">●</font> รังลิง  <font color="%s">●</font> ฐานบั้งไฟ  <font color="%s">●</font> จุดลง',
		MapView.colorHex(MapView.COLOR_KUTI),
		MapView.colorHex(MapView.COLOR_NEST),
		MapView.colorHex(MapView.COLOR_ROCKET),
		MapView.colorHex(MapView.COLOR_LANDING)
	)

	-- ===== ปุ่มพร้อม + นับถอยหลัง =====
	-- คอลัมน์ขวา ใต้ช่องแลกขนม เหนือบริเวณปุ่มกระโดดของ Roblox (มุมขวาล่าง)
	local readyButton = makeButton(
		lobbyRoot,
		"Ready",
		"พร้อม",
		UDim2.fromScale(0.82, 0.56),
		UDim2.fromScale(0.16, 0.16), -- ล่างสุดที่ y = 0.72 พ้นโซนปุ่มกระโดด (x > 0.86, y > 0.72)
		GREEN,
		30
	)
	local countdownLabel =
		makeLabel(lobbyRoot, "Countdown", "", UDim2.fromScale(0.80, 0.47), UDim2.fromScale(0.20, 0.08), 26)
	countdownLabel.TextColor3 = Color3.fromRGB(255, 235, 150)

	-- ===== วาดตามข้อมูล =====
	local function refreshMoney()
		moneyLabel.Text = "เงิน " .. money
	end

	local function refreshShop()
		for _, shopRow in shopRows do
			local def = Config.Guns[shopRow.id]
			if def ~= nil then
				local button = shopRow.button
				if owned[shopRow.id] then
					if equippedGunId == shopRow.id then
						button.Text = "ถืออยู่"
						button.BackgroundColor3 = GREEN
						button.AutoButtonColor = false
					else
						button.Text = "ใช้ปืนนี้"
						button.BackgroundColor3 = BLUE
						button.AutoButtonColor = true
					end
					button.BackgroundTransparency = 0
				else
					button.Text = "ซื้อ"
					button.BackgroundColor3 = ORANGE
					button.AutoButtonColor = true
					button.BackgroundTransparency = if money >= def.price then 0 else 0.5 -- เงินไม่พอ = จางลง (ยังกดได้ เซิร์ฟเวอร์ตอบ)
				end
			end
		end
	end

	local function refreshSnacks()
		snackLabel.Text = "ขนมพระ "
			.. snacks
			.. " ห่อ\n(ห่อละ "
			.. Config.Snacks.ExchangeMoney
			.. " เงิน)"
		exchangeButton.Text = if snacks > 0
			then "แลกขนม (+" .. snacks * Config.Snacks.ExchangeMoney .. ")"
			else "แลกขนม"
		exchangeButton.BackgroundTransparency = if snacks > 0 then 0 else 0.5
	end

	-- ผลลัพธ์จากเซิร์ฟเวอร์: { ok: boolean, message: string }
	local function handleResult(result: any): boolean
		if type(result) == "table" and type(result.message) == "string" then
			showToast(result.message)
			return result.ok == true
		end
		showToast("เกิดข้อผิดพลาด ลองใหม่อีกครั้ง")
		return false
	end

	for _, shopRow in shopRows do
		shopRow.button.Activated:Connect(function()
			if busy then
				return
			end
			local id = shopRow.id
			if owned[id] then
				if equippedGunId ~= id then
					selectGunRemote:FireServer(id) -- เซิร์ฟเวอร์ตรวจว่ามีปืนนี้จริง แล้วส่งสถานะกลับมา
				end
				return
			end
			busy = true
			local ok, result = pcall(function()
				return buyGunRemote:InvokeServer(id)
			end)
			busy = false
			if ok then
				if handleResult(result) then
					selectGunRemote:FireServer(id) -- ซื้อแล้วถือเลย
				end
			else
				showToast("เกิดข้อผิดพลาด ลองใหม่อีกครั้ง")
			end
		end)
	end

	exchangeButton.Activated:Connect(function()
		if busy then
			return
		end
		if snacks < 1 then
			showToast("ไม่มีขนมให้แลก")
			return
		end
		busy = true
		local ok, result = pcall(function()
			return exchangeRemote:InvokeServer(snacks)
		end)
		busy = false
		if ok then
			handleResult(result)
		else
			showToast("เกิดข้อผิดพลาด ลองใหม่อีกครั้ง")
		end
	end)

	local myReady = false
	local myEligible = true
	readyButton.Activated:Connect(function()
		if snapshot == nil or snapshot.phase ~= "Lobby" or not myEligible then
			return
		end
		setReadyRemote:FireServer(not myReady)
	end)

	local function applySnapshot(s: { [string]: any })
		snapshot = s
		if onSnapshot ~= nil then
			onSnapshot(s)
		end
		local phase = s.phase
		local inLobby = s.inLobby == true

		-- ใครเห็นอะไร: ห้องรอ (เฉพาะช่วง Lobby) · รอภารกิจจบ · กำลังถูกยิง · HUD ต่อสู้ (อยู่ในภารกิจแล้ว)
		local showLobby = phase == "Lobby" and inLobby
		local waiting = phase ~= "Lobby" and inLobby
		local launching = phase == "Launching" and not inLobby
		lobbyRoot.Visible = showLobby
		hud.setCombatVisible(not inLobby and not launching)
		noticeBack.Visible = waiting or launching
		if waiting then
			noticeText.Text =
				"กำลังมีภารกิจอยู่ รอเพื่อนเล่นจบก่อนนะ แล้วจะได้เข้าห้องรอพร้อมกัน"
		elseif launching then
			noticeText.Text =
				"กำลังถูกยิงด้วยหนังสติ๊ก! เตรียมตัวลงพื้น"
		end

		isLeader = s.leaderUserId == player.UserId
		myReady = false
		myEligible = s.eligible == true
		if type(s.members) == "table" then
			for _, member in s.members do
				if type(member) == "table" and member.userId == player.UserId then
					myReady = member.ready == true
				end
			end
		end

		local readyCount = if type(s.readyCount) == "number" then s.readyCount else 0
		local total = if type(s.total) == "number" then s.total else 0
		local counting = type(s.countdownEndsAt) == "number" and s.countdownEndsAt > 0
		if not myEligible then
			readyButton.Text = "ห้องเต็ม\nรอที่ว่าง"
			readyButton.BackgroundColor3 = GREY
		elseif myReady then
			readyButton.Text = "ยกเลิกพร้อม\n(" .. readyCount .. "/" .. total .. ")"
			readyButton.BackgroundColor3 = ORANGE
		else
			readyButton.Text = "พร้อม\n(" .. readyCount .. "/" .. total .. ")"
			readyButton.BackgroundColor3 = GREEN
		end

		if isLeader then
			hintLabel.Text = if counting
				then "กำลังนับถอยหลัง — กดยกเลิกพร้อมก่อนถ้าจะเปลี่ยนจุดลง"
				else "คุณคือหัวห้อง — แตะแผนที่เพื่อเลือกจุดลง"
		else
			local leaderPlayer =
				Players:GetPlayerByUserId(if type(s.leaderUserId) == "number" then s.leaderUserId else 0)
			local leaderName = if leaderPlayer ~= nil then leaderPlayer.DisplayName else "-"
			hintLabel.Text = "หัวห้องเลือกจุดลง (หัวห้อง: "
				.. leaderName
				.. ")"
		end

		mapView.setMarkers(s.markers)
		if type(s.landingX) == "number" and type(s.landingZ) == "number" then
			landingDot.Position = mapView.worldToMap(s.landingX, s.landingZ)
			landingDot.Visible = true
		else
			landingDot.Visible = false
		end
	end

	-- นับถอยหลังเริ่มภารกิจ (คิดจากเวลาเซิร์ฟเวอร์ที่ส่งมา · เขียนข้อความเมื่อเปลี่ยนเท่านั้น)
	local lastCountdownText = ""
	RunService.Heartbeat:Connect(function()
		local s = snapshot
		local text = ""
		if s ~= nil and lobbyRoot.Visible then
			local endsAt = s.countdownEndsAt
			if type(endsAt) == "number" and endsAt > 0 then
				local remaining = math.ceil(endsAt - Workspace:GetServerTimeNow())
				text = if remaining > 0 then "เริ่มใน " .. remaining else "ไปเลย!"
			end
		end
		if text ~= lastCountdownText then
			lastCountdownText = text
			countdownLabel.Text = text
		end
	end)

	missionState.OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" then
			applySnapshot(payload)
		end
	end)

	-- ปืนที่ถืออยู่ (เซิร์ฟเวอร์บอกผ่าน CombatState — Controls ฟังตัวเดียวกันด้วย)
	-- ต่อสายก่อนขอสถานะครั้งแรก เพราะเซิร์ฟเวอร์ส่งสถานะปืนซ้ำให้ตอนตอบ GetMissionState (กันพลาดอีเวนต์แรก)
	combatStateRemote.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		local newId: string? = if type(payload.gunId) == "string" then payload.gunId else nil
		if newId ~= equippedGunId then
			equippedGunId = newId
			refreshShop()
		end
	end)

	-- กันพลาดอีเวนต์ที่ยิงก่อน client พร้อม: ขอสถานะปัจจุบันครั้งแรก (ลองใหม่ได้ถ้าเซิร์ฟเวอร์ยังไม่พร้อม)
	task.spawn(function()
		for _ = 1, 5 do
			local ok, result = pcall(function()
				return getMissionState:InvokeServer()
			end)
			if snapshot ~= nil then
				return -- อีเวนต์มาถึงก่อนแล้ว ใหม่กว่าผลที่ขอ
			end
			if ok and type(result) == "table" then
				applySnapshot(result)
				return
			end
			task.wait(1)
		end
	end)

	refreshMoney()
	refreshShop()
	refreshSnacks()

	return {
		onData = function(payload: any)
			if type(payload) ~= "table" then
				return
			end
			if type(payload.money) == "number" then
				money = payload.money
			end
			if type(payload.snacks) == "number" then
				snacks = payload.snacks
			end
			if type(payload.ownedGuns) == "table" then
				local set: { [string]: boolean } = {}
				for _, id in payload.ownedGuns do
					if type(id) == "string" then
						set[id] = true
					end
				end
				owned = set
			end
			refreshMoney()
			refreshShop()
			refreshSnacks()
		end,
	}
end

return LobbyUi
