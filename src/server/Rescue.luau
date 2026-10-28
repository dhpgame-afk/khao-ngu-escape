--!strict
-- Rescue: กลับเข้าแมพหลังตาย — เซิร์ฟเวอร์ตัดสินทุกอย่าง · client ส่งได้แค่เจตนา
--   (ก) เพื่อนโทรเรียก: คนที่ยังมีชีวิตกด "โทรเรียกเพื่อน" → โทร Config.Player.PhoneCallSeconds วิ (ระหว่างโทรยิงไม่ได้)
--       → คนตายที่รอนานสุดเกิดใหม่ แล้วบินจากฟ้ามาลงข้างคนโทร (นับ callsMade ให้คนโทร)
--   (ข) ครบ Config.Player.RespawnSeconds (40 วิ) ไม่มีใครโทร → เกิดที่ถุงหนังสติ๊กในห้องรอ (ตรึงไว้)
--       → ผู้เล่นลากนิ้วเล็งบนแผนที่ แล้วส่ง SlingshotFire(x, z) → บินไปลงจุดนั้น
--       → ไม่ยิงใน Config.Rescue.AimSeconds → ยิงอัตโนมัติไปจุดลงของภารกิจ
--   ถ้าสายโทรเสร็จตอนคนตายรอเล็งหนังสติ๊กอยู่ สายโทรมาก่อน (ยกเลิกหน้าจอเล็ง แล้วบินไปหาคนโทร)
-- - ใช้เฉพาะผู้ร่วมภารกิจในช่วง InMission · ออกจากช่วงนี้ (หรือภารกิจจบ) = ล้างทุกอย่างและปลดตรึงทุกคน
-- - สถานะอยู่ฝั่งเซิร์ฟเวอร์ ส่งให้ client ผ่าน RemoteEvent "RescueState" (ไม่ใช่ข้อมูลลับ)
-- - ไม่ require Mission (กันพึ่งกันเป็นวงกลม) — Mission ส่งฟังก์ชันที่ต้องใช้เข้ามาทาง Rescue.init(deps)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local RateLimit = require(script.Parent.RateLimit)
local Lobby = require(script.Parent.Lobby)
local Combat = require(script.Parent.Combat)
local PlayerHealth = require(script.Parent.PlayerHealth)
local Flight = require(script.Parent.Flight)

local RC = Config.Rescue
local LaunchCfg = Config.Launch
local PlayerCfg = Config.Player

-- Dead = ตายแล้วรอเพื่อนโทร/ครบ 40 วิ · Aiming = อยู่ที่หนังสติ๊ก รอเล็ง · Flying = กำลังบินกลับเข้าแมพ
type Stage = "Dead" | "Aiming" | "Flying"
type FlightMode = "Call" | "Slingshot"

type Entry = {
	player: Player,
	stage: Stage,
	diedClock: number, -- os.clock ตอนตาย · ใช้เรียง "รอนานสุด"
	deadlineClock: number, -- Dead: ถึงเวลานี้ → ไปหนังสติ๊ก · Aiming: ถึงเวลานี้ → ยิงอัตโนมัติ
	reservedBy: Player?, -- มีคนกำลังโทรเรียกคนนี้ (จองไว้ กันสองคนปลุกคนเดียวกัน)
	spawned: boolean, -- สร้างตัวละครใหม่ที่ถุงหนังสติ๊กแล้ว (ตรึงอยู่)
	token: number, -- เปลี่ยนทุกครั้งที่ขั้นเปลี่ยน · เธรด/ตัวเฝ้าที่ถือค่าเก่าต้องหยุดทำงาน
	slot: number, -- ช่องยืนที่ถุงหนังสติ๊ก (ไม่ให้ซ้อนกัน)
}

type Call = {
	caller: Player,
	target: Player,
	endsClock: number,
}

export type Deps = {
	getPhase: () -> string, -- "InMission" เท่านั้นที่ใช้ระบบนี้ได้
	isParticipant: (Player) -> boolean,
	getParticipants: () -> { Player },
	getLanding: () -> Vector3?, -- จุดลงจริงของภารกิจ (หลัง raycast ลงพื้น)
	getSafeSpot: () -> Vector3?, -- ที่สำรองถ้ายังไม่มีจุดลง
	groundHit: (x: number, z: number, startY: number?) -> Vector3?,
	groundPoint: (x: number, z: number, startY: number?) -> Vector3,
	clampLanding: (x: number, z: number) -> (number, number),
	recordCall: (Player) -> (), -- นับ callsMade ใน Mission
}

local Rescue = {}

local deps: Deps = {
	getPhase = function(): string
		return "Lobby"
	end,
	isParticipant = function(_player: Player): boolean
		return false
	end,
	getParticipants = function(): { Player }
		return {}
	end,
	getLanding = function(): Vector3?
		return nil
	end,
	getSafeSpot = function(): Vector3?
		return nil
	end,
	groundHit = function(_x: number, _z: number, _startY: number?): Vector3?
		return nil
	end,
	groundPoint = function(x: number, z: number, _startY: number?): Vector3
		return Vector3.new(x, LaunchCfg.FallbackGroundY, z)
	end,
	clampLanding = function(x: number, z: number): (number, number)
		return x, z
	end,
	recordCall = function(_player: Player) end,
}

local callCooldownUntil: { [Player]: number } = {} -- คนโทรที่เพิ่งวางสาย/ถูกตัดสาย: โทรใหม่ไม่ได้จนถึง os.clock นี้ (กันกวนเวลานับของคนตาย)
local entries: { [Player]: Entry } = {} -- คนที่ตายแล้ว/กำลังกลับเข้าแมพ
local calls: { [Player]: Call } = {} -- key = คนโทร
local stateEvent: RemoteEvent? = nil
local epoch = 0 -- เพิ่มตอนล้างทุกอย่าง (cleanupAll) · เธรดเก่าที่ถือค่าเก่าหยุดทำงาน
local tokenCounter = 0
local lastMatePushClock = 0
local rng = Random.new()

-- ===== ตัวช่วย =====

local function isFiniteNumber(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
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

local function nextToken(): number
	tokenCounter += 1
	return tokenCounter
end

local function serverTimeOf(clockValue: number): number
	return Workspace:GetServerTimeNow() + (clockValue - os.clock())
end

local function isMissionActive(): boolean
	return deps.getPhase() == "InMission"
end

-- ตั้ง Attribute "Calling" บนตัวละคร (ให้ client ของคนโทรเลิกยิง/ขว้างทันที ไม่ลดกระสุนในจอเอง)
local function setCallingFlag(player: Player, isCalling: boolean)
	Combat.setCalling(player, isCalling)
	local character = player.Character
	if character ~= nil then
		character:SetAttribute("Calling", isCalling)
	end
end

-- ===== ส่งสถานะให้ client =====

-- รายการคนที่รอเพื่อนโทร (ยังไม่มีใครจอง) เรียงจากรอนานสุด
local function waitingEntries(): { Entry }
	local list: { Entry } = {}
	for player, entry in entries do
		-- เกินเวลาแล้ว (กำลังจะไปหนังสติ๊ก/ยิงอัตโนมัติ) ไม่ให้จองเพิ่ม กันคนโทร-วางสายวนให้เวลาตายค้าง
		if
			player.Parent == Players
			and entry.reservedBy == nil
			and (entry.stage == "Dead" or entry.stage == "Aiming")
			and os.clock() < entry.deadlineClock
		then
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a: Entry, b: Entry)
		if a.diedClock == b.diedClock then
			return a.player.UserId < b.player.UserId
		end
		return a.diedClock < b.diedClock
	end)
	return list
end

local function buildPayload(player: Player): { [string]: any }
	local entry = entries[player]
	local participant = deps.isParticipant(player)
	local stage = "None"
	local endsAt = 0
	local beingCalled = false
	local ready = false
	if entry ~= nil then
		ready = entry.spawned
		stage = entry.stage
		if entry.stage == "Dead" or entry.stage == "Aiming" then
			endsAt = serverTimeOf(entry.deadlineClock)
		end
		beingCalled = entry.reservedBy ~= nil
	end
	local call = calls[player]
	local mates = {}
	if participant then
		for _, other in deps.getParticipants() do
			if other ~= player and other.Parent == Players then
				local root = rootOf(other)
				if root ~= nil then
					local otherEntry = entries[other]
					table.insert(mates, {
						userId = other.UserId,
						x = root.Position.X,
						z = root.Position.Z,
						alive = otherEntry == nil or otherEntry.stage == "Flying",
					})
				end
			end
		end
	end
	return {
		stage = stage, -- "None" | "Dead" | "Aiming" | "Flying"
		endsAt = endsAt, -- เวลาเซิร์ฟเวอร์: Dead = ไปหนังสติ๊ก · Aiming = ยิงอัตโนมัติ · อย่างอื่น 0
		beingCalled = beingCalled, -- เพื่อนกำลังโทรเรียกคนนี้อยู่
		ready = ready, -- ตัวละครอยู่ที่ถุงหนังสติ๊กแล้ว (client ถึงจะให้ลากเล็งได้ · ก่อนหน้านี้เซิร์ฟเวอร์ทิ้งคำสั่งยิง)
		waiting = if participant and isMissionActive() then #waitingEntries() else 0, -- n ในปุ่ม "โทรเรียกเพื่อน (n)"
		callEndsAt = if call ~= nil then serverTimeOf(call.endsClock) else 0, -- > 0 = กำลังโทรอยู่
		mates = mates, -- เพื่อนร่วมภารกิจ: userId, ตำแหน่งแนวราบ (ไว้ดูเพื่อน/วาดบนแผนที่เล็ง)
	}
end

local function push(player: Player)
	local event = stateEvent
	if event == nil or player.Parent ~= Players then
		return
	end
	-- ครอบ pcall: การส่งสถานะพังต้องไม่ลามไปทำให้ระบบหลัก (เช่น ตอนตาย) ล้ม
	local ok, err = pcall(function()
		event:FireClient(player, buildPayload(player))
	end)
	if not ok then
		warn("[Rescue] ส่งสถานะให้ client ล้มเหลว", player.Name, err)
	end
end

-- ส่งให้ผู้ร่วมภารกิจทุกคน (+ extra = คนที่เพิ่งพ้นภารกิจ ต้องได้รับสถานะ "None")
local function pushAll(extra: { Player }?)
	local sent: { [Player]: boolean } = {}
	for _, player in deps.getParticipants() do
		sent[player] = true
		push(player)
	end
	if extra ~= nil then
		for _, player in extra do
			if not sent[player] then
				push(player)
			end
		end
	end
end

-- ===== สายโทร =====

-- applyCooldown = true เมื่อคนโทรวางสายเอง/ถูกตัดสายเพราะหมดเวลา: โทรใหม่ไม่ได้ช่วงหนึ่ง (กันกวน)
local function cancelCall(caller: Player, applyCooldown: boolean?)
	local call = calls[caller]
	if call == nil then
		return
	end
	if applyCooldown then
		callCooldownUntil[caller] = os.clock() + RC.CallCancelCooldownSeconds
	end
	calls[caller] = nil
	setCallingFlag(caller, false)
	local targetEntry = entries[call.target]
	if targetEntry ~= nil and targetEntry.reservedBy == caller then
		targetEntry.reservedBy = nil -- คืนคิว: คนอื่นโทรเรียกคนนี้ต่อได้
	end
	pushAll()
end

-- เลือกคนที่จะเรียก: รอนานสุดในบรรดาที่ยังไม่มีใครจอง
local function pickTarget(): Entry?
	return waitingEntries()[1]
end

-- ===== บินกลับเข้าแมพ =====

-- ปล่อยตัวหลังบินจบ: เอาออกจากรายการ ปลดล็อกอาวุธ แล้วแจ้ง client
local function completeLanding(entry: Entry)
	local player = entry.player
	if entries[player] ~= entry then
		return
	end
	entries[player] = nil
	-- รับประกันสถานะตอนลง: Alive เลือด 100 ไม่มีเลือดชั่วคราว (ระหว่างนี้ PlayerHealth ไม่รับดาเมจอยู่แล้ว)
	PlayerHealth.ensureFullHealth(player)
	if player.Parent == Players and isMissionActive() and deps.isParticipant(player) then
		Combat.setLocked(player, false) -- ประทัดคงจำนวนเดิมตาม Combat
	end
	pushAll({ player })
end

-- ขั้นตอนสำรอง: เกิดใหม่ไม่สำเร็จ → กลับไปรอ แล้วลองใหม่
local function retryLater(entry: Entry)
	if entries[entry.player] ~= entry then
		return
	end
	entry.stage = "Dead"
	entry.spawned = false
	entry.reservedBy = nil
	entry.token = nextToken()
	entry.deadlineClock = os.clock() + RC.SpawnRetrySeconds
	pushAll()
end

-- ปล่อยตัวแบบบังคับ (ตัวเฝ้าเตือนว่าค้าง / การบินพัง): วางที่จุดลงแล้วปลดตรึง · ไม่มีตัวละครเลย → กลับไปรอลองใหม่
local function forceRelease(entry: Entry, endPos: Vector3)
	if entries[entry.player] ~= entry then
		return
	end
	local root = rootOf(entry.player)
	if not entry.spawned or root == nil then
		retryLater(entry)
		return
	end
	entry.token = nextToken() -- เธรดบินเก่าหยุดทำงาน
	root.CFrame = CFrame.new(endPos)
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = false
	completeLanding(entry)
end

-- สร้างตัวละครใหม่ (เกิดที่ห้องรอตามจุดเกิดปกติ) แล้วตรึงทันที · คืน nil ถ้าไม่สำเร็จ หรือถูกยกเลิกกลางทาง
-- ล็อกอาวุธก่อนสร้าง: กันช่วงสั้น ๆ ที่ตัวละครใหม่ยังไม่ถูกตรึงแล้วมีคนยิงได้
local function spawnCharacter(entry: Entry, stillValid: () -> boolean): (Model?, BasePart?)
	local player = entry.player
	Combat.setLocked(player, true)
	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	if not ok then
		warn("[Rescue] เกิดใหม่ไม่สำเร็จ", player.Name, err)
		return nil, nil
	end
	if not stillValid() then
		return nil, nil
	end
	local character = player.Character
	if character == nil then
		return nil, nil
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not stillValid() or root == nil or not root:IsA("BasePart") then
		return nil, nil
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = true
	-- รอ PlayerHealth ตั้งสถานะ Alive เลือดเต็มให้ตัวละครใหม่ (ปกติภายในไม่กี่เฟรม)
	local waited = 0
	while character:GetAttribute("State") ~= "Alive" and waited < 5 and stillValid() do
		task.wait(0.05)
		waited += 0.05
	end
	if not stillValid() then
		return nil, nil
	end
	return character, root
end

-- เธรดบินกลับเข้าแมพ (รันใน task.spawn + pcall) · mode "Call": วางตัวสูงเหนือจุดลงแล้วบินลงมา · "Slingshot": บินจากถุงหนังสติ๊ก
local function runFlight(entry: Entry, stillValid: () -> boolean, mode: FlightMode, endPos: Vector3)
	local player = entry.player
	local character: Model? = nil
	local root: BasePart? = nil
	if entry.spawned then
		character, root = player.Character, rootOf(player) -- เกิดที่ถุงหนังสติ๊กไว้แล้ว (ตรึงอยู่)
	else
		character, root = spawnCharacter(entry, stillValid)
	end
	if not stillValid() then
		return
	end
	if character == nil or root == nil then
		retryLater(entry)
		return
	end
	entry.spawned = true
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero

	local startPos = root.Position
	local seconds = LaunchCfg.FlightSeconds
	local peak = LaunchCfg.ArcPeakHeight
	if mode == "Call" then
		-- เริ่มจากฟ้าเหนือจุดลง ห่างออกไปในทิศสุ่ม แล้วบินลงมา
		local angle = rng:NextNumber(0, 2 * math.pi)
		startPos = endPos
			+ Vector3.new(
				math.cos(angle) * RC.CallApproachStuds,
				RC.CallDropHeight,
				math.sin(angle) * RC.CallApproachStuds
			)
		seconds = RC.CallFlightSeconds
		peak = RC.CallArcPeakHeight
	end
	local flat = Vector3.new(endPos.X - startPos.X, 0, endPos.Z - startPos.Z)
	local facing = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, 1)
	root.CFrame = CFrame.lookAt(startPos, startPos + facing)

	Flight.streamAround(player, endPos, LaunchCfg.StreamTimeoutSeconds)
	if not stillValid() then
		return
	end

	local leg: Flight.Leg = {
		player = player,
		character = character,
		root = root,
		startPos = startPos,
		endPos = endPos,
		facing = facing,
	}
	if not Flight.run({ leg }, seconds, peak, stillValid, nil) then
		return
	end
	Flight.land(leg)
	completeLanding(entry)
end

-- เริ่มบินกลับเข้าแมพ (ขั้น Flying) · endPos = ตำแหน่ง HumanoidRootPart ตอนลง
local function beginFlight(entry: Entry, mode: FlightMode, endPos: Vector3)
	local player = entry.player
	entry.stage = "Flying"
	entry.reservedBy = nil
	entry.token = nextToken()
	local token = entry.token
	local myEpoch = epoch
	pushAll()

	local function stillValid(): boolean
		return epoch == myEpoch
			and entries[player] == entry
			and entry.token == token
			and player.Parent == Players
			and isMissionActive()
	end

	task.spawn(function()
		local ok, err = pcall(runFlight, entry, stillValid, mode, endPos)
		if not ok then
			warn("[Rescue] บินกลับเข้าแมพล้มเหลว", player.Name, err)
			if stillValid() then
				forceRelease(entry, endPos)
			end
		end
	end)

	-- ตัวเฝ้า: ใครก็ห้ามถูกตรึงค้างตลอดไป
	local seconds = if mode == "Call" then RC.CallFlightSeconds else LaunchCfg.FlightSeconds
	task.delay(seconds + LaunchCfg.StreamTimeoutSeconds + RC.WatchdogExtraSeconds, function()
		if stillValid() then
			warn(
				"[Rescue] บินกลับเข้าแมพค้างเกินเวลา — ปล่อยตัว",
				player.Name
			)
			forceRelease(entry, endPos)
		end
	end)
end

-- ===== โทรเรียกเพื่อน =====

-- หาจุดลงข้างคนโทร: ลองหลายทิศรอบตัว เอาจุดแรกที่พื้นสูงใกล้เคียงกับใต้เท้าคนโทร (ไม่ลงบนหลังคา/โขดหินเหนือหัว)
local function pickCallLanding(callerPosition: Vector3): Vector3
	local footY = callerPosition.Y - LaunchCfg.LandingRootHeight
	local startAngle = rng:NextNumber(0, 2 * math.pi)
	for i = 0, RC.CallLandingAttempts - 1 do
		local angle = startAngle + i * (2 * math.pi / RC.CallLandingAttempts)
		local x = callerPosition.X + math.cos(angle) * RC.CallLandingSideStuds
		local z = callerPosition.Z + math.sin(angle) * RC.CallLandingSideStuds
		local hit = deps.groundHit(x, z, callerPosition.Y + RC.CallRayUp)
		if hit ~= nil and math.abs(hit.Y - footY) <= RC.CallMaxHeightDiff then
			return hit
		end
	end
	-- ไม่เจอทิศไหนเลย: ลงข้างคนโทรที่ความสูงเท้าของคนโทร
	return Vector3.new(callerPosition.X + RC.CallLandingSideStuds, footY, callerPosition.Z)
end

local function finishCall(call: Call)
	local caller = call.caller
	calls[caller] = nil
	setCallingFlag(caller, false)
	local entry = entries[call.target]
	local callerRoot = rootOf(caller)
	local reservedByMe = entry ~= nil and entry.reservedBy == caller
	if entry == nil or not reservedByMe or callerRoot == nil then
		if entry ~= nil and reservedByMe then
			entry.reservedBy = nil -- คืนคิว ไม่ให้เป้าหมายค้างถูกจอง
		end
		pushAll()
		return
	end
	deps.recordCall(caller)
	local ground = pickCallLanding(callerRoot.Position)
	beginFlight(entry, "Call", ground + Vector3.new(0, LaunchCfg.LandingRootHeight, 0))
end

local function callerIsValid(caller: Player): boolean
	return caller.Parent == Players
		and deps.isParticipant(caller)
		and entries[caller] == nil
		and PlayerHealth.getState(caller) == "Alive"
		and rootOf(caller) ~= nil
end

local function onCallStart(player: Player)
	if not RateLimit.allow(player, "CallFriendStart", RC.CallMinIntervalSeconds) then
		return
	end
	if not isMissionActive() or not callerIsValid(player) or calls[player] ~= nil then
		return
	end
	local cooldownUntil = callCooldownUntil[player]
	if cooldownUntil ~= nil and os.clock() < cooldownUntil then
		return -- เพิ่งวางสาย รอสักครู่
	end
	local target = pickTarget()
	if target == nil then
		push(player) -- ไม่มีใครให้เรียก (อาจมีคนอื่นจองไปแล้ว) · บอก client ให้ปุ่มตรงกับความจริง
		return
	end
	target.reservedBy = player -- จองทันที กันสองคนโทรเรียกคนเดียวกัน
	calls[player] = { caller = player, target = target.player, endsClock = os.clock() + PlayerCfg.PhoneCallSeconds }
	setCallingFlag(player, true)
	pushAll()
end

local function onCallCancel(player: Player)
	if not RateLimit.allow(player, "CallFriendCancel", RC.CancelMinIntervalSeconds) then
		return
	end
	cancelCall(player, true)
end

-- ===== หนังสติ๊กยิงตัวเอง =====

-- ครบ 40 วิ: สร้างตัวละครที่ถุงหนังสติ๊ก (ตรึงไว้) แล้วให้ผู้เล่นเล็ง
local function startSlingshot(entry: Entry)
	local player = entry.player
	entry.stage = "Aiming"
	entry.token = nextToken()
	entry.deadlineClock = os.clock() + RC.AimSeconds
	entry.spawned = false
	local aimingCount = 0
	for _, other in entries do
		if other ~= entry and other.stage == "Aiming" then
			aimingCount += 1
		end
	end
	entry.slot = aimingCount
	local token = entry.token
	local myEpoch = epoch
	pushAll()

	local function stillValid(): boolean
		return epoch == myEpoch
			and entries[player] == entry
			and entry.token == token
			and player.Parent == Players
			and isMissionActive()
	end

	task.spawn(function()
		local ok, err = pcall(function()
			local character, root = spawnCharacter(entry, stillValid)
			if not stillValid() then
				return
			end
			if character == nil or root == nil then
				retryLater(entry)
				return
			end
			local pouchCf = Lobby.getPouchStandCFrame()
			local offsetX = (entry.slot - 1.5) * LaunchCfg.SpreadStuds
			local position = pouchCf:PointToWorldSpace(Vector3.new(offsetX, 0, 0))
			root.CFrame = CFrame.lookAt(position, position + Vector3.new(0, 0, 1)) -- หันไปทางที่ยิง (ใต้ = +Z)
			root.AssemblyLinearVelocity = Vector3.zero
			entry.spawned = true
			pushAll() -- บอก client ว่าเล็งได้แล้ว (ready)
		end)
		if not ok then
			warn("[Rescue] เตรียมหนังสติ๊กล้มเหลว", player.Name, err)
			if stillValid() then
				retryLater(entry)
			end
		end
	end)
end

-- ยิงไปจุด (x, z) ที่ผ่านการตรวจแล้ว
local function fireSlingshot(entry: Entry, x: number, z: number)
	local ground = deps.groundPoint(x, z)
	beginFlight(entry, "Slingshot", ground + Vector3.new(0, LaunchCfg.LandingRootHeight, 0))
end

-- ไม่ยิงภายในเวลา: ไปจุดลงของภารกิจ (สุ่มรอบ ๆ เล็กน้อย) หรือจุดปลอดภัย
local function autoFire(entry: Entry)
	local landing = deps.getLanding() or deps.getSafeSpot()
	local x, z = 0, 0
	if landing ~= nil then
		x = landing.X + rng:NextNumber(-RC.AutoFireScatterStuds, RC.AutoFireScatterStuds)
		z = landing.Z + rng:NextNumber(-RC.AutoFireScatterStuds, RC.AutoFireScatterStuds)
	end
	x, z = deps.clampLanding(x, z)
	fireSlingshot(entry, x, z)
end

local function onSlingshotFire(player: Player, x: any, z: any)
	if not RateLimit.allow(player, "SlingshotFire", RC.FireMinIntervalSeconds) then
		return
	end
	if not isFiniteNumber(x) or not isFiniteNumber(z) then
		return
	end
	if not isMissionActive() or not deps.isParticipant(player) then
		return
	end
	local entry = entries[player]
	-- ต้องอยู่ขั้นเล็ง ตัวละครพร้อมแล้ว และไม่มีเพื่อนกำลังโทรเรียก (สายโทรมาก่อน)
	if entry == nil or entry.stage ~= "Aiming" or not entry.spawned or entry.reservedBy ~= nil then
		return
	end
	-- จุดต้องอยู่ในแผนที่เว้นขอบ (เกินนิดเดียวจากเศษทศนิยมยอมรับแล้วบีบเข้าขอบ)
	local tolerance = RC.FireToleranceStuds
	local insideX, insideZ = deps.clampLanding(x, z)
	if math.abs(insideX - x) > tolerance or math.abs(insideZ - z) > tolerance then
		return
	end
	fireSlingshot(entry, insideX, insideZ)
end

-- ===== ตาย / ออกเกม / ล้างทุกอย่าง =====

-- PlayerHealth เรียกตอนตาย · คืน true = Rescue รับไปดูแล (ผู้ร่วมภารกิจในช่วง InMission เท่านั้น)
function Rescue.onDeath(player: Player): boolean
	if not isMissionActive() or not deps.isParticipant(player) then
		return false
	end
	local old = entries[player]
	if old ~= nil then
		-- ตายซ้ำตอนเล็ง/กำลังบิน: ปลดตรึงซากเดิม (เธรดบินเก่าหยุดเองเพราะ token ไม่ตรง)
		local oldRoot = rootOf(player)
		if oldRoot ~= nil then
			oldRoot.Anchored = false
		end
		if old.reservedBy ~= nil then
			cancelCall(old.reservedBy) -- (กันไว้) ไม่ควรเกิด แต่ถ้าเกิดต้องไม่ทิ้งสายค้าง
		end
	end
	if calls[player] ~= nil then
		cancelCall(player) -- คนโทรตายกลางสาย
	end
	local now = os.clock()
	entries[player] = {
		player = player,
		stage = "Dead",
		diedClock = now,
		deadlineClock = now + PlayerCfg.RespawnSeconds,
		reservedBy = nil,
		spawned = false,
		token = nextToken(), -- (ตายซ้ำตอนกำลังบิน → เธรดบินเก่าหยุดเอง เพราะค่าไม่ตรงกัน)
		slot = 0,
	}
	local okPush, errPush = pcall(pushAll) -- ส่งสถานะพัง ไม่ทำให้ถือว่า "ไม่รับ" (ไม่งั้นเกิดใหม่ซ้ำสองรอบ)
	if not okPush then
		warn("[Rescue] pushAll ล้มเหลวตอนตาย", errPush)
	end
	return true
end

function Rescue.onPlayerRemoving(player: Player)
	local entry = entries[player]
	entries[player] = nil
	callCooldownUntil[player] = nil
	if entry ~= nil and entry.reservedBy ~= nil then
		cancelCall(entry.reservedBy) -- คนที่ถูกโทรเรียกออกเกม → วางสาย
	end
	if calls[player] ~= nil then
		cancelCall(player)
	end
	pushAll()
end

-- ผู้เล่นคนนี้ติดอยู่กับขั้นตอนกลับเข้าแมพ (ตาย/เล็ง/กำลังบิน) ไหม — ใช้ห้ามหยิบของ/กินขนมระหว่างนี้
function Rescue.isBusy(player: Player): boolean
	return entries[player] ~= nil
end

-- ล้างทุกอย่าง: ยกเลิกสาย ปลดตรึงทุกคน ปิดหน้าจอของ client (ภารกิจจบ / ออกจากช่วง InMission)
function Rescue.cleanupAll()
	epoch += 1 -- เธรดบิน/ตัวเฝ้าเก่าหยุดทำงาน
	local affected: { Player } = {}
	for player in entries do
		table.insert(affected, player)
	end
	for caller in calls do
		table.insert(affected, caller)
		setCallingFlag(caller, false)
	end
	entries = {}
	calls = {}
	callCooldownUntil = {}
	for _, player in affected do
		local root = rootOf(player)
		if root ~= nil then
			root.Anchored = false
		end
	end
	pushAll(affected)
end

-- ===== วงจรหลัก =====

-- สายโทร: คนโทรต้องยังปกติ (ไม่ล้ม/ตาย/ออก) และเป้าหมายยังรออยู่ที่จองไว้ · ครบเวลา → เรียกกลับ
-- แต่ละรายการครอบ pcall แยก: รายการใดพัง รายการอื่นต้องไปต่อ
local function tickCalls(now: number)
	for caller, call in calls do
		local ok, err = pcall(function()
			local targetEntry = entries[call.target]
			local targetOk = targetEntry ~= nil
				and targetEntry.reservedBy == caller
				and (targetEntry.stage == "Dead" or targetEntry.stage == "Aiming")
			if not callerIsValid(caller) or not targetOk then
				cancelCall(caller)
			elseif now >= call.endsClock then
				finishCall(call)
			end
		end)
		if not ok then
			warn("[Rescue] tickCalls error:", err)
			pcall(cancelCall, caller)
		end
	end
end

-- คนตาย: ครบ 40 วิ → หนังสติ๊ก · ครบเวลาเล็ง → ยิงอัตโนมัติ
-- คนที่มีสายโทรจองอยู่รอผลสายก่อน แต่เกินเวลา + ReservationGraceSeconds แล้วตัดสายทิ้ง (กันจองค้างให้เวลาตายไม่เดิน)
local function tickEntries(now: number)
	for player, entry in entries do
		local ok, err = pcall(function()
			if player.Parent ~= Players then
				Rescue.onPlayerRemoving(player)
			elseif entry.reservedBy ~= nil then
				if now >= entry.deadlineClock + RC.ReservationGraceSeconds then
					cancelCall(entry.reservedBy, true)
				end
			elseif entry.stage == "Dead" and now >= entry.deadlineClock then
				startSlingshot(entry)
			elseif entry.stage == "Aiming" and entry.spawned and now >= entry.deadlineClock then
				autoFire(entry)
			end
		end)
		if not ok then
			warn("[Rescue] tickEntries error:", err)
		end
	end
end

local function tick()
	if not isMissionActive() then
		if next(entries) ~= nil or next(calls) ~= nil then
			Rescue.cleanupAll()
		end
		return
	end
	local now = os.clock()
	tickCalls(now)
	tickEntries(now)

	-- คนที่กำลังเล็ง: อัปเดตตำแหน่งเพื่อนบนแผนที่เป็นระยะ
	if now - lastMatePushClock >= RC.MateRefreshSeconds then
		lastMatePushClock = now
		for player, entry in entries do
			if entry.stage == "Aiming" then
				push(player)
			end
		end
	end
end

function Rescue.init(dependencies: Deps)
	deps = dependencies
	stateEvent = Remotes.remoteEvent("RescueState") -- server → ผู้ร่วมภารกิจ: สถานะกลับเข้าแมพ (ดู buildPayload)
	Remotes.remoteEvent("CallFriendStart").OnServerEvent:Connect(onCallStart) -- ()
	Remotes.remoteEvent("CallFriendCancel").OnServerEvent:Connect(onCallCancel) -- ()
	Remotes.remoteEvent("SlingshotFire").OnServerEvent:Connect(onSlingshotFire) -- (x: number, z: number)
	PlayerHealth.setDeathHandler(Rescue.onDeath)
	PlayerHealth.setDamageGuard(Rescue.isBusy) -- ตาย/เล็ง/กำลังบินกลับ: ไม่รับดาเมจ

	task.spawn(function()
		while true do
			task.wait(RC.TickSeconds)
			-- ครอบด้วย xpcall: ถ้ารอบใดพัง ลูปต้องไม่ตาย (ไม่งั้นคนตายค้างและสายโทรไม่จบ)
			local ok, err = xpcall(tick, debug.traceback)
			if not ok then
				warn("[Rescue] tick error:", err)
			end
		end
	end)
end

return Rescue
