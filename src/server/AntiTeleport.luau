--!strict
-- AntiTeleport: กันเทเลพอร์ต/วิ่งเร็วเกินจริง (ฝั่งเซิร์ฟเวอร์ล้วน) — ตัวละครของผู้เล่นคุมฟิสิกส์ที่ client จึงต้องตรวจตำแหน่งเอง
-- - ทุก Config.AntiCheat.TickSeconds วิ ตรวจผู้ร่วมภารกิจที่ root "ไม่ถูกตรึง": ระยะแนวราบที่ขยับต่อรอบต้องไม่เกิน
--   (WalkSpeed × SpeedMultiplier + SlackStuds) × dt · เกิน → ดึงกลับตำแหน่งดีล่าสุด (lastGoodPos) + นับ strike
--   (แนวดิ่งไม่จำกัด: ตกจากที่สูง/กระโดดได้ปกติ) · คนล้มใช้ DownedWalkSpeed
-- - ข้ามการตรวจเมื่อ: root.Anchored (หนังสติ๊ก/กลับเข้าแมพ/มัดตัวบนบั้งไฟ/ยิงบั้งไฟ) · คนตาย · ไม่ได้อยู่ในภารกิจ
--   · รอบแรกหลังปลดตรึง (ตำแหน่งลงพื้นที่เซิร์ฟเวอร์วางให้ถือว่าถูกต้อง) · หลังเรียก AntiTeleport.reset
-- - ใช้ WalkSpeed จาก Config ไม่อ่านจาก Humanoid (client แก้ค่าในเครื่องตัวเองได้)
-- - ตั้งใจให้หลวม ไม่ให้ดึงคนเล่นปกติกลับ (วิ่ง ลาดเอียง กระโดด เน็ตหน่วง) · เปิดดูจำนวน strike ได้ที่ Config.Debug.AntiCheat

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerHealth = require(script.Parent.PlayerHealth)

local AC = Config.AntiCheat

type State = {
	character: Model,
	lastPos: Vector3,
	lastClock: number,
	wasAnchored: boolean,
	resetPending: boolean,
	strikes: number,
}

local AntiTeleport = {}

local states: { [Player]: State } = {}
local isActive: (Player) -> boolean = function(_player: Player): boolean
	return false
end

-- ตำแหน่งเปลี่ยนอย่างถูกต้อง (เซิร์ฟเวอร์ย้ายเอง): รอบหน้ารับตำแหน่งใหม่เป็นจุดตั้งต้น ไม่ตรวจระยะ
function AntiTeleport.reset(player: Player)
	local state = states[player]
	if state ~= nil then
		state.resetPending = true
	end
end

local function check(player: Player, now: number)
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if character == nil or root == nil or not root:IsA("BasePart") then
		states[player] = nil
		return
	end
	local position = root.Position
	local state = states[player]
	if state == nil or state.character ~= character then
		-- ตัวละครใหม่ (เกิดใหม่): เริ่มนับจากตำแหน่งที่เกิด
		states[player] = {
			character = character,
			lastPos = position,
			lastClock = now,
			wasAnchored = root.Anchored,
			resetPending = false,
			strikes = 0,
		}
		return
	end

	local dt = math.min(now - state.lastClock, AC.MaxDtSeconds)
	state.lastClock = now

	if root.Anchored then
		state.wasAnchored = true
		state.lastPos = position
		return
	end
	if state.wasAnchored or state.resetPending then
		state.wasAnchored = false
		state.resetPending = false
		state.lastPos = position
		return
	end
	if not isActive(player) then
		state.lastPos = position
		return
	end
	local healthState = PlayerHealth.getState(player)
	if healthState == "Dead" then
		state.lastPos = position
		return
	end

	local speed = if healthState == "Downed" then Config.Player.DownedWalkSpeed else Config.Player.WalkSpeed
	local allowed = (speed * AC.SpeedMultiplier + AC.SlackStuds) * dt
	local flat = Vector3.new(position.X - state.lastPos.X, 0, position.Z - state.lastPos.Z)
	if flat.Magnitude > allowed then
		state.strikes += 1
		if Config.Debug.AntiCheat then
			warn(
				string.format(
					"[AntiTeleport] %s ขยับ %.1f stud ใน %.2f วิ (เพดาน %.1f) strike #%d — ดึงกลับ",
					player.Name,
					flat.Magnitude,
					dt,
					allowed,
					state.strikes
				)
			)
		end
		-- ดึงกลับตำแหน่งดีล่าสุด คงทิศที่หัน · ความเร็วเป็นศูนย์
		character:PivotTo(CFrame.new(state.lastPos) * (root.CFrame - root.CFrame.Position))
		root.AssemblyLinearVelocity = Vector3.zero
		return
	end
	state.lastPos = position
end

-- isActiveFn(player) → true เมื่อผู้เล่นคนนี้อยู่ในภารกิจ (ช่วงที่ต้องตรวจ) — Mission เป็นคนตัดสิน
function AntiTeleport.init(isActiveFn: (Player) -> boolean)
	isActive = isActiveFn
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(AC.TickSeconds)
			-- ครอบด้วย xpcall: ถ้ารอบใดพัง ลูปต้องไม่ตาย · แต่ละคนแยก pcall กันคนหนึ่งพังแล้วคนอื่นไม่ถูกตรวจ
			local ok, err = xpcall(function()
				local now = os.clock()
				for _, player in Players:GetPlayers() do
					local okPlayer, errPlayer = pcall(check, player, now)
					if not okPlayer then
						warn("[AntiTeleport] check error:", errPlayer)
					end
				end
			end, debug.traceback)
			if not ok then
				warn("[AntiTeleport] loop error:", err)
			end
		end
	end)
end

return AntiTeleport
