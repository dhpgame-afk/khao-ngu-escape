--!strict
-- PlayerData: โหลด/เซฟข้อมูลผู้เล่นข้ามเกม (เงิน ปืน ขนม สถิติ) — ทำงานฝั่งเซิร์ฟเวอร์เท่านั้น
-- กฎเหล็ก: ถ้าโหลดไม่สำเร็จ ห้ามเซฟทับด้วยค่าเริ่มต้น (session.saveable = false)

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local DataConfig = Config.Data

export type PlayerRecord = {
	dataVersion: number,
	money: number,
	ownedGuns: { string },
	snacks: number,
	stats: {
		missionsCompleted: number,
		monkeysKilled: number,
	},
}

type Session = {
	player: Player,
	data: PlayerRecord,
	loaded: boolean, -- โหลดเสร็จแล้ว (ไม่ว่าสำเร็จหรือไม่)
	saveable: boolean, -- true เฉพาะเมื่อโหลดข้อมูลจริงสำเร็จและยังถือล็อกอยู่
	unsavedTest: boolean, -- โหมดทดสอบใน Studio: เล่นในหน่วยความจำได้ แต่ห้ามเซฟเด็ดขาด
	saving: boolean,
	dirty: boolean, -- มีข้อมูลเปลี่ยนตั้งแต่เซฟครั้งล่าสุด
	lastSaveClock: number,
	leaving: boolean,
	released: boolean, -- เซฟครั้งสุดท้าย + ปล่อยล็อกแล้ว
	message: string?, -- ข้อความภาษาไทยแจ้งผู้เล่น
}

local PlayerData = {}

local store = DataStoreService:GetDataStore(DataConfig.StoreName)
local sessions: { [Player]: Session } = {}
local closing = false
local dataChanged: RemoteEvent? = nil
local lastGetMyData: { [Player]: number } = {}

-- โหมด "เล่นทดสอบไม่เซฟ" เปิดได้เฉพาะใน Studio เท่านั้น
local STUDIO_UNSAVED: boolean = DataConfig.StudioAllowUnsaved and RunService:IsStudio()

-- Studio ไม่มี JobId จริง จึงสุ่มเอง เพื่อให้ล็อกใช้งานได้
local JOB_ID: string = if game.JobId ~= "" then game.JobId else ("studio-" .. HttpService:GenerateGUID(false))

local MSG_LOAD_FAILED =
	"โหลดข้อมูลของคุณไม่สำเร็จ เกมนี้จะไม่บันทึกความคืบหน้ารอบนี้ เงินและปืนเดิมของคุณปลอดภัย ลองออกแล้วเข้าใหม่นะ"
local MSG_LOCKED =
	"ข้อมูลของคุณกำลังถูกใช้อยู่ในเซิร์ฟเวอร์อื่น เกมนี้จะไม่บันทึกความคืบหน้ารอบนี้ รอสักครู่แล้วเข้าใหม่นะ"
local MSG_NEW_VERSION =
	"ข้อมูลของคุณมาจากเกมรุ่นที่ใหม่กว่า เกมนี้จะไม่บันทึกความคืบหน้ารอบนี้"
local MSG_STUDIO_UNSAVED =
	"โหมดทดสอบใน Studio: เชื่อมที่เก็บข้อมูลไม่ได้ ข้อมูลรอบนี้จะไม่ถูกบันทึก"
local MSG_LOST_LOCK =
	"ข้อมูลของคุณถูกเซิร์ฟเวอร์อื่นรับช่วงไปแล้ว เกมนี้จะหยุดบันทึกความคืบหน้ารอบนี้"

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function newDefaultRecord(): PlayerRecord
	return {
		dataVersion = DataConfig.CurrentVersion,
		money = 0,
		ownedGuns = { Config.DefaultGunId },
		snacks = 0,
		stats = { missionsCompleted = 0, monkeysKilled = 0 },
	}
end

local function cleanCount(value: any): number
	if type(value) == "number" and value == value and value >= 0 and value < 2 ^ 52 then
		return math.floor(value)
	end
	return 0
end

-- ===== การแปลงข้อมูลเก่า =====
-- migrations[n] = ฟังก์ชันแปลงข้อมูลจากเวอร์ชัน n → n+1 (เพิ่มตรงนี้เมื่อเปลี่ยนรูปแบบข้อมูล)
local migrations: { [number]: (any) -> any } = {}

-- คืน (ข้อมูลที่แปลงแล้ว, ok) — ok=false เมื่อข้อมูลมาจากเวอร์ชันที่ใหม่กว่าเกมนี้ (ห้ามเซฟทับ)
function PlayerData.migrate(raw: any): (PlayerRecord?, boolean)
	if type(raw) ~= "table" then
		return nil, false
	end
	local version = raw.dataVersion
	if type(version) ~= "number" then
		version = 1
	end
	if version > DataConfig.CurrentVersion then
		return nil, false
	end
	while version < DataConfig.CurrentVersion do
		local step = migrations[version]
		if step == nil then
			return nil, false -- ไม่มีวิธีแปลง → ไม่เสี่ยงเซฟทับ
		end
		raw = step(raw)
		version += 1
	end

	-- เติม/ล้างค่าให้ถูกรูปแบบ (เก็บเฉพาะฟิลด์ที่รู้จัก)
	local record = newDefaultRecord()
	record.money = cleanCount(raw.money)
	record.snacks = math.min(cleanCount(raw.snacks), Config.Snacks.MaxStored)
	local stats = if type(raw.stats) == "table" then raw.stats else {}
	record.stats.missionsCompleted = cleanCount(stats.missionsCompleted)
	record.stats.monkeysKilled = cleanCount(stats.monkeysKilled)

	local guns: { string } = {}
	local seen: { [string]: boolean } = {}
	if type(raw.ownedGuns) == "table" then
		for _, id in raw.ownedGuns do
			if type(id) == "string" and not seen[id] then
				seen[id] = true
				table.insert(guns, id)
			end
		end
	end
	if not seen[Config.DefaultGunId] then
		table.insert(guns, 1, Config.DefaultGunId)
	end
	record.ownedGuns = guns
	return record, true
end

-- ===== ส่งข้อมูลให้เจ้าของเท่านั้น (ไม่ใช้ Attribute เพราะจะเห็นกันทุกคน) =====
local function buildPayload(session: Session): { [string]: any }
	return {
		money = session.data.money,
		snacks = session.data.snacks,
		ownedGuns = table.clone(session.data.ownedGuns),
		message = session.message,
	}
end

local function pushToOwner(session: Session)
	local event = dataChanged
	if event ~= nil and session.player.Parent == Players then
		event:FireClient(session.player, buildPayload(session))
	end
end

-- เรียกทุกครั้งที่ข้อมูลเปลี่ยน
local function markChanged(session: Session)
	session.dirty = true
	pushToOwner(session)
end

local function isLockFresh(record: any): boolean
	if type(record) ~= "table" then
		return false
	end
	local lockJobId = record.lockJobId
	local lockTime = record.lockTime
	if type(lockJobId) ~= "string" or lockJobId == JOB_ID then
		return false
	end
	if type(lockTime) ~= "number" then
		return false
	end
	return (os.time() - lockTime) < DataConfig.LockStaleSeconds
end

-- ===== โหลด =====
-- คืนสถานะ: "ok" | "locked" | "newer" | "error"
local function tryLoad(userId: number): (string, PlayerRecord?)
	local key = DataConfig.KeyPrefix .. userId
	local result: PlayerRecord? = nil
	local status = "ok"

	local success, err = pcall(function()
		store:UpdateAsync(key, function(old: any)
			-- ฟังก์ชันนี้อาจถูกรันซ้ำ ต้องรีเซ็ตค่าทุกครั้ง
			result = nil
			status = "ok"
			local base: any
			if old == nil then
				base = newDefaultRecord()
			elseif type(old) ~= "table" then
				status = "error" -- ข้อมูลเสีย ห้ามแตะ
				return nil
			else
				if isLockFresh(old) then
					status = "locked"
					return nil
				end
				base = old
			end
			local migrated, ok = PlayerData.migrate(base)
			if not ok or migrated == nil then
				status = "newer"
				return nil
			end
			result = migrated
			local toSave: any = deepCopy(migrated)
			toSave.lockJobId = JOB_ID
			toSave.lockTime = os.time()
			return toSave
		end)
	end)

	if not success then
		warn("[PlayerData] โหลดไม่สำเร็จ:", err)
		return "error", nil
	end
	return status, result
end

local function loadWithRetries(session: Session): (string, PlayerRecord?)
	local player = session.player
	-- ใน Studio โหมดทดสอบ: ลองครั้งเดียวแล้วเลิก (ไม่ต้องรอนาน)
	local maxAttempts = if STUDIO_UNSAVED then 1 else DataConfig.LoadRetries
	local status = "error"
	for attempt = 1, maxAttempts do
		local record: PlayerRecord?
		status, record = tryLoad(player.UserId)
		if status == "ok" and record ~= nil then
			return "ok", record
		end
		if status == "newer" then
			return status, nil -- รอก็ไม่หาย
		end
		if session.leaving or player.Parent == nil then
			return status, nil -- ผู้เล่นออกไปแล้ว เลิกลอง
		end
		if attempt < maxAttempts then
			task.wait(DataConfig.LoadRetryDelaySeconds)
		end
	end
	return status, nil
end

-- ===== เซฟ =====
-- ตัวเซฟจริง (ถูกเรียกใต้ pcall เสมอ จึงไม่ทำให้ flag ค้าง)
local function doSave(session: Session, release: boolean): boolean
	local key = DataConfig.KeyPrefix .. session.player.UserId
	local snapshot: any = deepCopy(session.data) -- ถ่ายภาพข้อมูล ณ ตอนนี้
	session.dirty = false
	local savedOk = false

	for attempt = 1, DataConfig.SaveRetries do
		local lostLock = false
		local success, err = pcall(function()
			store:UpdateAsync(key, function(old: any)
				lostLock = false
				-- เซฟได้เฉพาะเมื่อ record เดิมยังเป็นล็อกของเซิร์ฟเวอร์นี้เท่านั้น
				-- (ไม่มี record / ไม่มีล็อก / ล็อกของเซิร์ฟเวอร์อื่น = เราถูกรับช่วงไปแล้ว → ห้ามทับ)
				if type(old) ~= "table" or old.lockJobId ~= JOB_ID then
					lostLock = true
					return nil
				end
				if type(old.dataVersion) == "number" and old.dataVersion > DataConfig.CurrentVersion then
					lostLock = true
					return nil
				end
				local toSave: any = deepCopy(snapshot)
				if release then
					toSave.lockJobId = nil
					toSave.lockTime = nil
				else
					toSave.lockJobId = JOB_ID
					toSave.lockTime = os.time()
				end
				return toSave
			end)
		end)
		if success and not lostLock then
			savedOk = true
			break
		end
		if success and lostLock then
			warn(
				"[PlayerData] เสียล็อกข้อมูลของ UserId",
				session.player.UserId,
				"— หยุดเซฟเพื่อไม่ให้ทับข้อมูลเซิร์ฟเวอร์อื่น"
			)
			session.saveable = false
			session.message = MSG_LOST_LOCK
			pushToOwner(session)
			return false
		end
		warn(
			"[PlayerData] เซฟไม่สำเร็จ ครั้งที่",
			attempt,
			"UserId",
			session.player.UserId,
			err
		)
		if attempt < DataConfig.SaveRetries then
			task.wait(DataConfig.SaveRetryDelaySeconds)
		end
	end

	if savedOk then
		session.lastSaveClock = os.clock()
		if release then
			session.released = true
		end
	else
		session.dirty = true -- ยังไม่ได้เซฟ ให้รอบหน้าลองใหม่
	end
	return savedOk
end

-- release=true: เซฟครั้งสุดท้ายแล้วปล่อยล็อก (ใช้ตอนออกเกม/ปิดเซิร์ฟเวอร์)
local function saveSession(session: Session, release: boolean): boolean
	-- รอถ้ากำลังเซฟอยู่ (กันเขียนซ้อน) แต่มีเวลาหมด ไม่รอตลอดไป
	local waitDeadline = os.clock() + DataConfig.SaveWaitTimeoutSeconds
	while session.saving do
		if os.clock() > waitDeadline then
			warn(
				"[PlayerData] รอเซฟที่ค้างอยู่เกินเวลา UserId",
				session.player.UserId
			)
			return false
		end
		task.wait()
	end
	if session.released then
		return true
	end
	if not session.saveable then
		return false
	end

	session.saving = true
	local success, result = pcall(doSave, session, release)
	session.saving = false -- รีเซ็ตทุกทางออก แม้ doSave error
	if not success then
		warn("[PlayerData] saveSession error UserId", session.player.UserId, result)
		session.dirty = true
		return false
	end
	if release and not result then
		warn(
			"[PlayerData] เซฟครั้งสุดท้ายไม่สำเร็จ ข้อมูลอาจสูญเสีย UserId",
			session.player.UserId
		)
	end
	return result
end

-- ===== ผู้เล่นเข้า/ออก =====
local function onPlayerAdded(player: Player)
	if sessions[player] ~= nil or player.Parent == nil then
		return
	end
	local session: Session = {
		player = player,
		data = newDefaultRecord(),
		loaded = false,
		saveable = false,
		unsavedTest = false,
		saving = false,
		dirty = false,
		lastSaveClock = os.clock(),
		leaving = false,
		released = false,
		message = nil,
	}
	sessions[player] = session

	local status, record = loadWithRetries(session)
	if status == "ok" and record ~= nil then
		session.data = record
		session.saveable = true
	else
		-- โหลดไม่สำเร็จ: ใช้ข้อมูลเริ่มต้นในหน่วยความจำ แต่ไม่เซฟเด็ดขาด
		session.saveable = false
		if STUDIO_UNSAVED then
			session.unsavedTest = true
			session.message = MSG_STUDIO_UNSAVED
		elseif status == "locked" then
			session.message = MSG_LOCKED
		elseif status == "newer" then
			session.message = MSG_NEW_VERSION
		else
			session.message = MSG_LOAD_FAILED
		end
		warn(
			"[PlayerData] ผู้เล่น",
			player.Name,
			"โหลดไม่สำเร็จ สถานะ:",
			status,
			"— ไม่เซฟรอบนี้"
		)
	end
	session.loaded = true
	pushToOwner(session)

	-- ผู้เล่นออกระหว่างโหลด → เซฟ/ปล่อยล็อกที่นี่
	if session.leaving then
		if session.saveable then
			saveSession(session, true)
		end
		sessions[player] = nil
	end
end

local function onPlayerRemoving(player: Player)
	lastGetMyData[player] = nil
	local session = sessions[player]
	if session == nil then
		return
	end
	session.leaving = true
	if not session.loaded then
		return -- onPlayerAdded จะจัดการเองเมื่อโหลดเสร็จ
	end
	if session.saveable then
		saveSession(session, true)
	end
	sessions[player] = nil
end

function PlayerData.init()
	dataChanged = Remotes.remoteEvent("DataChanged")

	-- client เรียกตอนเริ่มเพื่อขอข้อมูลของตัวเอง (กันพลาดอีเวนต์ที่ยิงก่อน client พร้อม)
	local getMyData = Remotes.remoteFunction("GetMyData")
	getMyData.OnServerInvoke = function(player: Player)
		local now = os.clock()
		local last = lastGetMyData[player]
		if last ~= nil and now - last < Config.Shop.RequestCooldownSeconds then
			return nil
		end
		lastGetMyData[player] = now
		local session = sessions[player]
		if session == nil or not session.loaded then
			return nil
		end
		return buildPayload(session)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- เซฟอัตโนมัติ: เซฟเมื่อข้อมูลเปลี่ยน หรือครบรอบต่ออายุล็อก (ข้ามถ้ากำลังเซฟอยู่)
	task.spawn(function()
		while not closing do
			task.wait(DataConfig.AutosaveSeconds)
			for _, session in sessions do
				if session.loaded and session.saveable and not session.leaving and not session.saving then
					local needRenew = (os.clock() - session.lastSaveClock) >= DataConfig.LockRenewSeconds
					if session.dirty or needRenew then
						task.spawn(saveSession, session, false)
					end
				end
			end
		end
	end)

	-- ปิดเซิร์ฟเวอร์: เซฟทุกคนพร้อมกัน แล้วรอจนเสร็จ (หรือหมดเวลา)
	game:BindToClose(function()
		closing = true
		local pending = 0
		for _, session in sessions do
			if session.loaded and session.saveable then
				pending += 1
				task.spawn(function()
					local ok, err = pcall(saveSession, session, true)
					if not ok then
						warn("[PlayerData] BindToClose เซฟ error UserId", session.player.UserId, err)
					end
					pending -= 1 -- ลดตัวนับเสมอ แม้ error
				end)
			end
		end
		local deadline = os.clock() + DataConfig.ShutdownMaxWaitSeconds
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

-- ===== ฟังก์ชันให้ระบบอื่นเรียก (ฝั่งเซิร์ฟเวอร์เท่านั้น) =====

-- คืนข้อมูลผู้เล่น (nil ถ้ายังโหลดไม่เสร็จ) — ห้ามแก้ตรง ๆ ให้ใช้ฟังก์ชันด้านล่าง
function PlayerData.get(player: Player): PlayerRecord?
	local session = sessions[player]
	if session == nil or not session.loaded then
		return nil
	end
	return session.data
end

-- ข้อมูลนี้เซฟลง DataStore ได้จริงไหม (false = โหลดพลาด)
function PlayerData.isSaveable(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.loaded and session.saveable
end

-- ซื้อ/แลกได้ไหม: เซฟได้จริง หรืออยู่ในโหมดทดสอบ Studio (เล่นในหน่วยความจำ ไม่เซฟ)
function PlayerData.canTransact(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.loaded and (session.saveable or session.unsavedTest)
end

local function isPositiveInteger(n: any): boolean
	return type(n) == "number" and n == n and n >= 1 and n < 2 ^ 31 and n % 1 == 0
end

function PlayerData.addMoney(player: Player, amount: number): boolean
	local session = sessions[player]
	if session == nil or not session.loaded or not isPositiveInteger(amount) then
		return false
	end
	session.data.money += amount
	markChanged(session)
	return true
end

function PlayerData.spendMoney(player: Player, amount: number): boolean
	local session = sessions[player]
	if session == nil or not session.loaded or not isPositiveInteger(amount) then
		return false
	end
	if session.data.money < amount then
		return false
	end
	session.data.money -= amount
	markChanged(session)
	return true
end

-- เพิ่มขนม: เกินเพดาน (15) แปลงส่วนเกินเป็นเงินอัตโนมัติห่อละ 25
-- คืน (ขนมที่เก็บได้จริง, เงินที่ได้จากส่วนเกิน)
function PlayerData.addSnacks(player: Player, amount: number): (number, number)
	local session = sessions[player]
	if session == nil or not session.loaded or not isPositiveInteger(amount) then
		return 0, 0
	end
	local room = Config.Snacks.MaxStored - session.data.snacks
	local stored = math.min(amount, math.max(room, 0))
	local overflow = amount - stored
	session.data.snacks += stored
	local bonusMoney = overflow * Config.Snacks.ExchangeMoney
	session.data.money += bonusMoney
	markChanged(session)
	return stored, bonusMoney
end

-- ลดขนม (ใช้ตอนแลกเป็นเงิน — ผู้เรียกเป็นคนเพิ่มเงินเอง)
function PlayerData.removeSnacks(player: Player, amount: number): boolean
	local session = sessions[player]
	if session == nil or not session.loaded or not isPositiveInteger(amount) then
		return false
	end
	if session.data.snacks < amount then
		return false
	end
	session.data.snacks -= amount
	markChanged(session)
	return true
end

-- เพิ่มสถิติ (เฉพาะคีย์ที่รู้จัก) — ไม่เปลี่ยนรูปแบบข้อมูลที่เซฟ
function PlayerData.addStat(player: Player, key: string, amount: number): boolean
	local session = sessions[player]
	if session == nil or not session.loaded or not isPositiveInteger(amount) then
		return false
	end
	local stats = session.data.stats
	if key == "monkeysKilled" then
		stats.monkeysKilled += amount
	elseif key == "missionsCompleted" then
		stats.missionsCompleted += amount
	else
		return false
	end
	markChanged(session)
	return true
end

function PlayerData.hasGun(player: Player, gunId: string): boolean
	local session = sessions[player]
	if session == nil or not session.loaded then
		return false
	end
	return table.find(session.data.ownedGuns, gunId) ~= nil
end

function PlayerData.addGun(player: Player, gunId: string): boolean
	local session = sessions[player]
	if session == nil or not session.loaded or Config.Guns[gunId] == nil then
		return false
	end
	if table.find(session.data.ownedGuns, gunId) ~= nil then
		return false
	end
	table.insert(session.data.ownedGuns, gunId)
	markChanged(session)
	return true
end

return PlayerData
