--!strict
-- Settlement: คิดและจ่ายรางวัลตอนบั้งไฟขึ้น (ฝั่งเซิร์ฟเวอร์ล้วน — client ไม่มีส่วนตัดสิน) แล้วคืนข้อมูลหน้าสรุปผล
-- กติกา (ตัวเลขทั้งหมดอยู่ Config.Rewards / Config.Rocket / Config.Snacks):
--   1) ไม่มีใครขึ้นบั้งไฟ → ภารกิจล้มเหลว ได้ 0 ทุกคน (รวมเงินจากฆ่าลิงที่สะสมรอจ่าย = 0)
--   1.1) เงินจากฆ่าลิง "จ่ายที่นี่ตอนจบภารกิจ" (Monkeys สะสมไว้ ไม่จ่ายสด) · ไม่โดนตัวคูณขาดถุงเงิน/ขนม
--        คนถูกทิ้งโดน ×LeftBehindMultiplier ทั้งก้อน (รางวัลภารกิจ + เงินจากลิง) · คนออกก่อนจบ = ไม่ได้
--   2) รางวัลเต็ม = MissionComplete × (ตัวคูณขาดของ) · ถุงเงินหรือขนมไม่ได้อยู่กับคนที่มัดตัวบนบั้งไฟ = ขาดของ
--      ขาดอย่างใดอย่างหนึ่งหรือทั้งคู่ คูณ MissingItemsMultiplier ครั้งเดียว (ถ้า StackMissingItemPenalty = true คูณซ้อนต่อชิ้น)
--   3) คนมัดตัวได้รางวัลเต็ม · คนถูกทิ้งได้ × LeftBehindMultiplier (0.95)
--   4) ขนมที่เหลือในห่อ (ถ้าผู้ถือมัดตัวบนบั้งไฟ) แบ่งเท่า ๆ กันในหมู่คนมัดตัว เศษให้ผู้ถือห่อ · ห่อไม่อยู่บนบั้งไฟ = ขนมหายหมด
--      ขนมเก็บได้สูงสุด 15/คน — ส่วนเกินแปลงเป็นเงินห่อละ 25 (PlayerData.addSnacks จัดการ)
--   5) คนมัดตัวนับ stats.missionsCompleted +1 เมื่อภารกิจสำเร็จ
-- เรียกครั้งเดียวต่อภารกิจ (Mission คุมไม่ให้จ่ายซ้ำ)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerData = require(script.Parent.PlayerData)
local Monkeys = require(script.Parent.Monkeys)

export type Row = {
	userId: number,
	name: string,
	kills: number, -- ลิงที่ฆ่ารอบนี้
	calls: number, -- เพื่อนที่โทรเรียกกลับรอบนี้
	money: number, -- เงินที่ได้รอบนี้ทั้งหมด (เงินจากลิง + รางวัลภารกิจ + เงินจากขนมส่วนเกิน)
	killMoney: number, -- ส่วนของเงินจากฆ่าลิง (รวมอยู่ใน money แล้ว · โชว์แยกบรรทัดในหน้าสรุป)
	snacks: number, -- ขนมที่ได้จากการแบ่งบนบั้งไฟ (ห่อ)
	status: string, -- "Rocket" = ขึ้นบั้งไฟ · "Left" = ถูกทิ้ง
}

export type Result = {
	success: boolean,
	title: string,
	subtitle: string,
	rows: { Row },
}

export type Input = {
	participants: { Player }, -- ผู้ร่วมภารกิจที่ยังอยู่ในเกม
	tied: { [Player]: boolean }, -- คนที่มัดตัวบนบั้งไฟตอนนับครบ
	moneyBagHolder: Player?, -- ผู้ถือถุงเงินตอนนับครบ (nil = ไม่มี/อยู่บนพื้น)
	snackHolder: Player?,
	snackCount: number, -- ห่อที่เหลือในมือผู้ถือ
	callsMade: (Player) -> number,
}

local PAYMENT_FAILED_MESSAGE = "รอบนี้ยังไม่ได้รับรางวัล"

local Settlement = {}

local function roundMoney(value: number): number
	return math.max(0, math.floor(value + 0.5))
end

-- รางวัลเต็มของคนที่ขึ้นบั้งไฟ (ก่อนหักส่วนคนถูกทิ้ง)
function Settlement.fullReward(moneyOnBoard: boolean, snackOnBoard: boolean): number
	local multiplier = 1
	local missingCount = (if moneyOnBoard then 0 else 1) + (if snackOnBoard then 0 else 1)
	if Config.Rewards.StackMissingItemPenalty then
		multiplier = Config.Rewards.MissingItemsMultiplier ^ missingCount
	elseif missingCount > 0 then
		multiplier = Config.Rewards.MissingItemsMultiplier
	end
	return roundMoney(Config.Rewards.MissionComplete * multiplier)
end

local function subtitleOf(success: boolean, moneyOnBoard: boolean, snackOnBoard: boolean): string
	if not success then
		return "ภารกิจล้มเหลว — ไม่ได้รับเงินรางวัลและเงินจากลิง"
	end
	if moneyOnBoard and snackOnBoard then
		return "ถุงเงินและขนมขึ้นบั้งไฟครบ — รับรางวัลเต็ม"
	end
	if not moneyOnBoard and not snackOnBoard then
		return "ถุงเงินและขนมไม่ได้ขึ้นบั้งไฟ — รางวัลลดลง"
	end
	if not moneyOnBoard then
		return "ถุงเงินไม่ได้ขึ้นบั้งไฟ — รางวัลลดลง"
	end
	return "ขนมไม่ได้ขึ้นบั้งไฟ — รางวัลลดลง"
end

function Settlement.run(input: Input): Result
	local boarders: { Player } = {}
	for _, player in input.participants do
		if player.Parent == Players and input.tied[player] then
			table.insert(boarders, player)
		end
	end
	local success = #boarders > 0

	local moneyHolder = input.moneyBagHolder
	local snackHolder = input.snackHolder
	local moneyOnBoard = moneyHolder ~= nil and input.tied[moneyHolder] == true
	local snackOnBoard = snackHolder ~= nil and input.tied[snackHolder] == true

	local fullReward = if success then Settlement.fullReward(moneyOnBoard, snackOnBoard) else 0
	local leftBehindReward = roundMoney(fullReward * Config.Rocket.LeftBehindMultiplier)

	-- แบ่งขนม: เท่า ๆ กันในหมู่คนมัดตัว เศษให้ผู้ถือห่อ
	local snackShare: { [Player]: number } = {}
	if success and snackOnBoard and snackHolder ~= nil and input.snackCount > 0 then
		local each = input.snackCount // #boarders
		local remainder = input.snackCount - each * #boarders
		for _, player in boarders do
			snackShare[player] = each
		end
		snackShare[snackHolder] = (snackShare[snackHolder] or 0) + remainder
	end

	local rows: { Row } = {}
	for _, player in input.participants do
		if player.Parent == Players then
			local boarded = input.tied[player] == true
			local snacks = snackShare[player] or 0
			-- เงินจากลิงที่สะสมรอจ่าย: ภารกิจล้มเหลว = 0 · ไม่โดนตัวคูณขาดของ · คนถูกทิ้งคูณ LeftBehindMultiplier
			local pendingKill = if success then Monkeys.getMissionKillMoney(player) else 0
			local killPay = if boarded
				then pendingKill
				else roundMoney(pendingKill * Config.Rocket.LeftBehindMultiplier)
			local reward = if boarded then fullReward else leftBehindReward
			local moneyEarned = 0

			-- จ่ายก้อนเดียว (รางวัลภารกิจ + เงินจากลิง) ครั้งเดียวต่อคน · เซฟไม่ได้ = ไม่ได้เงินและไม่โชว์ว่าได้
			local payout = reward + killPay
			local killShown = 0
			local paymentFailed = false
			if payout > 0 then
				if PlayerData.addMoney(player, payout) then
					moneyEarned += payout
					killShown = killPay
					Monkeys.clearMissionKillMoney(player)
				else
					paymentFailed = true
				end
			end
			if snacks > 0 then
				local stored, overflowMoney = PlayerData.addSnacks(player, snacks)
				moneyEarned += overflowMoney
				if stored == 0 and overflowMoney == 0 then
					paymentFailed = true -- addSnacks คืน 0,0 = เพิ่มไม่ได้ (ไม่ใช่ขนมเต็มเฉย ๆ เพราะส่วนเกินจะกลายเป็นเงิน)
				end
			end
			if paymentFailed then
				PlayerData.notifyPaymentFailed(player, PAYMENT_FAILED_MESSAGE) -- คนกำลังออกเกม PlayerData ข้ามให้เอง
			elseif payout > 0 or snacks > 0 then
				PlayerData.clearPaymentFailed(player) -- จ่ายสำเร็จรอบนี้ ล้างข้อความค้างจากรอบก่อน
			end
			if success and boarded then
				PlayerData.addStat(player, "missionsCompleted", 1)
			end

			table.insert(rows, {
				userId = player.UserId,
				name = player.DisplayName,
				kills = Monkeys.getMissionKills(player),
				calls = input.callsMade(player),
				money = moneyEarned,
				killMoney = killShown,
				snacks = snacks,
				status = if boarded then "Rocket" else "Left",
			})
		end
	end

	return {
		success = success,
		title = if success then "ภารกิจสำเร็จ!" else "ภารกิจล้มเหลว",
		subtitle = subtitleOf(success, moneyOnBoard, snackOnBoard),
		rows = rows,
	}
end

return Settlement
