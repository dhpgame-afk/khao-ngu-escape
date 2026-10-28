--!strict
-- จุดเริ่มต้นฝั่ง client: สร้าง HUD แล้วต่อปุ่มเข้ากับระบบต่อสู้ + หน้าจอห้องรอ
-- เงิน/ปืนของผู้เล่นส่งมาเฉพาะเจ้าตัวผ่าน DataChanged / GetMyData (ไม่ใช้ Attribute)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hud = require(script.Hud)
local Controls = require(script.Controls)
local LobbyUi = require(script.LobbyUi)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local dataChanged = remotes:WaitForChild("DataChanged") :: RemoteEvent
local getMyData = remotes:WaitForChild("GetMyData") :: RemoteFunction

local hud = Hud.create()
local controls = Controls.start(hud)
local lobbyUi = LobbyUi.start(hud)

local function onData(payload: any)
	controls.onData(payload)
	lobbyUi.onData(payload)
end

dataChanged.OnClientEvent:Connect(onData)
onData(getMyData:InvokeServer())
