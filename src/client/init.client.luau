--!strict
-- จุดเริ่มต้นฝั่ง client: สร้าง HUD แล้วต่อปุ่มเข้ากับระบบต่อสู้ + หน้าจอห้องรอ
-- เงิน/ปืนของผู้เล่นส่งมาเฉพาะเจ้าตัวผ่าน DataChanged / GetMyData (ไม่ใช้ Attribute)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hud = require(script.Hud)
local Controls = require(script.Controls)
local LobbyUi = require(script.LobbyUi)
local MissionHud = require(script.MissionHud)
local RescueUi = require(script.RescueUi)
local NavMap = require(script.NavMap)
local ResultsUi = require(script.ResultsUi)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local dataChanged = remotes:WaitForChild("DataChanged") :: RemoteEvent
local getMyData = remotes:WaitForChild("GetMyData") :: RemoteFunction

local hud = Hud.create()
local missionHud = MissionHud.start(hud)
local controls = Controls.start(hud, missionHud)
local rescueUi = RescueUi.start()
local navMap = NavMap.start(rescueUi)
local resultsUi = ResultsUi.start()
-- สถานะภารกิจจากเซิร์ฟเวอร์ (MissionState) ส่งต่อให้ HUD ภารกิจ แผนที่เล็งหนังสติ๊ก และแผนที่นำทาง
local lobbyUi = LobbyUi.start(hud, function(snapshot: { [string]: any })
	missionHud.onSnapshot(snapshot)
	rescueUi.onSnapshot(snapshot)
	navMap.onSnapshot(snapshot)
	resultsUi.onSnapshot(snapshot) -- หน้าสรุปจบภารกิจ (ช่วง Results)
end)

local function onData(payload: any)
	-- ข้อความเตือนระบบบันทึก (โหลด/บันทึกไม่ได้) → แถบเตือนค้างบนจอเสมอ ทั้งห้องรอและตอนเล่น
	if type(payload) == "table" and type(payload.message) == "string" then
		Hud.showDataWarning(payload.message)
	end
	controls.onData(payload)
	lobbyUi.onData(payload)
	missionHud.onData(payload)
end

dataChanged.OnClientEvent:Connect(onData)

-- ขอข้อมูลตอนเริ่ม: ครอบ pcall (InvokeServer พังได้ถ้าเซิร์ฟเวอร์ไม่ตอบ) และลองใหม่ — เซิร์ฟเวอร์ตอบ nil ถ้าข้อมูลยังโหลดไม่เสร็จ/ถามถี่เกิน
-- ถ้ายังไม่ได้ก็ไม่เป็นไร: เซิร์ฟเวอร์จะส่ง DataChanged มาเองเมื่อโหลดเสร็จ
local GET_DATA_ATTEMPTS = 8
local GET_DATA_RETRY_SECONDS = 1
for attempt = 1, GET_DATA_ATTEMPTS do
	local ok, result = pcall(function()
		return getMyData:InvokeServer()
	end)
	if ok and result ~= nil then
		onData(result)
		break
	end
	if attempt < GET_DATA_ATTEMPTS then
		task.wait(GET_DATA_RETRY_SECONDS)
	end
end
