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

-- ของที่ต้องถือ: ภาพประกอบจาก Part ล้วน ๆ (ไม่ใช้ asset) · ชิ้นแรกในรายการ parts คือ "Body" (ชิ้นหลักที่ weld กับตัวละคร)
export type ItemPartDef = {
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	offset: Vector3, -- ตำแหน่งเทียบกึ่งกลางของ Body
	color: Color3,
	material: Enum.Material,
}

export type ItemDef = {
	displayName: string, -- ชื่อที่ผู้เล่นเห็น (ภาษาไทย)
	restHeight: number, -- ตอนวางบนพื้น กึ่งกลาง Body สูงจากพื้นเท่านี้
	holdOffset: Vector3, -- ตอนถือ: ตำแหน่งเทียบ HumanoidRootPart (หน้าตัว = -Z)
	parts: { ItemPartDef },
}

local CarryItems: { [string]: ItemDef } = {
	FoodBasket = {
		displayName = "ตะกร้าอาหาร",
		restHeight = 0.8,
		holdOffset = Vector3.new(0, 0.3, -2.6),
		parts = {
			{
				name = "Body",
				shape = Enum.PartType.Block,
				size = Vector3.new(3, 1.6, 3),
				offset = Vector3.zero,
				color = Color3.fromRGB(176, 124, 66),
				material = Enum.Material.Wood,
			},
			{
				name = "Rim",
				shape = Enum.PartType.Block,
				size = Vector3.new(3.3, 0.25, 3.3),
				offset = Vector3.new(0, 0.85, 0),
				color = Color3.fromRGB(140, 95, 50),
				material = Enum.Material.Wood,
			},
			{
				name = "FruitRed",
				shape = Enum.PartType.Ball,
				size = Vector3.new(1.1, 1.1, 1.1),
				offset = Vector3.new(-0.7, 1.2, 0.3),
				color = Color3.fromRGB(220, 60, 50),
				material = Enum.Material.SmoothPlastic,
			},
			{
				name = "FruitGreen",
				shape = Enum.PartType.Ball,
				size = Vector3.new(1, 1, 1),
				offset = Vector3.new(0.6, 1.15, -0.5),
				color = Color3.fromRGB(90, 170, 70),
				material = Enum.Material.SmoothPlastic,
			},
			{
				name = "FruitYellow",
				shape = Enum.PartType.Ball,
				size = Vector3.new(0.9, 0.9, 0.9),
				offset = Vector3.new(0.4, 1.15, 0.8),
				color = Color3.fromRGB(250, 210, 60),
				material = Enum.Material.SmoothPlastic,
			},
		},
	},
	MoneyBag = {
		displayName = "ถุงเงิน",
		restHeight = 0.9,
		holdOffset = Vector3.new(0.8, 0.2, -1.8),
		parts = {
			{
				name = "Body",
				shape = Enum.PartType.Ball,
				size = Vector3.new(1.8, 1.8, 1.8),
				offset = Vector3.zero,
				color = Color3.fromRGB(200, 170, 110),
				material = Enum.Material.Fabric,
			},
			{
				name = "Neck",
				shape = Enum.PartType.Block,
				size = Vector3.new(0.9, 0.5, 0.9),
				offset = Vector3.new(0, 1.0, 0),
				color = Color3.fromRGB(200, 170, 110),
				material = Enum.Material.Fabric,
			},
			{
				name = "Tie",
				shape = Enum.PartType.Block,
				size = Vector3.new(1.1, 0.25, 1.1),
				offset = Vector3.new(0, 0.8, 0),
				color = Color3.fromRGB(150, 40, 40),
				material = Enum.Material.Fabric,
			},
			{
				name = "Coin",
				shape = Enum.PartType.Block,
				size = Vector3.new(0.8, 0.8, 0.1),
				offset = Vector3.new(0, 0, -0.9),
				color = Color3.fromRGB(255, 200, 40),
				material = Enum.Material.Metal,
			},
		},
	},
	SnackPack = {
		displayName = "ขนมพระ",
		restHeight = 0.6,
		holdOffset = Vector3.new(0, 0.3, -2.0),
		parts = {
			{
				name = "Body",
				shape = Enum.PartType.Block,
				size = Vector3.new(2, 1.2, 1.4),
				offset = Vector3.zero,
				color = Color3.fromRGB(250, 200, 80),
				material = Enum.Material.SmoothPlastic,
			},
			{
				name = "Pack2",
				shape = Enum.PartType.Block,
				size = Vector3.new(1.7, 0.9, 1.2),
				offset = Vector3.new(0.1, 1.0, 0),
				color = Color3.fromRGB(235, 120, 60),
				material = Enum.Material.SmoothPlastic,
			},
			{
				name = "Ribbon",
				shape = Enum.PartType.Block,
				size = Vector3.new(0.3, 1.3, 1.5),
				offset = Vector3.zero,
				color = Color3.fromRGB(200, 50, 50),
				material = Enum.Material.Fabric,
			},
		},
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

	-- ขอบเขตแมพ (ศูนย์กลาง (0,0) · เหนือ = -Z · ตะวันออก = +X) ≈ 970 × 640 stud
	Map = {
		HalfWidthStuds = 485, -- ครึ่งความกว้าง (ตะวันออก–ตะวันตก)
		HalfDepthStuds = 320, -- ครึ่งความลึก (เหนือ–ใต้)
		LandingMarginStuds = 40, -- จุดลงต้องห่างขอบแมพอย่างน้อยเท่านี้ (ไม่ให้ลงติดขอบ/นอกแมพ)
		MetersPerStud = 0.28, -- ใช้แสดงระยะไปเป้าหมายเป็นเมตร
		-- ชื่อจุดสำคัญใน Workspace.MapMarkers (Kuti = กุฏิ · Nest1–4 = รังลิง · RocketPad = ฐานบั้งไฟ)
		MarkerNames = { "Kuti", "Nest1", "Nest2", "Nest3", "Nest4", "RocketPad" },
	},

	-- ห้องรอ: แท่นลอยฟ้านอกแมพ + หนังสติ๊กยักษ์ (เซิร์ฟเวอร์สร้างเองถ้าไม่มี Workspace.Lobby)
	-- ถ้าเจ้าของทำห้องรอเองแล้วตั้งชื่อ Workspace.Lobby ระบบจะใช้ของเจ้าของ — ต้องมี Part ชื่อ
	-- "LobbySpawn" (จุดเกิด) และ "SlingshotPouch" (ถุงหนังสติ๊กที่ผู้เล่นยืนก่อนถูกยิง)
	Lobby = {
		Center = Vector3.new(0, 250, -700), -- กึ่งกลางแท่น (อยู่เหนือขอบแมพด้านเหนือ ที่ z = -320)
		FloorSize = Vector3.new(80, 2, 60),
		FloorColor = Color3.fromRGB(120, 130, 120),
		RailHeight = 14, -- สูงกว่าความสูงกระโดดปกติ (7.2) เพื่อกันกระโดดข้าม
		RailThickness = 1,
		RailTransparency = 0.5,
		RailColor = Color3.fromRGB(230, 200, 120),
		SpawnPadSize = Vector3.new(30, 1, 20),
		SpawnPadOffset = Vector3.new(0, 0, -8), -- จากกึ่งกลางแท่น
		SpawnPadColor = Color3.fromRGB(90, 170, 110),
		SpawnPadEdgeMargin = 3, -- ตอนสุ่มจุดเกิด ห่างขอบแผ่นเกิดอย่างน้อยเท่านี้
		StandHeight = 3.5, -- ความสูงของ HumanoidRootPart เหนือพื้นที่ยืน (ให้เท้าแตะพื้นพอดี)

		-- หนังสติ๊ก: ฐาน + เสา 2 ต้น + แถบยาง + ถุง (ประกอบจาก Part ล้วน ไม่ใช้ asset) ยิงไปทางใต้ (+Z)
		SlingshotOffset = Vector3.new(0, 0, 52), -- จากกึ่งกลางแท่นห้องรอ (ห่างกัน 10 stud กันเดินข้าม)
		SlingshotBaseSize = Vector3.new(40, 2, 24),
		SlingshotBaseColor = Color3.fromRGB(110, 90, 70),
		SlingshotPostSpacing = 24, -- ระยะห่างระหว่างเสา 2 ต้น
		SlingshotPostSize = Vector3.new(2, 18, 2),
		SlingshotPostZ = 4, -- เสาอยู่ล้ำไปทางใต้ของกึ่งกลางฐานเท่านี้
		SlingshotPostColor = Color3.fromRGB(139, 94, 52),
		SlingshotPouchOffset = Vector3.new(0, 8, -8), -- ถุงอยู่เหนือผิวฐาน และถอยไปทางเหนือ (ดึงยางไปข้างหลัง)
		SlingshotPouchSize = Vector3.new(14, 1, 6),
		SlingshotPouchColor = Color3.fromRGB(170, 120, 70),
		SlingshotBandThickness = 1,
		SlingshotBandColor = Color3.fromRGB(200, 60, 60),

		-- ผู้เล่นตกจากแท่น/หลุดออกนอกแท่น → เทเลพอร์ตกลับจุดเกิด
		BoundsCheckSeconds = 0.5,
		OutsideMarginStuds = 4, -- เลยขอบห้องรอไปเท่านี้ถือว่าหลุด
		FallResetBelowStuds = 15, -- ต่ำกว่าฐานห้องรอเท่านี้ถือว่าตก

		-- แผนที่ในหน้าจอห้องรอ: แบ่งเป็นช่องกริดให้หัวห้องแตะ (ไม่ต้องคำนวณพิกัดนิ้ว จึงไม่พลาดบนมือถือ)
		MapGridCols = 24,
		MapGridRows = 16,
	},

	-- ภารกิจ: หัวห้อง / พร้อม / นับถอยหลัง / จุดลง
	Mission = {
		MinPlayers = 1, -- ขั้นต่ำที่เริ่มได้ (สูงสุด = Config.MaxPlayers)
		ReadyCountdownSeconds = 3, -- ทุกคนพร้อมแล้วรอกี่วิก่อนยิง
		DefaultLandingOffset = Vector3.new(0, 0, 60), -- จุดลงเริ่มต้น = กุฏิ + ทางใต้ 60 stud (+Z = ใต้)
		ReadyMinIntervalSeconds = 0.3, -- จำกัดความถี่คำขอกดพร้อม
		LandingMinIntervalSeconds = 0.2, -- จำกัดความถี่คำขอเลือกจุดลง
		StateRequestMinIntervalSeconds = 0.5, -- จำกัดความถี่ที่ client ขอสถานะห้องรอ
		MarkerWaitSeconds = 10, -- รอ Workspace.MapMarkers ได้นานสุดเท่านี้ตอนเริ่มเซิร์ฟเวอร์
		ObjectsFolderName = "MissionObjects", -- โฟลเดอร์ใน Workspace เก็บของภารกิจ (ตะกร้า ฯลฯ) · ล้างตอนจบภารกิจ
		RespawnScatterStuds = 6, -- (ชั่วคราว) ตายแล้วเกิดใหม่กลางภารกิจ → เกิดสุ่มรอบจุดลงในรัศมีนี้
	},

	-- หนังสติ๊กยิงผู้เล่นเข้าแมพ
	Launch = {
		PrepSeconds = 1.0, -- ย้ายเข้าถุงแล้วรอก่อนปล่อยกี่วิ
		StreamTimeoutSeconds = 6, -- ระหว่างรอ ขอให้ client โหลดแมพรอบจุดลงล่วงหน้า (StreamingEnabled) รอนานสุดเท่านี้
		WatchdogExtraSeconds = 5, -- ถ้าผ่านเวลา (Prep + Stream + Flight) ไปอีกเท่านี้แล้วยังค้างที่ Launching → ยกเลิกภารกิจ
		FlightSeconds = 2.5, -- เวลาบิน (2–3 วิ)
		ArcPeakHeight = 140, -- ความสูงของวงโค้งเหนือเส้นตรงจากถุงถึงจุดลง (stud)
		SpreadStuds = 4, -- ผู้เล่นแต่ละคนห่างกัน (ตอนอยู่ในถุงและตอนลงพื้น)
		RaycastStartHeight = 1500, -- ยิงเรย์ลงหาพื้นจากความสูงนี้
		RaycastLength = 3000,
		FallbackGroundY = 50, -- ถ้าเรย์ไม่โดนพื้น (ไม่น่าเกิด) ใช้ความสูงนี้
		LandingRootHeight = 3.5, -- วาง HumanoidRootPart สูงจากพื้นเท่านี้ตอนลง
		BasketOffset = Vector3.new(0, 0, 10), -- ตะกร้าอาหารลงพื้นห่างจากจุดลงไปทางใต้เท่านี้ (บินตามโค้งเดียวกับผู้เล่น)
		BasketStartForward = 3, -- ตะกร้าเริ่มบินจากหน้าถุงหนังสติ๊ก (ไปทางจุดลง) เท่านี้ ไม่ทับตัวผู้เล่น
		BasketStartLift = 1.5, -- และยกสูงจากถุงเท่านี้
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

		-- ภาพไม้กวด (ประกอบจาก Part ล้วน ๆ ไม่ใช้ asset) — ไม่มีผลกับการคิดความเสียหาย
		HandleLength = 4.5, -- ความยาวด้าม (stud)
		HandleThickness = 0.25,
		HandleColor = Color3.fromRGB(139, 94, 52), -- ไม้
		BristleSize = Vector3.new(1.2, 1.5, 0.4), -- หัวไม้กวดรวมส่วนคอ (กว้าง × ยาว × หนา)
		BristleColor = Color3.fromRGB(222, 190, 100), -- ฟางดอกหญ้า
		NeckColor = Color3.fromRGB(170, 135, 70), -- ส่วนคอ/ตรงที่มัดฟาง (เข้มกว่า)
		NeckHeightFraction = 0.35, -- ส่วนคอสูงกี่ส่วนของหัวไม้กวด (ด้านบน แคบ) ที่เหลือคือชายฟางบานออก
		NeckWidthFraction = 0.5, -- ส่วนคอกว้างกี่ส่วนของชายฟาง
		GripFromTop = 1.2, -- จุดที่มือจับ วัดจากปลายด้านบนของด้าม
		GripTiltDegrees = 70, -- เอียงด้ามไปข้างหน้าจากแนวดิ่ง (ตอนแขนห้อยลง) · 70 = ปลายหัวไม้กวดชี้ไปข้างหน้า ไม่จิ้มพื้น
		GripOffsetR15 = Vector3.new(0, -0.2, 0), -- จุดจับบน RightHand
		GripOffsetR6 = Vector3.new(0, -1, 0), -- จุดจับบน Right Arm (ปลายแขน)
		SwingSeconds = 0.3, -- ท่าฟาดทั้งท่า
		SwingWindupDegrees = 110, -- ยกแขนขึ้นก่อนฟาดกี่องศา
		SwingStrikeDegrees = -15, -- ปลายท่าฟาด (ติดลบ = แขนปัดลงต่ำกว่าท่าห้อย)
		SwingWindupFraction = 0.3, -- ช่วงง้างเป็นกี่ส่วนของเวลาทั้งหมด
		SwingStrikeEndFraction = 0.7, -- ฟาดเสร็จที่กี่ส่วน (หลังจากนั้นกลับท่าเดิม)
		SwingBroomExtraFactor = 0.4, -- ไม้กวดหมุนรอบจุดจับเพิ่มอีก (เท่าของมุมแขน) ให้ปัดเป็นวงกว้าง
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

	-- ถือของ (ตะกร้าอาหาร / ถุงเงิน / ขนมพระ): ถือได้ทีละชิ้นต่อคน · ชิ้นละ 1 คนถือ
	Carry = {
		PickupRange = 8, -- ยืนห่างของไม่เกินกี่ stud ถึงหยิบได้ (TODO ยังไม่ระบุ: ปรับตอนทดสอบ)
		RangeTolerance = 3, -- เซิร์ฟเวอร์ยอมให้เกินระยะนี้อีกนิด (ชดเชยเน็ตหน่วง)
		PickupMinIntervalSeconds = 0.3,
		DropMinIntervalSeconds = 0.3,
		DropForwardStuds = 3, -- กดวางของ: วางห่างหน้าตัวเท่านี้ (ตายหรือออกเกม = วางตรงที่ยืน)
		DropRayStartUp = 2, -- เรย์หาพื้นรอบแรกเริ่มจากสูงกว่าจุดวางแค่นี้ (ระดับตัว ไม่เกาะหินที่ยื่นอยู่เหนือหัว)
		DropRayUp = 12, -- รอบสอง (ถ้ารอบแรกไม่โดน) เริ่มจากสูงเท่านี้
		VoidY = -50, -- พื้นที่เจอต่ำกว่านี้ถือว่าตกโลก → ใช้ตำแหน่งดีล่าสุด/จุดปลอดภัยแทน
		DropRayLength = 150,
		DropFallbackDown = 3, -- ถ้าเรย์ไม่โดนพื้น วางต่ำกว่าจุดเดิมเท่านี้
		LabelSize = UDim2.fromScale(7, 2), -- ป้ายลอย (หน่วย stud)
		LabelStudsOffset = Vector3.new(0, 3, 0),
		LabelMaxDistance = 160, -- เห็นป้ายไกลสุดกี่ stud
		LabelColor = Color3.fromRGB(255, 255, 255),
		Items = CarryItems,
	},

	-- พระที่กุฏิ (NPC ใจดี ไม่ถูกโจมตี ลิงไม่สนใจ)
	Monk = {
		Name = "Monk", -- ชื่อโมเดลใน Workspace.MissionObjects · ถ้าเจ้าของทำโมเดลชื่อนี้เอง ระบบใช้ของเจ้าของ
		OffsetFromKuti = Vector3.new(8, 0, 8), -- ยืนห่างจุดกุฏิเท่านี้ (แล้วยิงเรย์ลงพื้น)
		RaycastUp = 60, -- ยิงเรย์หาพื้นจากสูงกว่าจุดกุฏิเท่านี้ (ไม่เกาะหลังคา)
		OfferRange = 14, -- คนถือตะกร้ายืนห่างพระไม่เกินกี่ stud ถึงถวายได้
		OfferMinIntervalSeconds = 0.5,
		LabelText = "พระ",
		RobeColor = Color3.fromRGB(235, 125, 20), -- จีวรสีส้มเหลือง
		SashColor = Color3.fromRGB(190, 85, 15), -- ผ้าพาดไหล่ เข้มกว่าเล็กน้อย
		SkinColor = Color3.fromRGB(224, 172, 120),
		MoneyBagOffset = Vector3.new(-4, 0, 3), -- ถุงเงินที่พระให้ วางข้างพระ
		SnackPackOffset = Vector3.new(4, 0, 3), -- ขนม 4 ห่อ วางข้างพระ
		ToastSeconds = 4, -- ข้อความ "พระให้..." ขึ้นกี่วิ
	},

	Snacks = {
		PerMission = 4,
		TempHealth = 250,
		TempHealthSeconds = 10,
		EatMinIntervalSeconds = 0.5, -- จำกัดความถี่กดกินขนม
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

	-- ธงดีบัก (ชั่วคราว) — ปิดให้เป็น false ก่อน Publish
	Debug = {
		BroomSwing = true, -- พิมพ์ลง Output ตอนฟาดไม้กวด (ฝั่ง client และ server)
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
