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
		NonMissionRespawnSeconds = 3, -- ตายนอกภารกิจ (เช่น ตกจากห้องรอ) เกิดใหม่ในห้องรอหลังกี่วิ
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
		VoidY = -60, -- ผู้ร่วมภารกิจตกต่ำกว่าความสูงนี้ (ตกโลก) → เซิร์ฟเวอร์พากลับจุดปลอดภัย
		VoidCheckSeconds = 1, -- ตรวจตกโลกทุกกี่วินาที
		MarkersFolderName = "MapMarkers", -- โฟลเดอร์จุดสำคัญใน Workspace (MapSetup สร้างให้ถ้าไม่มี)
		ObjectsFolderName = "MapObjects", -- โฟลเดอร์สิ่งถาวรบนแมพ (กุฏิ พระ) · ไม่ถูกล้างตอนจบภารกิจ (ต่างจาก Mission.ObjectsFolderName)
		-- จุดสำคัญจะมองไม่เห็นในเกมถ้า false (ใช้แค่เป็นพิกัดให้โค้ดอ่าน) · true = แท่งสีนีออน+ป้ายชื่อ ไว้ดีบักตำแหน่ง
		MarkersVisible = false,
		MarkerVisibleTransparency = 0.4, -- ความโปร่งใสของแท่ง ตอน MarkersVisible = true
		MarkerLabelSize = UDim2.fromOffset(160, 40),
		MarkerLabelStudsOffset = Vector3.new(0, 8, 0),
		-- ตำแหน่งเริ่มต้นของจุดสำคัญ (x, z) · MapSetup สร้างให้เฉพาะจุดที่ยังไม่มีใน Workspace.MapMarkers
		-- (ไม่ย้าย/ไม่ทับจุดที่เจ้าของวางเองแล้ว) · ความสูง Y หาจากการยิงเรย์ลงบน Terrain
		-- กุฏิอยู่กลางแมพ (0,0) · ทิศเหนือ = Z ติดลบ · อิงผังใน mockups/wireframe.html
		Markers = {
			Kuti = {
				label = "กุฏิ",
				x = 0,
				z = 0,
				color = Color3.fromRGB(255, 200, 40),
				size = Vector3.new(24, 4, 24),
			},
			Nest1 = {
				label = "รังลิง 1",
				x = -186,
				z = -98,
				color = Color3.fromRGB(150, 90, 40),
				size = Vector3.new(16, 4, 16),
			},
			Nest2 = {
				label = "รังลิง 2",
				x = 186,
				z = -104,
				color = Color3.fromRGB(150, 90, 40),
				size = Vector3.new(16, 4, 16),
			},
			Nest3 = {
				label = "รังลิง 3",
				x = -138,
				z = 130,
				color = Color3.fromRGB(150, 90, 40),
				size = Vector3.new(16, 4, 16),
			},
			Nest4 = {
				label = "รังลิง 4",
				x = 138,
				z = 117,
				color = Color3.fromRGB(150, 90, 40),
				size = Vector3.new(16, 4, 16),
			},
			RocketPad = {
				label = "ฐานบั้งไฟ",
				x = 318,
				z = 195,
				color = Color3.fromRGB(230, 60, 60),
				size = Vector3.new(30, 4, 30),
			},
		},
	},

	-- กันโกงฝั่งเซิร์ฟเวอร์ (AntiTeleport / Combat): ตั้งให้หลวมพอที่เล่นปกติไม่โดนดึงกลับ (วิ่ง ลาดเอียง กระโดด เน็ตหน่วง)
	AntiCheat = {
		TickSeconds = 0.2, -- รอบตรวจตำแหน่ง
		SpeedMultiplier = 1.6, -- ยอมให้เร็วกว่า WalkSpeed กี่เท่า
		SlackStuds = 10, -- ยอมเพิ่มต่อวินาที (ชดเชยเน็ตกระตุก/ลาดชัน) — เพดานต่อรอบ = (WalkSpeed × SpeedMultiplier + SlackStuds) × dt
		MaxDtSeconds = 1.5, -- dt ที่ใช้คิดเพดานไม่เกินนี้ (เซิร์ฟเวอร์สะดุดนานก็ไม่ยอมให้เทเลพอร์ตไกลมาก)
		MaxHeadOffset = 3, -- Combat: หัวห่างจาก HumanoidRootPart เกินนี้ (stud) = ตัวละครผิดปกติ ปฏิเสธการยิง/ขว้าง/ฟาด
	},

	-- กำแพงล่องหนรอบแมพ (MapSetup สร้างตอนเริ่มเซิร์ฟเวอร์ถ้าไม่มี Workspace.MapObjects.<FolderName>) — ผู้เล่นเดินออกนอกแมพไม่ได้
	-- ไม่บังกระสุน/เรย์ (CanQuery = false) · ขอบด้านในชิดขอบแมพ (Config.Map.HalfWidthStuds / HalfDepthStuds)
	Boundary = {
		FolderName = "Boundary",
		BottomY = -150, -- ขอบล่างของกำแพง (ต่ำกว่าภูมิประเทศมาก)
		Height = 900, -- สูงรวม (ขอบบน = BottomY + Height)
		Thickness = 20,
	},

	-- กุฏิพระ: อาคารไม้ยกพื้นสร้างจาก Part (MapSetup สร้างตอนเริ่มเซิร์ฟเวอร์ถ้าไม่มี Workspace.MapObjects.<Name>)
	-- ถ้าเจ้าของทำกุฏิเอง: ลบโมเดลนี้ทิ้ง แล้วใส่ Model/Part ชื่อเดียวกันใน Workspace.MapObjects → ระบบใช้ของเจ้าของ
	-- ประตูหันไปทางใต้ (+Z) ฝั่งที่ผู้เล่นลงมา · หน่วยเป็น stud
	Kuti = {
		Name = "KutiBuilding",
		Width = 20, -- ด้านกว้าง (แกน X)
		Depth = 16, -- ด้านลึก (แกน Z)
		StiltHeight = 3, -- ความสูงใต้ถุน (วัดจากจุดต่ำสุดของพื้นดินใต้กุฏิ)
		StiltSize = 1.2,
		StiltBury = 3, -- เสาฝังลงใต้พื้นดินเท่านี้ (กันลอยเมื่อพื้นลาด)
		StiltCountX = 3, -- จำนวนเสาต่อแถว (แถวหน้า 1 แถว แถวหลัง 1 แถว)
		FloorThickness = 1,
		WallHeight = 8,
		WallThickness = 0.8,
		DoorWidth = 6,
		DoorHeight = 6.5,
		RoofRise = 6, -- ความสูงสันหลังคาเหนือขอบล่าง (ยิ่งมากยิ่งชัน)
		RoofOverhang = 2, -- ชายคายื่นออกไปด้านหน้า/หลัง
		RoofGableOverhang = 1.5, -- ชายคายื่นออกด้านข้าง
		RoofThickness = 0.7,
		RoofSink = 0.8, -- ขอบล่างหลังคาต่ำกว่าหัวผนังเท่านี้ (ไม่ให้มีช่องว่างใต้ชายคา)
		GableLayers = 5, -- จำนวนชั้นบล็อกอุดหน้าจั่ว (ยิ่งมากยิ่งเรียบ)
		RidgeThickness = 0.9, -- สันหลังคา
		FinialSize = Vector3.new(0.8, 3.5, 0.8), -- ปลายสันหลังคางอนขึ้นทั้งสองข้าง
		FinialTiltDegrees = 25,
		StepCount = 4, -- ขั้นบันไดหน้าประตู (ความสูงต่อขั้น = (ใต้ถุน+พื้น) ÷ จำนวนขั้น)
		StepDepth = 1.5,
		StepWidth = 8,
		WallColor = Color3.fromRGB(150, 100, 55),
		FloorColor = Color3.fromRGB(120, 82, 46),
		PostColor = Color3.fromRGB(95, 62, 34),
		StepColor = Color3.fromRGB(135, 92, 52),
		RoofColor = Color3.fromRGB(150, 45, 28), -- กระเบื้องแดงเข้ม
		FinialColor = Color3.fromRGB(205, 160, 60),
		-- ป้ายชื่อลอยเหนือหลังคา
		LabelText = "กุฏิ",
		LabelSize = UDim2.fromOffset(110, 36),
		LabelAbove = 5, -- ลอยเหนือสันหลังคาเท่านี้
		LabelMaxDistance = 250,
		LabelAlwaysOnTop = true, -- ป้ายเล็ก ๆ จึงเปิดให้เห็นทะลุต้นไม้/หญ้าได้
		-- เสาแสงสีเหลืองจาง ๆ ให้เห็นกุฏิจากไกล (Part นีออน ไม่ชน ไม่ถูกกระสุน)
		BeamEnabled = true,
		BeamHeight = 250,
		BeamWidth = 3,
		BeamTransparency = 0.8,
		BeamColor = Color3.fromRGB(255, 230, 110),
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
	},

	-- กลับเข้าแมพหลังตาย: (ก) เพื่อนโทรเรียก (Player.PhoneCallSeconds) · (ข) ครบ Player.RespawnSeconds → หนังสติ๊กยิงตัวเอง
	Rescue = {
		TickSeconds = 0.2, -- รอบตรวจฝั่งเซิร์ฟเวอร์ (ครบเวลาตาย/เวลาเล็ง/สายโทร)
		CallMinIntervalSeconds = 0.5, -- จำกัดความถี่คำขอโทร
		CancelMinIntervalSeconds = 0.2, -- จำกัดความถี่คำขอวางสาย
		CallCancelCooldownSeconds = 3, -- วางสายแล้ว (หรือถูกตัดสายเพราะเกินเวลา) โทรใหม่ไม่ได้ช่วงนี้ กันโทร-วางวนกวนเพื่อน
		ReservationGraceSeconds = 5, -- ครบเวลาของคนตายแล้ว สายที่เริ่มก่อนหน้านั้นยังโทรต่อได้อีกไม่เกินเท่านี้ แล้วตัดสาย
		FireMinIntervalSeconds = 0.3, -- จำกัดความถี่คำขอยิงหนังสติ๊ก
		MateRefreshSeconds = 1, -- ส่งตำแหน่งเพื่อนให้คนที่กำลังเล็งหนังสติ๊กทุกกี่วิ
		SpawnRetrySeconds = 5, -- สร้างตัวละครไม่สำเร็จ → ลองใหม่หลังกี่วิ
		WatchdogExtraSeconds = 20, -- ตัวเฝ้า: เวลาบิน + โหลดแมพ + เผื่อสร้างตัวละคร ถ้าเกินแล้วยังค้างตรึงอยู่ → ปล่อยตัว

		-- ยิงตัวเองด้วยหนังสติ๊ก (บินด้วยโค้งเดียวกับตอนเริ่มภารกิจ: Config.Launch)
		AimSeconds = 20, -- ไม่ยิงภายในเวลานี้ → ยิงอัตโนมัติไปจุดลงของภารกิจ
		AutoFireScatterStuds = 6, -- ยิงอัตโนมัติ: สุ่มรอบจุดลงในรัศมีนี้ (หลายคนไม่ลงทับกัน)
		FireToleranceStuds = 1, -- จุดที่ client ส่งมาเกินขอบที่ยอมรับได้นิดเดียว (ปัดเศษทศนิยม) ยังรับ แล้วบีบเข้าขอบ
		PullToMapScale = 1.8, -- (client) ดึงนิ้วไกลเท่าไร เป้าไกลเป็นกี่เท่าบนแผนที่ (ทิศตรงข้ามกับที่ดึง)
		MaxPullHeightFraction = 0.45, -- (client) ดึงได้ไกลสุดกี่ส่วนของความสูงแผนที่
		MinPullHeightFraction = 0.04, -- (client) ดึงน้อยกว่านี้ถือว่าแค่แตะ ไม่ยิง

		-- เพื่อนโทรเรียก: คนตายบินลงมาจากฟ้าข้างคนโทร
		CallFlightSeconds = 2, -- เวลาบิน
		CallDropHeight = 160, -- เริ่มบินจากสูงเหนือจุดลงเท่านี้
		CallApproachStuds = 40, -- เริ่มบินห่างจากจุดลงในแนวราบเท่านี้ (ทิศสุ่ม)
		CallArcPeakHeight = 20, -- ความโค้งของเส้นทาง (ยกขึ้นเหนือเส้นตรง)
		CallLandingSideStuds = 6, -- ลงพื้นข้างคนโทรห่างเท่านี้
		CallLandingAttempts = 8, -- ลองหาจุดลงรอบตัวคนโทรได้กี่ทิศ
		CallRayUp = 30, -- ยิงเรย์หาพื้นจากสูงกว่าคนโทรเท่านี้ (ไม่เกาะหลังคา/ก้อนหินเหนือหัว)
		CallMaxHeightDiff = 12, -- พื้นที่เจอต่างจากพื้นใต้เท้าคนโทรเกินนี้ → ลองทิศอื่น
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
		Name = "Monk", -- ชื่อโมเดลใน Workspace.MapObjects (สร้างตั้งแต่เริ่มเซิร์ฟเวอร์) · ถ้าเจ้าของทำโมเดลชื่อนี้เอง ระบบใช้ของเจ้าของ
		StepsGapStuds = 3, -- พระยืนหน้าบันไดกุฏิ ห่างจากขั้นล่างสุดเท่านี้ (ตำแหน่ง = กลางกุฏิ + ครึ่งความลึก + บันได + ระยะนี้ ทางใต้)
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

	-- บั้งไฟ: ถวายอาหารแล้ว → จุดชนวน → นับถอยหลัง 60 วิ (ลิงยังบุก) → มัดตัวขึ้นบั้งไฟ → ยิงขึ้นฟ้า → สรุปผล
	Rocket = {
		CountdownSeconds = 60,
		LeftBehindMultiplier = 0.95, -- ถูกทิ้ง (ไม่ได้ขึ้นบั้งไฟตอนนับครบ) ได้เงินน้อยกว่าเพื่อน 5%
		ResultsSeconds = 12, -- โชว์หน้าสรุปผลกี่วิ แล้วพากลับห้องรอ
		IgniteRange = 14, -- ยืนห่างบั้งไฟ (แนวราบ) ไม่เกินกี่ stud ถึงจุดชนวนได้
		TieRange = 12, -- ยืนห่างบั้งไฟ (แนวราบ) ไม่เกินกี่ stud ถึงมัดตัวได้
		RangeTolerance = 4, -- เซิร์ฟเวอร์ยอมให้เกินระยะอีกนิด (ชดเชยเน็ตหน่วง)
		VerticalTolerance = 25, -- ต่างความสูงจากฐานบั้งไฟเกินนี้ถือว่าไม่ได้อยู่ใกล้ (กันยืนบนหน้าผาข้างบน)
		IgniteMinIntervalSeconds = 0.5,
		TieMinIntervalSeconds = 0.5,
		TickSeconds = 0.25, -- รอบตรวจฝั่งเซิร์ฟเวอร์ตอนนับถอยหลัง (ลิงบุก / อัปเดตสถานะ)
		ToastSeconds = 4,

		-- ลิงบุกระหว่างนับถอยหลัง: ทุก RaidIntervalSeconds เรียกลิง RaidCount ตัวจากรังที่ใกล้ฐานบั้งไฟที่สุด
		-- (ไม่เกินเพดาน Config.Monkey.MaxTotal) · ลิงบุกไล่ผู้เล่นที่อยู่ใกล้ฐานบั้งไฟทันที ไม่สนระยะเห็น/ระยะผูกรัง
		RaidIntervalSeconds = 15,
		RaidCount = 3,
		RaidTargetRadius = 70, -- ลิงบุกเลือกเป้าเฉพาะผู้เล่นที่อยู่ห่างฐานบั้งไฟไม่เกินนี้ (ไม่มี → วิ่งไปรอที่ฐาน)

		-- ยิงบั้งไฟขึ้นฟ้า: ทั้งตัวบั้งไฟและคนที่มัดตัวไว้ลอยขึ้นตรง ๆ (เซิร์ฟเวอร์ขยับเอง)
		LaunchSeconds = 4,
		LaunchRiseStuds = 300,
		WatchdogExtraSeconds = 15, -- ตัวเฝ้า: ถ้าเลย (นับถอยหลัง + ยิง + สรุปผล) ไปอีกเท่านี้แล้วยังไม่กลับห้องรอ → บังคับจบภารกิจ

		-- ตัวมัดตัว: ผู้เล่นที่มัดแล้วถูกตรึงไว้ที่จุดมัด (Anchored) ยิงได้แต่ขยับไม่ได้ · ไม่รับดาเมจ (จึงไม่ล้มค้างบนบั้งไฟ)
		TieWindowSeconds = 15, -- มัดตัวได้เฉพาะ 15 วิสุดท้ายของการนับถอยหลัง (ก่อนหน้านั้นต้องยื้อ)
		TieRootHeight = 3.3, -- วาง HumanoidRootPart สูงจากจุดมัด (วงกลมบนพื้นแท่น) เท่านี้

		-- ควัน/ประกาย (ParticleEmitter ฝั่งเซิร์ฟเวอร์ ปิดไว้จนจุดชนวน) — ประหยัดเครื่อง: อัตราต่ำ
		FuseSparkRate = 18,
		LaunchSmokeRate = 45,
		LaunchFlameRate = 30,

		-- ตัวบั้งไฟ: สร้างจาก Part ล้วน ๆ ตอนเริ่มเซิร์ฟเวอร์ ถ้าไม่มี Workspace.MapObjects.<ModelName>
		-- ถ้าเจ้าของทำเอง: ใส่ Model ชื่อเดียวกัน (ควรมี Model ย่อย "Body" = ส่วนที่ลอยขึ้น และ Part "TieSpot1".."TieSpot4" = จุดมัด)
		Build = {
			ModelName = "Rocket",
			BodyDiameter = 3,
			BodyHeight = 22,
			BodyColor = Color3.fromRGB(226, 200, 150), -- ไม้ไผ่สีอ่อน
			NodeColor = Color3.fromRGB(176, 140, 86), -- ข้อไผ่
			NodeCount = 4,
			NodeDiameterExtra = 0.4,
			NodeHeight = 0.5,
			NoseTierCount = 4, -- ปลายแหลมเป็นขั้น ๆ (แดง/ทองสลับ)
			NoseTierHeight = 1.4,
			NoseBaseDiameter = 3.2,
			NoseColors = { Color3.fromRGB(205, 45, 40), Color3.fromRGB(235, 190, 60) },
			TipDiameter = 0.8,
			FinSize = Vector3.new(0.3, 4, 7), -- หนา × สูง × กว้างรวม (ยื่นออกจากตัวข้างละ 2)
			FinColor = Color3.fromRGB(150, 100, 55),
			FuseSize = Vector3.new(0.3, 1.4, 0.3), -- สายชนวนที่ก้นบั้งไฟ
			FuseColor = Color3.fromRGB(60, 45, 35),
			-- แท่นยิง: พื้นไม้ยกสูง + ขา 4 ต้น + เสากรอบด้านหลัง (ไม่ต้องปีนขึ้น — กดมัดตัวแล้วเซิร์ฟเวอร์วางคนที่จุดมัดให้)
			DeckSize = Vector3.new(18, 1, 18),
			DeckHeight = 5, -- ผิวบนของแท่นสูงจากพื้นเท่านี้
			DeckColor = Color3.fromRGB(125, 85, 48),
			LegSize = Vector3.new(1.4, 8, 1.4), -- ฝังลงดินเผื่อพื้นลาด
			LegInset = 1.2,
			FramePostSize = Vector3.new(1, 18, 1),
			FramePostSpacing = 12,
			FrameBarSize = Vector3.new(14, 0.8, 0.8),
			FrameColor = Color3.fromRGB(150, 100, 55),
			-- จุดมัด 4 จุดรอบตัวบั้งไฟ (ระดับแท่น): วงเชือกบนพื้น + ปมเชือกที่ตัวบั้งไฟ
			TieSpotCount = 4,
			TieSpotRadius = 3.2, -- ห่างแกนบั้งไฟ
			TieRingDiameter = 2.6,
			TieRingThickness = 0.2,
			TieRingColor = Color3.fromRGB(205, 45, 40),
			TieKnotHeight = 3.2, -- ปมเชือกสูงจากผิวแท่น
			TieKnotSize = 0.8,
			TieKnotColor = Color3.fromRGB(235, 190, 60),
			-- ป้ายลอยเหนือบั้งไฟ
			LabelText = "บั้งไฟ",
			LabelSize = UDim2.fromOffset(110, 36),
			LabelAbove = 4,
			LabelMaxDistance = 300,
		},
	},

	Rewards = {
		MissionComplete = 200, -- TODO(ยังไม่ระบุ): เงินก้อนใหญ่เมื่อภารกิจสำเร็จ
		MissingItemsMultiplier = 0.5, -- TODO(ยังไม่ระบุ): หนีโดยไม่มีถุงเงิน/ขนม รางวัลคูณเท่านี้
		-- false = ขาดถุงเงิน "หรือ" ขนมอย่างใดอย่างหนึ่ง (หรือทั้งคู่) คูณ MissingItemsMultiplier ครั้งเดียว (×0.5)
		-- true = ขาดทีละอย่างคูณซ้อนกัน (ขาดทั้งสอง = ×0.25)
		StackMissingItemPenalty = false,
	},

	Data = {
		StoreName = "PlayerData_v1",
		StudioStoreSuffix = "_studio", -- ใน Studio ใช้ที่เก็บ "PlayerData_v1_studio" แยกจากเกมจริง
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

	-- แผนที่นำทาง (กดปุ่มค้างถึงจะโชว์ · ฝั่ง client ล้วน ไม่ใช้ remote) สไตล์แผนที่ขุมทรัพย์บนม้วนกระดาษ วาดจาก GUI ล้วน
	NavMap = {
		DisplayOrder = 2, -- สูงกว่า HUD (0) · ต่ำกว่าหน้าเล็งหนังสติ๊ก (3)
		ButtonCenter = Vector2.new(0.07, 0.36), -- ซ้ายกลางจอ เหนือโซนจอยเดิน (y > 0.55) ใต้แถบเลือด (สิ้นสุด ~0.22) · ไม่ทับปุ่มดูเพื่อน (0.14, 0.50)
		ButtonSize = 0.16, -- เทียบความสูงจอ (ปุ่มกลม)
		ButtonText = "แผนที่",
		ButtonColor = Color3.fromRGB(170, 120, 60),
		HoldKey = Enum.KeyCode.M, -- คีย์ลัดบนคอม: กดค้างเพื่อดู
		ButtonCheckSeconds = 0.25, -- ตรวจว่าควรโชว์ปุ่มไหม (อยู่ในภารกิจ + ยังไม่ตาย) ทุกกี่วินาที
		UpdateHz = 10, -- แผนที่อัปเดตตำแหน่งกี่ครั้งต่อวินาทีตอนเปิดอยู่

		-- ขนาดแผ่นม้วนกระดาษ (เทียบจอ · UIAspectRatioConstraint คุมสัดส่วน ไม่ให้เบี้ยว)
		WidthFraction = 0.8,
		HeightFraction = 0.94,
		CenterY = 0.5,
		ScrollAspect = 1.6, -- กว้าง ÷ สูง ของม้วนกระดาษทั้งแผ่น
		RollWidth = 0.055, -- ความกว้างแกนม้วนแต่ละข้าง (เทียบความกว้างแผ่น)
		PaperInsetX = 0.03, -- กระดาษเริ่มห่างขอบแผ่นเท่านี้ (ให้แกนม้วนทับขอบ)
		PaperInsetY = 0.03,
		LandCenterY = 0.49, -- ตำแหน่งแผนที่จริง (เทียบความสูงแผ่น)
		LandWidthFraction = 0.82, -- กล่องที่แผนที่จริงอยู่ (ภาพถูกบีบด้วยสัดส่วนแมพจริงอีกชั้น)
		LandHeightFraction = 0.74,
		TitleText = "แผนที่เขางู",
		TitleCenterY = 0.075,
		DistanceCenterY = 0.915,
		NoTargetText = "ยังไม่รู้ว่าเป้าหมายอยู่ที่ไหน",
		DistanceToKuti = "ถึงกุฏิ",
		DistanceToRocket = "ถึงฐานบั้งไฟ",

		-- สี
		PaperColorTop = Color3.fromRGB(222, 180, 90),
		PaperColorBottom = Color3.fromRGB(196, 150, 60),
		PaperTransparency = 0.04,
		RollColor = Color3.fromRGB(128, 84, 40),
		RollLightColor = Color3.fromRGB(176, 124, 66),
		EdgeColor = Color3.fromRGB(110, 70, 30),
		LandColor = Color3.fromRGB(236, 205, 125),
		LandTransparency = 0.35,
		InkColor = Color3.fromRGB(88, 54, 24), -- ตัวหนังสือ / เส้นประ (น้ำตาลเข้ม)
		InkStrokeColor = Color3.fromRGB(244, 222, 160), -- ขอบตัวหนังสือสีกระดาษ อ่านง่ายบนต้นไม้/แม่น้ำ
		TargetColor = Color3.fromRGB(208, 40, 40), -- กากบาทแดง
		NestColor = Color3.fromRGB(150, 95, 50),
		KutiBodyColor = Color3.fromRGB(240, 205, 100),
		KutiRoofColor = Color3.fromRGB(176, 62, 42),
		RocketColor = Color3.fromRGB(235, 235, 245),
		RocketNoseColor = Color3.fromRGB(215, 60, 50),
		PlayerColor = Color3.fromRGB(40, 110, 220),
		PlayerOutline = Color3.fromRGB(255, 255, 255),
		DeadMateColor = Color3.fromRGB(140, 140, 140),
		MateColors = { Color3.fromRGB(70, 175, 90), Color3.fromRGB(165, 80, 200), Color3.fromRGB(235, 140, 40) },
		ItemColors = {
			FoodBasket = Color3.fromRGB(150, 90, 40),
			MoneyBag = Color3.fromRGB(255, 200, 40),
			SnackPack = Color3.fromRGB(245, 120, 60),
		},
		TreeColor = Color3.fromRGB(80, 145, 70),
		TreeDarkColor = Color3.fromRGB(50, 100, 50),
		RiverColor = Color3.fromRGB(90, 160, 215),

		-- ขนาดของบนแผนที่ (เทียบความสูงแผนที่)
		MarkerSize = 0.085,
		PlayerSize = 0.085,
		MateSize = 0.05,
		ItemSize = 0.045,
		TargetSize = 0.11,
		TargetBarThickness = 0.22, -- ความหนาขีดกากบาท เทียบขนาดกากบาท
		TreeSize = 0.05,

		-- เส้นประเดินทาง (หน่วย: เทียบความสูงแผนที่)
		DashLength = 0.035,
		DashGap = 0.03,
		DashThickness = 0.012,
		DashPoolSize = 40, -- เส้นประที่สร้างไว้ใช้ซ้ำ (เส้นทแยงสุดของแผนที่ ≈ 28 ขีด)
		DashStartPad = 0.05, -- เว้นปลายทางฝั่งผู้เล่น/ฝั่งกากบาท ไม่ให้ทับไอคอน
		DashEndPad = 0.045,

		-- ของตกแต่ง (วาดครั้งเดียว): ต้นไม้เป็นกลุ่ม · แม่น้ำเป็นเส้นคดเคี้ยว · พิกัด 0–1 บนแผนที่
		TreeClusters = {
			Vector2.new(0.08, 0.12),
			Vector2.new(0.45, 0.08),
			Vector2.new(0.74, 0.14),
			Vector2.new(0.92, 0.38),
			Vector2.new(0.10, 0.60),
			Vector2.new(0.26, 0.88),
			Vector2.new(0.62, 0.90),
			Vector2.new(0.90, 0.84),
		},
		TreeOffsets = { Vector2.new(0, 0), Vector2.new(0.035, 0.03), Vector2.new(-0.03, 0.035) }, -- ต้นไม้ในกลุ่ม (เทียบความสูงแผนที่)
		RiverSegments = 16,
		RiverStartU = 0.22,
		RiverEndU = 0.36,
		RiverAmplitude = 0.04,
		RiverWaves = 2.5,
		RiverThickness = 0.02,

		-- เข็มทิศ (มุมขวาบนของกระดาษ)
		CompassCenter = Vector2.new(0.905, 0.22),
		CompassSize = 0.075, -- เทียบความกว้างแผ่น (วงกลมจำกัดด้วยความสูงเท่ากัน)
	},

	-- ธงดีบัก (ชั่วคราว) — ปิดให้เป็น false ก่อน Publish
	Debug = {
		AntiCheat = false, -- พิมพ์เตือนลง Output เมื่อ AntiTeleport ดึงผู้เล่นกลับ/Combat ปฏิเสธเพราะหัวห่างตัว
		BroomSwing = false, -- พิมพ์ลง Output ตอนฟาดไม้กวด (ฝั่ง client และ server)
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
