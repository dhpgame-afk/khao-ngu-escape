--!strict
-- Config: ตัวเลขทั้งหมดของเกมอยู่ที่ไฟล์นี้ไฟล์เดียว (ห้ามเขียนตัวเลขเกมกระจายในโค้ดอื่น)
-- ค่าที่มี TODO(ยังไม่ระบุ) คือค่าที่ project.md ยังไม่ได้กำหนด — เป็นค่าสมมติ ปรับตอนทดสอบ

export type GunDef = {
	id: string,
	displayName: string, -- ชื่อที่แสดงให้ผู้เล่นเห็น (ภาษาไทย)
	price: number,
	damagePerPellet: number,
	pellets: number, -- จำนวนเม็ดต่อการยิง 1 ครั้ง
	magSize: number,
	automatic: boolean,
	fireRate: number, -- นัดต่อวินาที
}

local Guns: { [string]: GunDef } = {
	BBPistol = {
		id = "BBPistol",
		displayName = "ปืนพก BB",
		price = 0, -- ฟรี (ทุกคนมีตั้งแต่แรก)
		damagePerPellet = 25,
		pellets = 1,
		magSize = 12,
		automatic = false,
		fireRate = 3, -- TODO(ยังไม่ระบุ): อัตรายิง ปรับตอนทดสอบ
	},
	BBShotgun = {
		id = "BBShotgun",
		displayName = "ลูกซอง BB",
		price = 300, -- ค่าเสนอ
		damagePerPellet = 25,
		pellets = 5,
		magSize = 6, -- TODO(ยังไม่ระบุ): ขนาดแม็กลูกซอง
		automatic = false,
		fireRate = 1, -- TODO(ยังไม่ระบุ): อัตรายิง
	},
	BBSmg = {
		id = "BBSmg",
		displayName = "ปืนกล BB",
		price = 800, -- ค่าเสนอ
		damagePerPellet = 25,
		pellets = 1,
		magSize = 30,
		automatic = true,
		fireRate = 10, -- TODO(ยังไม่ระบุ): อัตรายิงรัว
	},
}

local Config = {
	MaxPlayers = 4,

	Player = {
		MaxHealth = 100,
		DownedSeconds = 30, -- ล้มแล้วไม่มีใครชุบใน 30 วิ → ตาย
		RespawnSeconds = 40, -- ตายแล้วครบ 40 วิ ไปหนังสติ๊กเลือกเป้ายิงตัวเอง
		PhoneCallSeconds = 5, -- โทรเรียกเพื่อนกลับ ระหว่างโทรยิงไม่ได้
		RegenPerSecond = 2, -- TODO(ยังไม่ระบุ): อัตราฟื้นเลือดเอง
		RegenDelaySeconds = 5, -- TODO(ยังไม่ระบุ): ไม่โดนตีนานเท่าไรถึงเริ่มฟื้น
		WalkSpeed = 16, -- ความเร็วเดินปกติ (ค่ามาตรฐาน Roblox)
		DownedHealth = 100, -- TODO(ยังไม่ระบุ — ค่าที่ตีความ): "เลือดตอนล้ม" ที่ลิงตีลดได้ หมดแล้วตายทันที
		DownedWalkSpeed = 5, -- TODO(ยังไม่ระบุ): คนล้มคลานช้ากว่าปกติเท่าไร
		ReviveRange = 8, -- TODO(ยังไม่ระบุ): ยืนห่างคนล้มไม่เกินกี่ stud ถึงชุบได้
		ReviveHoldSeconds = 3, -- TODO(ยังไม่ระบุ): กดค้างชุบนานกี่วิ
		ReviveHealthFraction = 0.5, -- TODO(ยังไม่ระบุ): ชุบแล้วได้เลือดกี่ส่วนของเต็ม
	},

	Monkey = {
		MaxHealth = 50,
		AttackDamage = 20,
		DownedDamageMultiplier = 0.5, -- ลิงตีคนที่ล้ม ความเสียหายลด 50%
		AttackIntervalSeconds = 1.5, -- TODO(ยังไม่ระบุ): ความถี่การตี
		NestCount = 4,
		NestBaseMax = 5, -- ปกติรังละไม่เกิน 5 ตัว
		ReinforceIntervalSeconds = 10, -- เริ่มโจมตีรัง → ครบ 10 วิเรียกพวก และเรียกซ้ำทุก 10 วิ
		ReinforceCount = 5, -- เรียกครั้งละ 5 ตัว
		ReinforceMaxPerNest = 15, -- เรียกเพิ่มรวมไม่เกิน 15 ตัวต่อรัง
		CorpseSinkDelaySeconds = 10, -- ตายแล้ว 10 วิ จมพื้นหายไป
		MoneyPerKill = 5, -- TODO(ยังไม่ระบุ): เงินต่อลิง 1 ตัว
		MaxTotal = 80, -- TODO(ยังไม่ระบุ): เพดานลิงทั้งแมพ (4 รัง × 20) ปรับตามความลื่นบนมือถือ
		NestWanderRadius = 30, -- TODO(ยังไม่ระบุ): รัศมีเดินวนรอบรัง (stud)
		SightDistance = 60, -- TODO(ยังไม่ระบุ): ระยะที่ลิงเห็นผู้เล่น (stud)
		AlertSightDistance = 150, -- TODO(ยังไม่ระบุ): ระยะเห็นเมื่อรังถูกโจมตีแล้ว
		AttackRange = 5, -- TODO(ยังไม่ระบุ): ระยะตี (stud)
		LeashDistance = 120, -- TODO(ยังไม่ระบุ): ไกลรังเกินนี้ → กลับรัง
		SleepDistance = 200, -- TODO(ยังไม่ระบุ): ไกลผู้เล่นทุกคนเกินนี้ → ลิงหยุดคิด (ประหยัดเครื่อง)
		AiTickSeconds = 0.25, -- อัปเดต AI เป็นรอบ ไม่ใช่ทุกเฟรม
		WalkSpeed = 8, -- TODO(ยังไม่ระบุ): ความเร็วเดินวนรัง
		ChaseSpeed = 16, -- TODO(ยังไม่ระบุ): ความเร็ววิ่งไล่
		SinkSeconds = 2, -- ใช้เวลาจมพื้นกี่วินาที
		SinkDepth = 5, -- จมลงกี่ stud
	},

	Guns = Guns,
	DefaultGunId = "BBPistol",

	Firecracker = {
		AreaDamage = 50,
		PerPlayer = 3,
		Radius = 12, -- TODO(ยังไม่ระบุ): รัศมีวงระเบิด (stud)
		FuseSeconds = 1.5, -- TODO(ยังไม่ระบุ): ขว้างแล้วระเบิดหลังกี่วิ
		ThrowSpeed = 55, -- TODO(ยังไม่ระบุ): ความเร็วขว้าง (stud/วิ)
		ThrowCooldownSeconds = 0.8, -- TODO(ยังไม่ระบุ)
	},

	Broom = {
		Damage = 25, -- ใช้ไม่จำกัด
		SwingCooldownSeconds = 0.6, -- TODO(ยังไม่ระบุ)
		Range = 7, -- TODO(ยังไม่ระบุ): ระยะฟาด (stud)
		ArcHalfAngleDegrees = 60, -- TODO(ยังไม่ระบุ): มุมฟาดครึ่งหนึ่งของแต่ละข้าง
	},

	Combat = {
		MaxRange = 300, -- TODO(ยังไม่ระบุ): ระยะกระสุนไกลสุด (stud)
		ReloadSeconds = 1.5, -- TODO(ยังไม่ระบุ): เวลาเปลี่ยนแม็ก
		ShotgunSpreadDegrees = 6, -- TODO(ยังไม่ระบุ): มุมกระจายของลูกซอง
		CarrySpreadDegrees = 8, -- TODO(ยังไม่ระบุ): ถือของอยู่ ยิงแบบไม่เล็ง = ศูนย์กว้างขึ้น (ใช้ตอนทำระบบถือของ)
		ActionMinIntervalSeconds = 0.03, -- กัน spam remote ยิง/ขว้าง/ฟาด/ชุบ
		MenuMinIntervalSeconds = 0.2, -- กัน spam remote เปลี่ยนช่อง/เปลี่ยนแม็ก
		FireRateTolerance = 0.85, -- ยอมให้ยิงเร็วกว่ากำหนดนิดหน่อย (ชดเชยเน็ตกระตุก)
		TracerSeconds = 0.08, -- เส้นกระสุนอยู่นานเท่านี้
	},

	Hud = {
		AimAssistDegrees = 7, -- TODO(ยังไม่ระบุ): กรวย aim assist บนมือถือ
		AimAssistRange = 150, -- TODO(ยังไม่ระบุ)
		AimAssistStrength = 0.6, -- TODO(ยังไม่ระบุ): 0 = ไม่ช่วย, 1 = ล็อกเต็ม
		NormalFov = 70,
		AimFov = 45,
	},

	Snacks = {
		PerMission = 4,
		TempHealth = 250,
		TempHealthSeconds = 10,
		MaxStored = 15, -- เก็บข้ามเกมได้สูงสุด
		ExchangeMoney = 25, -- แลกห่อละ 25 เงิน (เกินเพดานแลกเป็นเงินอัตโนมัติด้วยอัตราเดียวกัน)
	},

	Rocket = {
		CountdownSeconds = 60,
		LeftBehindPenalty = 0.05, -- ถูกทิ้ง ได้เงินน้อยกว่าเพื่อน 5%
	},

	Rewards = {
		MissionComplete = 200, -- TODO(ยังไม่ระบุ): เงินก้อนใหญ่เมื่อภารกิจสำเร็จ
		MissingItemsMultiplier = 0.5, -- TODO(ยังไม่ระบุ): หนีโดยไม่มีถุงเงิน/ขนม รางวัลคูณเท่านี้
	},

	Data = {
		StoreName = "PlayerData_v1",
		KeyPrefix = "u_",
		CurrentVersion = 1,
		AutosaveSeconds = 120,
		LoadRetries = 5,
		LoadRetryDelaySeconds = 3,
		SaveRetries = 4,
		SaveRetryDelaySeconds = 2,
		LockStaleSeconds = 600, -- ล็อกเก่ากว่า 10 นาทีถือว่าค้าง (เซิร์ฟเวอร์เดิมน่าจะล่มไปแล้ว)
		LockRenewSeconds = 300, -- ข้อมูลไม่เปลี่ยนก็ยังเซฟเพื่อต่ออายุล็อกทุก 5 นาที
		SaveWaitTimeoutSeconds = 40, -- รอเซฟที่ค้างอยู่ได้นานสุดเท่านี้
		StudioAllowUnsaved = true, -- เฉพาะใน Studio: ต่อ DataStore ไม่ได้ก็เล่นทดสอบได้ แต่ไม่เซฟ
		ShutdownMaxWaitSeconds = 25,
	},

	Shop = {
		RequestCooldownSeconds = 0.5, -- จำกัดความถี่คำขอต่อผู้เล่น
	},
}

-- แช่แข็งทั้งตาราง (รวมตารางย่อย) กันโค้ดอื่นแอบแก้ค่า
local function deepFreeze(t: { [any]: any })
	for _, v in t do
		if type(v) == "table" then
			deepFreeze(v)
		end
	end
	table.freeze(t)
end
deepFreeze(Config :: any)

return Config
