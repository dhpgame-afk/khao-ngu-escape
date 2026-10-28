--!strict
-- จุดเริ่มต้นฝั่งเซิร์ฟเวอร์: เปิดระบบข้อมูลผู้เล่นก่อน แล้วค่อยเปิดร้านค้า ห้องรอ และระบบต่อสู้

local PlayerData = require(script.PlayerData)
local Shop = require(script.Shop)
local Mission = require(script.Mission)
local PlayerHealth = require(script.PlayerHealth)
local Combat = require(script.Combat)

PlayerData.init()
Shop.init()
-- Mission ต้องเปิดก่อน PlayerHealth: สร้างห้องรอและผูกจุดเกิดก่อนที่ตัวละครตัวแรกจะถูกสร้าง (PlayerHealth เป็นคนเรียก LoadCharacter)
Mission.init()
PlayerHealth.init()
Combat.init()

-- ระบบลิงและรังลิง
local Monkeys = require(script.Monkeys)
Monkeys.start()
