--!strict
-- จุดเริ่มต้นฝั่งเซิร์ฟเวอร์: เปิดระบบข้อมูลผู้เล่นก่อน แล้วค่อยเปิดร้านค้า

local PlayerData = require(script.PlayerData)
local Shop = require(script.Shop)

PlayerData.init()
Shop.init()
