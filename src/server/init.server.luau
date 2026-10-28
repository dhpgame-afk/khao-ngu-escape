--!strict
-- จุดเริ่มต้นฝั่งเซิร์ฟเวอร์: เปิดระบบข้อมูลผู้เล่นก่อน แล้วค่อยเปิดร้านค้า ห้องรอ และระบบต่อสู้

-- MapSetup ต้องมาก่อนทุกอย่าง: สร้างจุดสำคัญ (MapMarkers) + กุฏิ ที่ Mission / Monkeys อ่านตอนเริ่ม
local MapSetup = require(script.MapSetup)
local Monk = require(script.Monk)
MapSetup.run()
Monk.ensure() -- พระยืนหน้ากุฏิตั้งแต่เริ่มเซิร์ฟเวอร์ (ไม่รอยิงหนังสติ๊ก)

local PlayerData = require(script.PlayerData)
local Shop = require(script.Shop)
local Mission = require(script.Mission)
local PlayerHealth = require(script.PlayerHealth)
local Combat = require(script.Combat)
local Carry = require(script.Carry)
local Snacks = require(script.Snacks)

PlayerData.init()
Shop.init()
-- Mission ต้องเปิดก่อน PlayerHealth: สร้างห้องรอและผูกจุดเกิดก่อนที่ตัวละครตัวแรกจะถูกสร้าง (PlayerHealth เป็นคนเรียก LoadCharacter)
Mission.init()
PlayerHealth.init()
Combat.init()
-- ถือของ + กินขนม: ใช้ได้เฉพาะช่วงภารกิจ (InMission) และเป็นผู้ร่วมภารกิจ — Mission เป็นคนตัดสิน
Carry.init(Mission.canInteract, Mission.getSafeSpot)
Snacks.init(Mission.canInteract)

-- ระบบลิงและรังลิง
local Monkeys = require(script.Monkeys)
Monkeys.start()
