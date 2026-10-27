--!strict
-- จุดเริ่มต้นฝั่ง client: สร้าง HUD แล้วต่อปุ่มเข้ากับระบบต่อสู้
-- เงิน/ปืนของผู้เล่นส่งมาเฉพาะเจ้าตัวผ่าน DataChanged / GetMyData (ไม่ใช้ Attribute)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hud = require(script.Hud)
local Controls = require(script.Controls)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local dataChanged = remotes:WaitForChild("DataChanged") :: RemoteEvent
local getMyData = remotes:WaitForChild("GetMyData") :: RemoteFunction

local hud = Hud.create()
local controls = Controls.start(hud)

dataChanged.OnClientEvent:Connect(controls.onData)
controls.onData(getMyData:InvokeServer())
