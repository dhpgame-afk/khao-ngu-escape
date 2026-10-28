--!strict
-- ResultsUi: หน้าสรุปจบภารกิจ (มือถือเป็นหลัก — Scale ทั้งหมด + UIAspectRatioConstraint · ข้อความไทย)
-- - client "โง่": วาดตามข้อมูลที่เซิร์ฟเวอร์ส่งมาใน MissionState.results ตอนช่วง Results เท่านั้น (เงินคิดและจ่ายที่เซิร์ฟเวอร์แล้ว)
-- - แถวละ 1 คน: ชื่อ · ฆ่าลิง · เรียกเพื่อน · เงินที่ได้ · ขนม · สถานะ (ขึ้นบั้งไฟ / ถูกทิ้ง)
-- - ปุ่ม "ปิด" แค่ปิดหน้านี้ (เซิร์ฟเวอร์พากลับห้องรอเองเมื่อครบเวลา)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Hud = require(script.Parent.Hud)

local DARK = Color3.fromRGB(25, 28, 33)
local ROW_COLOR = Color3.fromRGB(48, 54, 62)
local ROW_SELF_COLOR = Color3.fromRGB(70, 82, 104)
local GREEN = Color3.fromRGB(110, 230, 120)
local RED = Color3.fromRGB(255, 110, 100)
local ORANGE = Color3.fromRGB(255, 180, 70)
local YELLOW = Color3.fromRGB(255, 235, 150)
local GOLD = Color3.fromRGB(255, 205, 70)

local PANEL_ASPECT = 1.8 -- กว้าง ÷ สูง ของกล่องสรุป
local TITLE_Y, TITLE_H = 0.03, 0.12
local SUBTITLE_Y, SUBTITLE_H = 0.15, 0.08
local HEADER_Y, HEADER_H = 0.25, 0.06
local ROWS_Y, ROW_H, ROW_GAP = 0.32, 0.115, 0.01
local FOOTER_Y, FOOTER_H = 0.85, 0.12

-- คอลัมน์ (เริ่ม, กว้าง) เป็นสัดส่วนความกว้างแถว
local COLUMNS = {
	name = { 0.02, 0.28 },
	kills = { 0.30, 0.13 },
	calls = { 0.43, 0.14 },
	money = { 0.57, 0.17 },
	snacks = { 0.74, 0.11 },
	status = { 0.85, 0.14 },
}
local COLUMN_ORDER = { "name", "kills", "calls", "money", "snacks", "status" }
local HEADER_TEXT = {
	name = "ผู้เล่น",
	kills = "ฆ่าลิง",
	calls = "เรียกเพื่อน",
	money = "เงินที่ได้",
	snacks = "ขนม",
	status = "สถานะ",
}

export type Api = {
	onSnapshot: (snapshot: { [string]: any }) -> (),
}

local ResultsUi = {}

local function addCorner(inst: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = inst
end

local function makeCell(parent: Instance, column: string, text: string, y: number, h: number): TextLabel
	local span = COLUMNS[column]
	local label = Hud.makeLabel(parent, column, text, UDim2.fromScale(span[1], y), UDim2.fromScale(span[2], h))
	label.TextXAlignment = if column == "name" then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	return label
end

function ResultsUi.start(): Api
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Results"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- เลี่ยงรอยบาก/ขอบจอ
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 4 -- เหนือหน้าเล็งหนังสติ๊ก (3)
	gui.Enabled = false
	gui.Parent = playerGui

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Active = true -- กันนิ้วทะลุไปโดนปุ่มยิงด้านล่าง
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.94, 0.9)
	panel.BackgroundColor3 = DARK
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Parent = backdrop
	addCorner(panel, 0.04)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = PANEL_ASPECT
	ratio.Parent = panel

	local titleLabel = Hud.makeLabel(panel, "Title", "", UDim2.fromScale(0.04, TITLE_Y), UDim2.fromScale(0.92, TITLE_H))
	local subtitleLabel =
		Hud.makeLabel(panel, "Subtitle", "", UDim2.fromScale(0.04, SUBTITLE_Y), UDim2.fromScale(0.92, SUBTITLE_H))
	subtitleLabel.TextColor3 = YELLOW

	for _, column in COLUMN_ORDER do
		local cell = makeCell(panel, column, HEADER_TEXT[column], HEADER_Y, HEADER_H)
		cell.TextColor3 = Color3.fromRGB(190, 200, 215)
	end

	-- แถวผู้เล่น: สร้างไว้ล่วงหน้าตามจำนวนผู้เล่นสูงสุด (ใช้ซ้ำ ไม่สร้างใหม่ทุกครั้ง)
	type RowRefs = { frame: Frame, cells: { [string]: TextLabel } }
	local rows: { RowRefs } = {}
	for i = 1, Config.MaxPlayers do
		local frame = Instance.new("Frame")
		frame.Name = "Row" .. i
		frame.Position = UDim2.fromScale(0.02, ROWS_Y + (i - 1) * (ROW_H + ROW_GAP))
		frame.Size = UDim2.fromScale(0.96, ROW_H)
		frame.BackgroundColor3 = ROW_COLOR
		frame.BackgroundTransparency = 0.2
		frame.BorderSizePixel = 0
		frame.Visible = false
		frame.Parent = panel
		addCorner(frame, 0.2)
		local cells: { [string]: TextLabel } = {}
		for _, column in COLUMN_ORDER do
			cells[column] = makeCell(frame, column, "", 0.1, 0.8)
		end
		table.insert(rows, { frame = frame, cells = cells })
	end

	local countdownLabel =
		Hud.makeLabel(panel, "Countdown", "", UDim2.fromScale(0.04, FOOTER_Y), UDim2.fromScale(0.5, FOOTER_H))
	countdownLabel.TextXAlignment = Enum.TextXAlignment.Left
	countdownLabel.TextColor3 = YELLOW

	local backButton =
		Hud.makeButton(panel, "Back", "ปิด", Vector2.new(0.84, FOOTER_Y + FOOTER_H / 2), 0.17, false)
	backButton.Size = UDim2.fromScale(0.26, FOOTER_H)
	backButton.BackgroundColor3 = Color3.fromRGB(60, 160, 90)
	backButton.BackgroundTransparency = 0

	-- ===== สถานะ =====
	local endsAt = 0 -- เวลาเซิร์ฟเวอร์ที่จะกลับห้องรอ
	local shownKey = 0 -- endsAt ของหน้าสรุปที่แสดงอยู่ (กันโผล่ซ้ำหลังกดปิด)
	local dismissedKey = 0
	local lastCountdown = -1

	local function hide()
		gui.Enabled = false
	end

	backButton.Activated:Connect(function()
		dismissedKey = shownKey
		hide()
	end)

	RunService.RenderStepped:Connect(function()
		if not gui.Enabled then
			return
		end
		local remaining = math.max(0, math.ceil(endsAt - Workspace:GetServerTimeNow()))
		if remaining ~= lastCountdown then
			lastCountdown = remaining
			countdownLabel.Text = "กลับห้องรอใน " .. remaining .. " วิ"
		end
	end)

	local function number(value: any): number
		return if type(value) == "number" and value == value then value else 0
	end

	local function render(results: { [string]: any })
		local success = results.success == true
		titleLabel.Text = if type(results.title) == "string" then results.title else ""
		titleLabel.TextColor3 = if success then GOLD else RED
		subtitleLabel.Text = if type(results.subtitle) == "string" then results.subtitle else ""

		local list = if type(results.rows) == "table" then results.rows else {}
		for i, row in rows do
			local data = list[i]
			if type(data) ~= "table" then
				row.frame.Visible = false
			else
				row.frame.Visible = true
				local isSelf = data.userId == player.UserId
				row.frame.BackgroundColor3 = if isSelf then ROW_SELF_COLOR else ROW_COLOR
				row.cells.name.Text = if type(data.name) == "string" then data.name else "-"
				row.cells.kills.Text = tostring(number(data.kills))
				row.cells.calls.Text = tostring(number(data.calls))
				row.cells.money.Text = "+" .. number(data.money)
				local snacks = number(data.snacks)
				row.cells.snacks.Text = if snacks > 0 then "+" .. snacks else "-"
				local boarded = data.status == "Rocket"
				row.cells.status.Text = if boarded then "ขึ้นบั้งไฟ" else "ถูกทิ้ง"
				row.cells.status.TextColor3 = if boarded then GREEN else ORANGE
			end
		end
	end

	return {
		onSnapshot = function(snapshot: { [string]: any })
			local results = snapshot.results
			if snapshot.phase ~= "Results" or snapshot.inLobby == true or type(results) ~= "table" then
				hide()
				return
			end
			local key = number(results.endsAt)
			endsAt = key
			if key ~= shownKey then
				shownKey = key
				lastCountdown = -1
			end
			render(results)
			-- กดปิดแล้วไม่โผล่อีกในรอบนี้ (snapshot ส่งซ้ำได้เมื่อมีคนเข้า/ออก)
			gui.Enabled = key ~= dismissedKey
		end,
	}
end

return ResultsUi
