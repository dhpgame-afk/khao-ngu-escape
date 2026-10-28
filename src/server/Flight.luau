--!strict
-- Flight: บินผู้เล่นตามเส้นโค้ง (ใช้ร่วมกันระหว่างหนังสติ๊กยิงเข้าแมพตอนเริ่มภารกิจ กับกลับเข้าแมพหลังตาย)
-- - ไม่พึ่งฟิสิกส์: ตรึง HumanoidRootPart (Anchored) แล้วขยับ CFrame เองทุกเฟรม จึงไม่ติดภูมิประเทศ
-- - โมดูลนี้ "ไม่ตัดสินใจ" เรื่องกติกา: ผู้เรียกเป็นคนตรึงตัว ตรวจว่ายังบินต่อได้ไหม (stillValid) และปล่อยตัวตอนลง

local RunService = game:GetService("RunService")

local AntiTeleport = require(script.Parent.AntiTeleport)

local Flight = {}

export type Leg = {
	player: Player,
	character: Model,
	root: BasePart,
	startPos: Vector3,
	endPos: Vector3,
	facing: Vector3, -- ทิศที่ตัวละครหันตลอดการบิน (แนวราบ ห้ามเป็นศูนย์)
}

-- จุดบนเส้นโค้ง: เส้นตรงจากจุดเริ่มถึงจุดลง + ยกขึ้นเป็นพาราโบลา (สูงสุดตรงกลางทาง)
function Flight.arcPosition(startPos: Vector3, endPos: Vector3, alpha: number, peakHeight: number): Vector3
	local onLine = startPos:Lerp(endPos, alpha)
	return onLine + Vector3.new(0, peakHeight * 4 * alpha * (1 - alpha), 0)
end

-- ตัวละครของขาบินนี้ยังเป็นตัวเดิมและยังอยู่ในเกมไหม (เกิดใหม่/ถูกลบ = ไม่ขยับต่อ)
local function legIsAlive(leg: Leg): boolean
	return leg.root.Parent ~= nil and leg.player.Character == leg.character
end

-- บินทุกขาพร้อมกันจนครบ seconds · คืน true ถ้าบินครบ · false ถ้า stillValid() เป็น false ระหว่างทาง
-- onStep(alpha) เรียกทุกเฟรมหลังขยับผู้เล่น (Mission ใช้ขยับตะกร้าอาหารตามโค้งเดียวกัน)
-- ต้องเรียกจากเธรดที่ yield ได้ (ใช้ Heartbeat:Wait) และควรครอบด้วย pcall ที่ผู้เรียก
function Flight.run(
	legs: { Leg },
	seconds: number,
	peakHeight: number,
	stillValid: () -> boolean,
	onStep: ((alpha: number) -> ())?
): boolean
	local elapsed = 0
	while elapsed < seconds do
		local dt = RunService.Heartbeat:Wait()
		if not stillValid() then
			return false
		end
		elapsed += dt
		local alpha = math.min(elapsed / seconds, 1)
		for _, leg in legs do
			if legIsAlive(leg) then
				local position = Flight.arcPosition(leg.startPos, leg.endPos, alpha, peakHeight)
				leg.root.CFrame = CFrame.lookAt(position, position + leg.facing)
			end
		end
		if onStep ~= nil then
			onStep(alpha)
		end
	end
	return true
end

-- ลงพื้น: วางที่จุดลงพอดี หยุดความเร็ว และปลดตรึง (ไม่มีดาเมจตกจากที่สูง เพราะเกมไม่มีระบบเสียเลือดจากการตก)
function Flight.land(leg: Leg)
	if legIsAlive(leg) then
		leg.root.CFrame = CFrame.lookAt(leg.endPos, leg.endPos + leg.facing)
		leg.root.AssemblyLinearVelocity = Vector3.zero
		leg.root.Anchored = false
		AntiTeleport.reset(leg.player) -- ตำแหน่งลงพื้นเซิร์ฟเวอร์วางให้ ไม่ใช่การเทเลพอร์ตของผู้เล่น
	end
end

-- ขอให้ client ของผู้เล่นโหลดแมพรอบจุด position ล่วงหน้า (StreamingEnabled) กันลงบนพื้นที่ยังไม่โหลด (ตกทะลุพื้น)
-- yield จนโหลดเสร็จหรือหมดเวลา · ล้มเหลว = แค่เตือน ไม่หยุดการบิน
function Flight.streamAround(player: Player, position: Vector3, timeoutSeconds: number)
	local ok, err = pcall(function()
		player:RequestStreamAroundAsync(position, timeoutSeconds)
	end)
	if not ok then
		warn("[Flight] RequestStreamAroundAsync ล้มเหลว", player.Name, err)
	end
end

return Flight
