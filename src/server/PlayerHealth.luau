--!strict
-- PlayerHealth: เลือดและสถานะของผู้เล่น (ปกติ / ล้ม / ตาย) — เซิร์ฟเวอร์เป็นคนเปลี่ยนเท่านั้น
-- สถานะส่งให้ทุก client ผ่าน Attribute บน Character: State, StateEndsAt (เวลาเซิร์ฟเวอร์), ReviveProgress (0–1),
-- DownedHealth (เลือดตอนล้ม · 0 เมื่อไม่ได้ล้ม)
-- (ไม่ใช่ข้อมูลลับ — ใช้วาด UI นับถอยหลัง/แถบชุบ)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local RateLimit = require(script.Parent.RateLimit)

local PCfg = Config.Player
local TICK_SECONDS = 0.2

export type State = "Alive" | "Downed" | "Dead"

type Info = {
	state: State,
	character: Model,
	humanoid: Humanoid,
	lastHitClock: number, -- os.clock ตอนโดนครั้งล่าสุด (ไว้หน่วงการฟื้นเลือด)
	downedEndsAt: number, -- os.clock ที่ล้มแล้วจะกลายเป็นตาย
	downedHealth: number, -- "เลือดตอนล้ม" ลิงตีลดได้ (หมด = ตายทันที) · 0 เมื่อไม่ได้ล้ม
	jumpHeight: number, -- เก็บค่าตอนเกิดไว้คืนให้ตอนชุบ
	jumpPower: number,
}

type ReviveJob = {
	target: Player,
	startedAt: number,
}

local PlayerHealth = {}

local infos: { [Player]: Info } = {}
local revives: { [Player]: ReviveJob } = {} -- key = คนที่กำลังชุบ

-- ===== ตัวช่วย =====

local function publish(info: Info, endsAtServerTime: number)
	info.character:SetAttribute("State", info.state)
	info.character:SetAttribute("StateEndsAt", endsAtServerTime)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function isFiniteNumber(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function setTargetProgress(target: Player, value: number)
	local info = infos[target]
	if info ~= nil then
		info.character:SetAttribute("ReviveProgress", value)
	end
end

-- ยกเลิกงานชุบที่เกี่ยวกับผู้เล่นคนนี้ (เป็นคนชุบ หรือเป็นคนถูกชุบ)
local function cancelRevivesInvolving(player: Player)
	for reviver, job in revives do
		if reviver == player or job.target == player then
			revives[reviver] = nil
			setTargetProgress(job.target, 0)
		end
	end
end

-- ===== เปลี่ยนสถานะ =====

-- TODO(ชุดถัดไป): แทนด้วยระบบกลับเข้าแมพ (เพื่อนโทรเรียก 5 วิ / ครบ 40 วิ ไปหนังสติ๊กเลือกเป้ายิงตัว)
-- ตอนนี้แค่เกิดใหม่หลังครบ RespawnSeconds
function PlayerHealth.respawnAfterDeath(player: Player)
	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	if not ok then
		warn("[PlayerHealth] เกิดใหม่ไม่สำเร็จ", player.Name, err)
	end
end


local function setDead(player: Player, info: Info)
	if info.state == "Dead" then
		return
	end
	info.state = "Dead"
	info.downedHealth = 0
	info.character:SetAttribute("DownedHealth", 0)
	cancelRevivesInvolving(player)
	publish(info, Workspace:GetServerTimeNow() + PCfg.RespawnSeconds)
	info.humanoid.Health = 0 -- ตั้งสถานะก่อน เพื่อให้ Died ที่ตามมาไม่ทำซ้ำ

	local character = info.character
	task.delay(PCfg.RespawnSeconds, function()
		if player.Parent == Players and player.Character == character then
			PlayerHealth.respawnAfterDeath(player)
		end
	end)
end

local function setDowned(player: Player, info: Info)
	if info.state ~= "Alive" then
		return
	end
	info.state = "Downed"
	info.downedEndsAt = os.clock() + PCfg.DownedSeconds
	info.downedHealth = PCfg.DownedHealth
	info.character:SetAttribute("DownedHealth", info.downedHealth)
	info.humanoid.Health = 1 -- ค้างไว้ที่ 1 (ไม่ให้ Humanoid ตายเอง)
	info.humanoid.WalkSpeed = PCfg.DownedWalkSpeed
	info.humanoid.JumpHeight = 0
	info.humanoid.JumpPower = 0
	publish(info, Workspace:GetServerTimeNow() + PCfg.DownedSeconds)
	-- TODO(ชุดถัดไป): ท่าคลาน/ปล่อยของที่ถืออยู่เมื่อล้ม
	-- (ถ้าคนนี้กำลังชุบคนอื่นอยู่ ต้องเลิก)
	local job = revives[player]
	if job ~= nil then
		revives[player] = nil
		setTargetProgress(job.target, 0)
	end
end

local function setAlive(info: Info, health: number)
	info.state = "Alive"
	info.downedHealth = 0
	info.character:SetAttribute("DownedHealth", 0)
	info.humanoid.Health = health
	info.humanoid.WalkSpeed = PCfg.WalkSpeed
	info.humanoid.JumpHeight = info.jumpHeight
	info.humanoid.JumpPower = info.jumpPower
	info.lastHitClock = os.clock()
	info.character:SetAttribute("ReviveProgress", 0)
	publish(info, 0)
end

-- ===== API ที่ระบบอื่นเรียก =====

function PlayerHealth.getState(player: Player): State
	local info = infos[player]
	if info == nil then
		return "Dead" -- ยังไม่มีตัวละคร = ถือว่าลงสนามไม่ได้
	end
	return info.state
end

local function applyDamage(player: Player, amount: number, killsOutright: boolean)
	local info = infos[player]
	if info == nil or info.state ~= "Alive" then
		return -- ล้ม/ตายแล้ว: ไม่รับดาเมจเพิ่ม (นับถอยหลังเดิมเดินต่อ)
	end
	if not isFiniteNumber(amount) or amount <= 0 then
		return
	end
	info.lastHitClock = os.clock()
	local remaining = info.humanoid.Health - amount
	if remaining > 0 then
		info.humanoid.Health = remaining
	elseif killsOutright then
		setDead(player, info)
	else
		setDowned(player, info)
	end
end

-- ลิงตีจน HP หมด → ตายทันที
-- ถ้าเป้าล้มอยู่: ตีได้ แต่ลดเลือดตอนล้มแค่ amount × DownedDamageMultiplier · หมด → ตายทันที
function PlayerHealth.damageFromMonkey(player: Player, amount: number)
	local info = infos[player]
	if info ~= nil and info.state == "Downed" then
		if not isFiniteNumber(amount) or amount <= 0 then
			return
		end
		info.downedHealth -= amount * Config.Monkey.DownedDamageMultiplier
		if info.downedHealth <= 0 then
			setDead(player, info)
		else
			info.character:SetAttribute("DownedHealth", info.downedHealth)
		end
		return
	end
	applyDamage(player, amount, true)
end

-- เพื่อนทำร้าย (ปืน/ประทัด/ไม้กวด) จน HP หมด → ล้ม
-- (ประทัดที่ขว้างเองโดนตัวเองได้ → victim == attacker ก็ล้มแบบเดียวกัน · ผู้เรียกเป็นคนเลือกว่าอาวุธไหนโดนตัวเองได้)
function PlayerHealth.damageFromPlayer(victim: Player, amount: number, attacker: Player)
	applyDamage(victim, amount, false)
end

-- ===== ชุบ =====

local function startRevive(reviver: Player, targetUserId: number)
	local reviverInfo = infos[reviver]
	if reviverInfo == nil or reviverInfo.state ~= "Alive" then
		return
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if target == nil or target == reviver then
		return
	end
	local targetInfo = infos[target]
	if targetInfo == nil or targetInfo.state ~= "Downed" then
		return
	end
	-- มีคนชุบอยู่แล้ว (คนอื่น) → ไม่ให้ซ้อน
	for otherReviver, job in revives do
		if job.target == target and otherReviver ~= reviver then
			return
		end
	end
	local a, b = rootOf(reviver), rootOf(target)
	if a == nil or b == nil or (a.Position - b.Position).Magnitude > PCfg.ReviveRange + 1 then
		return
	end
	local existing = revives[reviver]
	if existing ~= nil and existing.target == target then
		return -- กดซ้ำเป้าเดิม ไม่รีเซ็ตเวลา
	end
	if existing ~= nil then
		setTargetProgress(existing.target, 0)
	end
	revives[reviver] = { target = target, startedAt = os.clock() }
end

local function stopRevive(reviver: Player)
	local job = revives[reviver]
	if job ~= nil then
		revives[reviver] = nil
		setTargetProgress(job.target, 0)
	end
end

-- ตรวจงานชุบทุกรอบ: ระยะ/สถานะต้องยังถูกต้องตลอดเวลาที่กดค้าง
local function tickRevives(now: number)
	for reviver, job in revives do
		local reviverInfo = infos[reviver]
		local targetInfo = infos[job.target]
		local a, b = rootOf(reviver), rootOf(job.target)
		local valid = reviverInfo ~= nil
			and targetInfo ~= nil
			and reviverInfo.state == "Alive"
			and targetInfo.state == "Downed"
			and a ~= nil
			and b ~= nil
			and (a.Position - b.Position).Magnitude <= PCfg.ReviveRange + 1
		if not valid then
			revives[reviver] = nil
			setTargetProgress(job.target, 0)
		elseif reviverInfo ~= nil and targetInfo ~= nil then
			local progress = (now - job.startedAt) / PCfg.ReviveHoldSeconds
			if progress >= 1 then
				revives[reviver] = nil
				setAlive(targetInfo, PCfg.MaxHealth * PCfg.ReviveHealthFraction)
			else
				targetInfo.character:SetAttribute("ReviveProgress", progress)
			end
		end
	end
end

-- ===== วงจรหลัก (ฟื้นเลือด / ล้มหมดเวลา / ชุบ) =====

local function tick(dt: number)
	local now = os.clock()
	for player, info in infos do
		if info.character.Parent == nil then
			continue
		end
		if info.state == "Alive" then
			local hum = info.humanoid
			if hum.Health < PCfg.MaxHealth and now - info.lastHitClock >= PCfg.RegenDelaySeconds then
				hum.Health = math.min(PCfg.MaxHealth, hum.Health + PCfg.RegenPerSecond * dt)
			end
		elseif info.state == "Downed" then
			if now >= info.downedEndsAt then
				setDead(player, info)
			elseif info.humanoid.Health ~= 1 then
				info.humanoid.Health = 1 -- กันระบบฟื้นเลือดของ Roblox ดันเลือดคนล้มขึ้น
			end
		end
	end
	tickRevives(now)
end

-- ===== ตัวละครเกิด =====

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid == nil or not humanoid:IsA("Humanoid") then
		return
	end
	cancelRevivesInvolving(player)

	humanoid.MaxHealth = PCfg.MaxHealth
	humanoid.Health = PCfg.MaxHealth
	humanoid.WalkSpeed = PCfg.WalkSpeed

	local info: Info = {
		state = "Alive",
		character = character,
		humanoid = humanoid,
		lastHitClock = 0,
		downedEndsAt = 0,
		downedHealth = 0,
		jumpHeight = humanoid.JumpHeight,
		jumpPower = humanoid.JumpPower,
	}
	infos[player] = info
	character:SetAttribute("ReviveProgress", 0)
	character:SetAttribute("DownedHealth", 0)
	publish(info, 0)

	humanoid.Died:Connect(function()
		-- ตายจากเหตุอื่น (เช่น ตกเหว) ก็นับเป็นตาย
		if infos[player] == info then
			setDead(player, info)
		end
	end)

	-- ปิดระบบฟื้นเลือดมาตรฐานของ Roblox (เราคุมการฟื้นเลือดเอง)
	task.spawn(function()
		local defaultRegen = character:WaitForChild("Health", 3)
		if defaultRegen ~= nil and defaultRegen:IsA("Script") then
			defaultRegen:Destroy()
		end
	end)
end

local function setupPlayer(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	if player.Character ~= nil then
		task.spawn(onCharacterAdded, player, player.Character)
	else
		-- เราคุมการเกิดเอง (CharacterAutoLoads = false) จึงต้องเรียกเกิดครั้งแรกเอง
		task.spawn(PlayerHealth.respawnAfterDeath, player)
	end
end

function PlayerHealth.init()
	Players.CharacterAutoLoads = false

	local reviveHold = Remotes.remoteEvent("ReviveHold")
	reviveHold.OnServerEvent:Connect(function(player: Player, targetUserId: any, holding: any)
		if type(holding) ~= "boolean" then
			return
		end
		-- คำสั่งปล่อยต้องไม่ถูกทิ้ง (ไม่ผ่าน rate limit) · stopRevive เบาและทำซ้ำได้ปลอดภัย
		if not holding then
			stopRevive(player)
			return
		end
		if not RateLimit.allow(player, "ReviveHold", Config.Combat.ActionMinIntervalSeconds) then
			return
		end
		if not isFiniteNumber(targetUserId) or targetUserId % 1 ~= 0 then
			return
		end
		startRevive(player, targetUserId)
	end)

	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		cancelRevivesInvolving(player)
		infos[player] = nil
	end)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TICK_SECONDS)
			local now = os.clock()
			tick(now - last)
			last = now
		end
	end)
end

return PlayerHealth
