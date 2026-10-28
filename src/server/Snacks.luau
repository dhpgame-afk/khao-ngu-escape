--!strict
-- Snacks: กินขนมพระระหว่างภารกิจ → เลือดชั่วคราว +250 นาน 10 วิ (ตัวเลขใน Config.Snacks)
-- ลำดับแหล่งขนม: (ก) ห่อที่ถืออยู่ในมือ (SnackPack) ก่อน · (ข) ขนมที่เซฟไว้ในตัว (PlayerData.snacks = "พกเข้าภารกิจ")
-- เซิร์ฟเวอร์ตรวจทุกอย่าง: ช่วงภารกิจ · สถานะปกติ · ความถี่ · จำนวนขนม — client ส่งแค่เจตนา "EatSnack"
-- (ขนมที่เหลือตอนขึ้นบั้งไฟ แบ่งให้คนบนบั้งไฟ — Settlement.luau จัดการ)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local RateLimit = require(script.Parent.RateLimit)
local PlayerData = require(script.Parent.PlayerData)
local PlayerHealth = require(script.Parent.PlayerHealth)
local Carry = require(script.Parent.Carry)

local Snacks = {}

-- Mission ตั้งให้ผ่าน init: กินได้เฉพาะช่วง InMission และเป็นผู้ร่วมภารกิจ
local canUse: (Player) -> boolean = function(_player: Player): boolean
	return false
end

local function onEat(player: Player)
	if not RateLimit.allow(player, "EatSnack", Config.Snacks.EatMinIntervalSeconds) then
		return
	end
	if not canUse(player) or PlayerHealth.getState(player) ~= "Alive" then
		return
	end
	-- ไม่มี yield ระหว่างตรวจกับหักขนม จึงไม่เกิดกินซ้อน
	if Carry.consumeHeldSnack(player) then
		PlayerHealth.grantTempHealth(player)
		return
	end
	local data = PlayerData.get(player)
	if data == nil or data.snacks < 1 then
		return
	end
	if PlayerData.removeSnacks(player, 1) then -- หักแล้วเซฟตามระบบ PlayerData (markChanged)
		PlayerHealth.grantTempHealth(player)
	end
end

function Snacks.init(canUseFn: (Player) -> boolean)
	canUse = canUseFn
	Remotes.remoteEvent("EatSnack").OnServerEvent:Connect(onEat) -- ()
end

return Snacks
