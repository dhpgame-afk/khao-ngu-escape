--!strict
-- Shop: ร้านปืน + แลกขนมเป็นเงิน — เซิร์ฟเวอร์ตรวจทุกอย่าง ไม่เชื่อค่าจาก client

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerData = require(script.Parent.PlayerData)
local Remotes = require(script.Parent.Remotes)
local Mission = require(script.Parent.Mission)

export type Result = { ok: boolean, message: string }

local Shop = {}

local lastRequestTime: { [Player]: number } = {}

local function fail(message: string): Result
	return { ok = false, message = message }
end

-- ซื้อ/แลกได้เฉพาะตอนภารกิจอยู่ในช่วงห้องรอ และผู้เล่นคนนี้อยู่ในห้องรอ (Mission ตัดสิน)
local function isInLobby(player: Player): boolean
	return Mission.isInLobby(player)
end

-- จำกัดความถี่ต่อผู้เล่น (ค่าอยู่ใน Config.Shop)
local function passRateLimit(player: Player): boolean
	local now = os.clock()
	local last = lastRequestTime[player]
	if last ~= nil and now - last < Config.Shop.RequestCooldownSeconds then
		return false
	end
	lastRequestTime[player] = now
	return true
end

-- ตรวจเงื่อนไขร่วมกันของทุกคำขอ
local function commonChecks(player: Player): Result?
	if not passRateLimit(player) then
		return fail("กดเร็วเกินไป รอสักครู่นะ")
	end
	if PlayerData.get(player) == nil then
		return fail(
			"ข้อมูลของคุณยังโหลดไม่เสร็จ รอสักครู่นะ"
		)
	end
	if not PlayerData.canTransact(player) then
		return fail(
			"ตอนนี้บันทึกข้อมูลไม่ได้ ยังซื้อหรือแลกไม่ได้"
		)
	end
	if not isInLobby(player) then
		return fail(
			"ซื้อหรือแลกได้เฉพาะตอนอยู่ในห้องรอ"
		)
	end
	return nil
end

function Shop.buyGun(player: Player, gunId: any): Result
	local blocked = commonChecks(player)
	if blocked ~= nil then
		return blocked
	end
	if type(gunId) ~= "string" then
		return fail("คำขอไม่ถูกต้อง")
	end
	local gun = Config.Guns[gunId]
	if gun == nil then
		return fail("ไม่มีปืนนี้ในร้าน")
	end
	if PlayerData.hasGun(player, gunId) then
		return fail("คุณมีปืนนี้แล้ว")
	end
	local data = PlayerData.get(player)
	if data == nil or data.money < gun.price then
		return fail("เงินไม่พอ")
	end
	-- ไม่มี yield ระหว่างตรวจกับหัก จึงไม่เกิดซื้อซ้อนกัน
	if gun.price > 0 and not PlayerData.spendMoney(player, gun.price) then
		return fail("เงินไม่พอ")
	end
	if not PlayerData.addGun(player, gunId) then
		return fail("ซื้อไม่สำเร็จ ลองใหม่อีกครั้ง")
	end
	return { ok = true, message = "ซื้อ " .. gun.displayName .. " สำเร็จ" }
end

function Shop.exchangeSnacks(player: Player, amount: any): Result
	local blocked = commonChecks(player)
	if blocked ~= nil then
		return blocked
	end
	if type(amount) ~= "number" or amount ~= amount or amount % 1 ~= 0 then
		return fail("จำนวนไม่ถูกต้อง")
	end
	local data = PlayerData.get(player)
	if data == nil or amount < 1 or amount > data.snacks then
		return fail("จำนวนขนมไม่ถูกต้อง")
	end
	if not PlayerData.removeSnacks(player, amount) then
		return fail("แลกไม่สำเร็จ ลองใหม่อีกครั้ง")
	end
	local gained = amount * Config.Snacks.ExchangeMoney
	PlayerData.addMoney(player, gained)
	return { ok = true, message = "แลกขนม " .. amount .. " ห่อ ได้เงิน " .. gained }
end

local function makeRemoteFunction(name: string, handler: (Player, any) -> Result)
	local remote = Remotes.remoteFunction(name)
	remote.OnServerInvoke = function(player: Player, arg: any)
		local success, result = pcall(handler, player, arg)
		if success then
			return result
		end
		warn("[Shop]", name, "error:", result)
		return fail("เกิดข้อผิดพลาด ลองใหม่อีกครั้ง")
	end
end

function Shop.init()
	-- Remotes ใช้โฟลเดอร์ที่ Rojo ประกาศไว้ (ไม่มีก็สร้างตอนรัน)
	makeRemoteFunction("BuyGun", Shop.buyGun)
	makeRemoteFunction("ExchangeSnacks", Shop.exchangeSnacks)

	Players.PlayerRemoving:Connect(function(player)
		lastRequestTime[player] = nil
	end)
end

return Shop
