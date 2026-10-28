--!strict
-- Combat: ระบบอาวุธฝั่งเซิร์ฟเวอร์ (ปืน BB / ประทัด / ไม้กวด)
-- หลักการ: client ส่งแค่ "ทิศที่เล็ง" (unit vector) — เซิร์ฟเวอร์ raycast เอง คิดความเสียหายเอง นับกระสุนเอง
-- ไม่ใช้ Tool ของ Roblox (ปุ่มบนมือถือจะชนกัน) — ช่องอาวุธ 1 = ปืน, 2 = ประทัด, 3 = ไม้กวด

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local RateLimit = require(script.Parent.RateLimit)
local PlayerHealth = require(script.Parent.PlayerHealth)
local PlayerData = require(script.Parent.PlayerData)
local Monkeys = require(script.Parent.Monkeys)

local CombatCfg = Config.Combat

local SLOT_GUN = 1
local SLOT_FIRECRACKER = 2
local SLOT_BROOM = 3
local MONKEY_TAG = "Monkey"

type Loadout = {
	character: Model,
	slot: number,
	gunId: string?,
	ammo: { [string]: number }, -- กระสุนในแม็กของปืนแต่ละกระบอก (ไม่มี key = เต็มแม็ก)
	firecrackers: number,
	reloadEndsAt: number, -- os.clock ที่เปลี่ยนแม็กเสร็จ (0 = ไม่ได้เปลี่ยนอยู่)
	reloadToken: number, -- เพิ่มทุกครั้งที่ยกเลิก/เริ่มเปลี่ยนแม็ก (กัน task.delay เก่ามาทำงานซ้ำ)
	lastFire: number,
	lastThrow: number,
	lastSwing: number,
	carrying: boolean, -- ถือของ (ตะกร้า/ถุงเงิน/ขนม): ยิงแบบไม่เล็ง เปลี่ยนแม็กไม่ได้
}

type TargetEntry = {
	monkey: Model?,
	player: Player?,
	position: Vector3,
}

local Combat = {}

local loadouts: { [Player]: Loadout } = {}
local stateEvent: RemoteEvent? = nil
local fxEvent: RemoteEvent? = nil
local firecrackersLeft: { [Player]: number } = {} -- ประทัดที่เหลือต่อผู้เล่น (ต่อเซิร์ฟเวอร์ ไม่เซฟ) เกิดใหม่ไม่เติมคืน

-- ===== ตัวช่วยตรวจค่าจาก client =====

local function isFiniteNumber(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- ตรวจว่าเป็น Vector3 จริง ไม่ NaN/inf และความยาวเป็น 1 (±ค่าคลาดเคลื่อน) แล้วคืนตัวที่ normalize
local function sanitizeDirection(value: any): Vector3?
	if typeof(value) ~= "Vector3" then
		return nil
	end
	local v = value :: Vector3
	if not (isFiniteNumber(v.X) and isFiniteNumber(v.Y) and isFiniteNumber(v.Z)) then
		return nil
	end
	local mag = v.Magnitude
	if math.abs(mag - 1) > 0.02 then
		return nil
	end
	return v.Unit
end

local function headPosition(character: Model): Vector3?
	local head = character:FindFirstChild("Head")
	if head ~= nil and head:IsA("BasePart") then
		return head.Position
	end
	return nil
end

local function rootPart(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- ===== ปืน / สถานะอาวุธ =====

-- ปืนที่ดีที่สุดที่ผู้เล่นมี (ราคาสูงสุด) — ชุดถัดไปจะมีเลือกปืนในห้องรอ
local function bestOwnedGunId(player: Player): string?
	local bestId: string? = nil
	local bestPrice = -1
	for id, def in Config.Guns do
		if PlayerData.hasGun(player, id) and def.price > bestPrice then
			bestId = id
			bestPrice = def.price
		end
	end
	return bestId
end

-- คืนนิยามปืนที่ถืออยู่ (ถ้ายังไม่เลือกหรือไม่มีแล้ว เลือกปืนที่ดีที่สุดที่มีให้)
local function currentGun(player: Player, loadout: Loadout): Config.GunDef?
	local id = loadout.gunId
	if id == nil or not PlayerData.hasGun(player, id) then
		id = bestOwnedGunId(player)
		loadout.gunId = id
	end
	if id == nil then
		return nil
	end
	return Config.Guns[id]
end

local function ammoOf(loadout: Loadout, gun: Config.GunDef): number
	local ammo = loadout.ammo[gun.id]
	if ammo == nil then
		return gun.magSize
	end
	return ammo
end

local function pushState(player: Player, loadout: Loadout)
	local event = stateEvent
	if event == nil or player.Parent ~= Players then
		return
	end
	local gun = currentGun(player, loadout)
	local reloadEnds = 0
	if loadout.reloadEndsAt ~= 0 then
		reloadEnds = Workspace:GetServerTimeNow() + (loadout.reloadEndsAt - os.clock())
	end
	event:FireClient(player, {
		slot = loadout.slot,
		gunId = if gun ~= nil then gun.id else nil,
		ammo = if gun ~= nil then ammoOf(loadout, gun) else 0,
		magSize = if gun ~= nil then gun.magSize else 0,
		firecrackers = loadout.firecrackers,
		reloadEndsAt = reloadEnds, -- เวลาเซิร์ฟเวอร์ (GetServerTimeNow) · 0 = ไม่ได้เปลี่ยนแม็ก
		carrying = loadout.carrying,
	})
end

local function cancelReload(loadout: Loadout)
	loadout.reloadToken += 1
	loadout.reloadEndsAt = 0
end

local function canAct(player: Player): Loadout?
	local loadout = loadouts[player]
	if loadout == nil or loadout.character ~= player.Character then
		return nil
	end
	if PlayerHealth.getState(player) ~= "Alive" then
		return nil
	end
	return loadout
end

-- ===== ภาพไม้กวดในมือ =====
-- สร้าง/ลบที่เซิร์ฟเวอร์ ทุกคนจึงเห็นตรงกัน · เป็นภาพล้วน ๆ ไม่ชน ไม่หนัก ไม่ถูก raycast (ไม่กระทบการคิดโดน)

local BROOM_FOLDER_NAME = "HeldBroom"

-- พิมพ์ดีบักฟาดไม้กวด (เปิด/ปิดที่ Config.Debug.BroomSwing)
local function debugBroom(message: string)
	if Config.Debug.BroomSwing then
		print("[BroomSwing][server] " .. message)
	end
end

local function removeBroom(character: Model)
	local existing = character:FindFirstChild(BROOM_FOLDER_NAME)
	if existing ~= nil then
		existing:Destroy()
	end
end

local function makeVisualPart(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

local function attachBroom(character: Model)
	if character:FindFirstChild(BROOM_FOLDER_NAME) ~= nil then
		return
	end
	-- R15 = RightHand · R6 = Right Arm
	local hand = character:FindFirstChild("RightHand")
	local gripOffset = Config.Broom.GripOffsetR15
	if hand == nil then
		hand = character:FindFirstChild("Right Arm")
		gripOffset = Config.Broom.GripOffsetR6
	end
	if hand == nil or not hand:IsA("BasePart") then
		return
	end

	local broomCfg = Config.Broom
	local folder = Instance.new("Folder")
	folder.Name = BROOM_FOLDER_NAME

	local length = broomCfg.HandleLength
	local handle = makeVisualPart(
		"Handle",
		Vector3.new(broomCfg.HandleThickness, length, broomCfg.HandleThickness),
		broomCfg.HandleColor,
		Enum.Material.Wood
	)
	-- วางด้ามให้จุดจับ (วัดจากปลายบน) ตรงกับมือ แล้วเอียงด้ามไปข้างหน้า (ดู GripTiltDegrees)
	-- ปลายล่างของด้าม (แกน -Y) คือด้านหัวไม้กวด
	local gripOnHandle = CFrame.new(0, length / 2 - broomCfg.GripFromTop, 0)
	local handWeld = Instance.new("Weld")
	handWeld.Name = "HandWeld"
	handWeld.Part0 = hand
	handWeld.Part1 = handle
	handWeld.C0 = CFrame.new(gripOffset) * CFrame.Angles(math.rad(broomCfg.GripTiltDegrees), 0, 0)
	handWeld.C1 = gripOnHandle
	handle.CFrame = hand.CFrame * handWeld.C0 * gripOnHandle:Inverse()
	handWeld.Parent = handle

	-- หัวไม้กวดรูปพัด = ส่วนคอแคบ (บน) + ชายฟางบานกว้าง (ล่าง) ต่อที่ปลายล่างของด้าม ซ้อนกันเล็กน้อยให้ดูแน่น
	local headSize = broomCfg.BristleSize
	local neckHeight = headSize.Y * broomCfg.NeckHeightFraction
	local skirtHeight = headSize.Y - neckHeight
	local headTopY = -(length / 2) + 0.3 -- ขอบบนของหัวไม้กวด (พิกัดบนด้าม)

	local function addHeadPart(name: string, size: Vector3, centerY: number, color: Color3)
		local part = makeVisualPart(name, size, color, Enum.Material.Fabric)
		local weld = Instance.new("Weld")
		weld.Name = name .. "Weld"
		weld.Part0 = handle
		weld.Part1 = part
		weld.C0 = CFrame.new(0, centerY, 0)
		part.CFrame = handle.CFrame * weld.C0
		weld.Parent = part
		part.Parent = folder
	end
	addHeadPart(
		"BroomNeck",
		Vector3.new(headSize.X * broomCfg.NeckWidthFraction, neckHeight, headSize.Z * 0.9),
		headTopY - neckHeight / 2,
		broomCfg.NeckColor
	)
	addHeadPart(
		"Bristles",
		Vector3.new(headSize.X, skirtHeight, headSize.Z),
		headTopY - neckHeight - skirtHeight / 2,
		broomCfg.BristleColor
	)

	handle.Parent = folder
	folder.Parent = character
end

-- ให้ไม้กวดในมือตรงกับสถานะ: ถืออยู่เมื่อเลือกช่อง 3 และสถานะปกติเท่านั้น (ล้ม/ตาย/ช่องอื่น = ลบ)
local function syncBroom(player: Player, loadout: Loadout)
	local character = loadout.character
	if character.Parent == nil then
		return
	end
	local wantBroom = loadout.slot == SLOT_BROOM and PlayerHealth.getState(player) == "Alive"
	if wantBroom then
		attachBroom(character)
	else
		removeBroom(character)
	end
end

-- ===== หาเป้า / ทำความเสียหาย =====

-- เดินขึ้นจากชิ้นส่วนที่ raycast โดน หาว่าเป็นตัวลิง (Model ติด tag) หรือตัวละครผู้เล่น
local function resolveHit(inst: Instance): (Model?, Player?)
	local current: Instance? = inst
	while current ~= nil and current ~= Workspace do
		if current:IsA("Model") then
			if CollectionService:HasTag(current, MONKEY_TAG) then
				return current, nil
			end
			local owner = Players:GetPlayerFromCharacter(current)
			if owner ~= nil then
				return nil, owner
			end
		end
		current = current.Parent
	end
	return nil, nil
end

local function damageMonkey(model: Model, amount: number, attacker: Player)
	local ok, err = pcall(function()
		Monkeys.damageMonkey(model, amount, attacker)
	end)
	if not ok then
		warn("[Combat] damageMonkey error:", err)
	end
end

local function applyHit(inst: Instance, amount: number, attacker: Player)
	local monkey, victim = resolveHit(inst)
	if monkey ~= nil then
		damageMonkey(monkey, amount, attacker)
	elseif victim ~= nil and victim ~= attacker then
		PlayerHealth.damageFromPlayer(victim, amount, attacker)
	end
end

-- รวมเป้าที่โดนวงได้ทั้งหมด (ลิง + ผู้เล่นอื่น) · includeSelf = true นับผู้โจมตีเองเป็นเป้าด้วย (ใช้กับประทัดเท่านั้น)
local function gatherTargets(attacker: Player, includeSelf: boolean): { TargetEntry }
	local list: { TargetEntry } = {}
	for _, inst in CollectionService:GetTagged(MONKEY_TAG) do
		if inst:IsA("Model") and inst:IsDescendantOf(Workspace) then
			table.insert(list, { monkey = inst, player = nil, position = inst:GetPivot().Position })
		end
	end
	for _, other in Players:GetPlayers() do
		if (includeSelf or other ~= attacker) and other.Character ~= nil then
			local root = rootPart(other.Character)
			if root ~= nil then
				table.insert(list, { monkey = nil, player = other, position = root.Position })
			end
		end
	end
	return list
end

local function damageEntry(entry: TargetEntry, amount: number, attacker: Player)
	if entry.monkey ~= nil then
		damageMonkey(entry.monkey, amount, attacker)
	elseif entry.player ~= nil then
		PlayerHealth.damageFromPlayer(entry.player, amount, attacker)
	end
end

-- ===== ยิงปืน =====

-- สุ่มเบนทิศภายในกรวยครึ่งมุม spreadDegrees (สุ่มที่เซิร์ฟเวอร์เท่านั้น)
local function spreadDirection(dir: Vector3, spreadDegrees: number): Vector3
	if spreadDegrees <= 0 then
		return dir
	end
	local roll = math.random() * math.pi * 2
	local pitch = math.rad(spreadDegrees) * math.sqrt(math.random())
	local cf = CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(0, 0, roll) * CFrame.Angles(pitch, 0, 0)
	return cf.LookVector
end

local function onFire(player: Player, rawDir: any)
	if not RateLimit.allow(player, "Fire", CombatCfg.ActionMinIntervalSeconds) then
		return
	end
	local dir = sanitizeDirection(rawDir)
	if dir == nil then
		return
	end
	local loadout = canAct(player)
	if loadout == nil or loadout.slot ~= SLOT_GUN or loadout.reloadEndsAt ~= 0 then
		return
	end
	local gun = currentGun(player, loadout)
	if gun == nil then
		return
	end
	local now = os.clock()
	if now - loadout.lastFire < (1 / gun.fireRate) * CombatCfg.FireRateTolerance then
		return
	end
	local ammo = ammoOf(loadout, gun)
	if ammo <= 0 then
		return
	end
	local origin = headPosition(loadout.character)
	if origin == nil then
		return
	end

	loadout.lastFire = now
	loadout.ammo[gun.id] = ammo - 1

	local spread = 0
	if gun.pellets > 1 then
		spread += CombatCfg.ShotgunSpreadDegrees
	end
	if loadout.carrying then
		spread += CombatCfg.CarrySpreadDegrees -- ถือของ = ยิงแบบไม่เล็ง ศูนย์กว้าง
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { loadout.character }

	local ends: { Vector3 } = {}
	for _ = 1, gun.pellets do
		local pelletDir = spreadDirection(dir, spread)
		local result = Workspace:Raycast(origin, pelletDir * CombatCfg.MaxRange, params)
		if result ~= nil then
			table.insert(ends, result.Position)
			applyHit(result.Instance, gun.damagePerPellet, player)
		else
			table.insert(ends, origin + pelletDir * CombatCfg.MaxRange)
		end
	end

	local fx = fxEvent
	if fx ~= nil then
		fx:FireAllClients(origin, ends)
	end
	pushState(player, loadout)
end

-- ===== เปลี่ยนแม็ก =====

local function onReload(player: Player)
	if not RateLimit.allow(player, "Reload", CombatCfg.MenuMinIntervalSeconds) then
		return
	end
	local loadout = canAct(player)
	if loadout == nil or loadout.slot ~= SLOT_GUN or loadout.carrying or loadout.reloadEndsAt ~= 0 then
		return -- ถือของอยู่เปลี่ยนแม็กไม่ได้
	end
	local gun = currentGun(player, loadout)
	if gun == nil or ammoOf(loadout, gun) >= gun.magSize then
		return
	end
	cancelReload(loadout)
	local token = loadout.reloadToken
	loadout.reloadEndsAt = os.clock() + CombatCfg.ReloadSeconds
	pushState(player, loadout)

	task.delay(CombatCfg.ReloadSeconds, function()
		if loadouts[player] ~= loadout or loadout.reloadToken ~= token then
			return
		end
		loadout.reloadEndsAt = 0
		if PlayerHealth.getState(player) == "Alive" and loadout.gunId == gun.id then
			loadout.ammo[gun.id] = gun.magSize -- กระสุนสำรองไม่จำกัด
		end
		pushState(player, loadout)
	end)
end

-- ===== ประทัด =====

local function explodeFirecracker(position: Vector3, attacker: Player)
	-- ภาพวงระเบิด: Explosion ไม่ทำลายอะไร (BlastPressure 0) ไม่มีเลือด
	local ex = Instance.new("Explosion")
	ex.Position = position
	ex.BlastRadius = Config.Firecracker.Radius
	ex.BlastPressure = 0
	ex.DestroyJointRadiusPercent = 0
	ex.ExplosionType = Enum.ExplosionType.NoCraters
	ex.Parent = Workspace

	-- ประทัดโดนผู้ขว้างเองได้ ความเสียหายเท่ากัน · HP หมดจากประทัดตัวเอง → ล้ม (ไม่ใช่ตาย)
	for _, entry in gatherTargets(attacker, true) do
		if (entry.position - position).Magnitude <= Config.Firecracker.Radius then
			damageEntry(entry, Config.Firecracker.AreaDamage, attacker)
		end
	end
end

local function onThrow(player: Player, rawDir: any)
	if not RateLimit.allow(player, "Throw", CombatCfg.ActionMinIntervalSeconds) then
		return
	end
	local dir = sanitizeDirection(rawDir)
	if dir == nil then
		return
	end
	local loadout = canAct(player)
	if loadout == nil or loadout.firecrackers <= 0 then
		return
	end
	local now = os.clock()
	if now - loadout.lastThrow < Config.Firecracker.ThrowCooldownSeconds then
		return
	end
	local origin = headPosition(loadout.character)
	if origin == nil then
		return
	end
	loadout.lastThrow = now
	loadout.firecrackers -= 1
	firecrackersLeft[player] = loadout.firecrackers

	-- ชิ้นประทัดจริงอยู่ที่เซิร์ฟเวอร์ (เซิร์ฟเวอร์เป็นเจ้าของฟิสิกส์)
	local part = Instance.new("Part")
	part.Name = "Firecracker"
	part.Size = Vector3.new(0.5, 0.5, 1.2)
	part.Color = Color3.fromRGB(210, 40, 40)
	part.Material = Enum.Material.SmoothPlastic
	part.CanQuery = false -- ไม่ให้กระสุนชน
	part.CanTouch = false
	local launch = (dir + Vector3.new(0, 0.25, 0)).Unit
	part.CFrame = CFrame.lookAt(origin + dir * 2.5, origin + dir * 2.5 + launch)
	part.AssemblyLinearVelocity = launch * Config.Firecracker.ThrowSpeed
	part.Parent = Workspace
	pcall(function()
		part:SetNetworkOwner(nil)
	end)

	task.delay(Config.Firecracker.FuseSeconds, function()
		if part.Parent == nil then
			return
		end
		local position = part.Position
		part:Destroy()
		explodeFirecracker(position, player)
	end)
	Debris:AddItem(part, Config.Firecracker.FuseSeconds + 1)

	pushState(player, loadout)
end

-- ===== ไม้กวด =====

local function onSwing(player: Player, rawDir: any)
	if not RateLimit.allow(player, "Swing", CombatCfg.ActionMinIntervalSeconds) then
		return
	end
	local dir = sanitizeDirection(rawDir)
	if dir == nil then
		return
	end
	local loadout = canAct(player)
	if loadout == nil or loadout.slot ~= SLOT_BROOM then
		debugBroom(player.Name .. " swing rejected: cannot act or slot is not broom")
		return
	end
	local now = os.clock()
	if now - loadout.lastSwing < Config.Broom.SwingCooldownSeconds then
		debugBroom(player.Name .. " swing rejected: cooldown")
		return
	end
	local root = rootPart(loadout.character)
	if root == nil then
		return
	end
	loadout.lastSwing = now
	debugBroom(player.Name .. " swing accepted (slot 3)")

	-- บอกทุกคน (ยกเว้นผู้ฟาด ที่เล่นท่าเองทันทีแล้ว) ให้เล่นท่าฟาด — ภาพล้วน ไม่เกี่ยวกับการคิดความเสียหายด้านล่าง
	local fx = fxEvent
	if fx ~= nil then
		local message = { kind = "swing", character = loadout.character }
		for _, other in Players:GetPlayers() do
			if other ~= player then
				fx:FireClient(other, message)
			end
		end
	end

	-- ฟาดเป็นรูปพัดหน้าตัว: อยู่ในระยะ + อยู่ในมุม (TODO: เช็คกำแพงกั้น)
	local origin = root.Position
	local minDot = math.cos(math.rad(Config.Broom.ArcHalfAngleDegrees))
	for _, entry in gatherTargets(player, false) do -- ไม้กวดไม่โดนตัวเอง
		local offset = entry.position - origin
		local dist = offset.Magnitude
		if dist <= Config.Broom.Range and (dist < 0.5 or offset.Unit:Dot(dir) >= minDot) then
			damageEntry(entry, Config.Broom.Damage, player)
		end
	end
end

-- ===== เปลี่ยนช่อง / เปลี่ยนปืน =====

local function onSelectSlot(player: Player, rawSlot: any)
	if not RateLimit.allow(player, "SelectSlot", CombatCfg.MenuMinIntervalSeconds) then
		return
	end
	local loadout = loadouts[player]
	if loadout == nil or loadout.character ~= player.Character then
		return
	end
	-- ส่งอะไรมาก็ได้ ถ้าไม่ใช่ 1–3 ก็แค่ขอสถานะล่าสุด (ใช้ตอน client เพิ่งเริ่ม)
	if isFiniteNumber(rawSlot) and (rawSlot == SLOT_GUN or rawSlot == SLOT_FIRECRACKER or rawSlot == SLOT_BROOM) then
		if loadout.slot ~= rawSlot then
			cancelReload(loadout)
			loadout.slot = rawSlot
		end
	end
	syncBroom(player, loadout)
	pushState(player, loadout)
end

local function onSelectGun(player: Player, gunId: any)
	if not RateLimit.allow(player, "SelectGun", CombatCfg.MenuMinIntervalSeconds) then
		return
	end
	local loadout = loadouts[player]
	if loadout == nil or loadout.character ~= player.Character then
		return
	end
	if type(gunId) ~= "string" or Config.Guns[gunId] == nil or not PlayerData.hasGun(player, gunId) then
		return
	end
	if loadout.gunId ~= gunId then
		cancelReload(loadout)
		loadout.gunId = gunId
	end
	loadout.slot = SLOT_GUN
	syncBroom(player, loadout) -- เปลี่ยนไปถือปืน = เก็บไม้กวด
	pushState(player, loadout)
end

-- ===== เกิดใหม่ =====

local function resetLoadout(player: Player, character: Model)
	-- เข้าเกมครั้งแรกเติมเต็ม · เกิดใหม่หลังตายใช้จำนวนที่เหลือ (ไม่ได้ประทัดคืน)
	local remaining = firecrackersLeft[player]
	if remaining == nil then
		remaining = Config.Firecracker.PerPlayer
		firecrackersLeft[player] = remaining
	end
	local loadout: Loadout = {
		character = character,
		slot = SLOT_GUN,
		gunId = nil,
		ammo = {},
		firecrackers = remaining,
		reloadEndsAt = 0,
		reloadToken = 0,
		lastFire = 0,
		lastThrow = 0,
		lastSwing = 0,
		carrying = false,
	}
	loadouts[player] = loadout
	removeBroom(character)
	pushState(player, loadout)

	-- สถานะเปลี่ยน (ล้ม/ตาย/ชุบ) หรือตัวละครตาย → ให้ไม้กวดในมือตรงกับสถานะ
	local function resyncBroom()
		if loadouts[player] == loadout then
			syncBroom(player, loadout)
		end
	end
	character:GetAttributeChangedSignal("State"):Connect(resyncBroom)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.Died:Connect(function()
			if loadouts[player] == loadout then
				removeBroom(character)
			end
		end)
	end

	-- ข้อมูลผู้เล่น (ปืนที่มี) อาจยังโหลดไม่เสร็จ → รอแล้วเลือกปืนให้ใหม่
	task.spawn(function()
		for _ = 1, 60 do
			if loadouts[player] ~= loadout or PlayerData.get(player) ~= nil then
				break
			end
			task.wait(0.5)
		end
		if loadouts[player] == loadout then
			pushState(player, loadout)
		end
	end)
end

local function setupPlayer(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		resetLoadout(player, character)
	end)
	if player.Character ~= nil then
		resetLoadout(player, player.Character)
	end
end

-- ===== API ให้ระบบอื่น =====

-- ระบบถือของ (ชุดถัดไป) เรียกตรงนี้: ถือของ → ยิงแบบไม่เล็ง + เปลี่ยนแม็กไม่ได้
function Combat.setCarrying(player: Player, carrying: boolean)
	local loadout = loadouts[player]
	if loadout == nil then
		return
	end
	loadout.carrying = carrying
	if carrying then
		cancelReload(loadout)
	end
	pushState(player, loadout)
end

-- ระบบภารกิจเรียกตอนเริ่มภารกิจ: เติมประทัดให้ครบ (TODO: ผูกกับระบบภารกิจชุดถัดไป)
function Combat.refillFirecrackers(player: Player)
	firecrackersLeft[player] = Config.Firecracker.PerPlayer
	local loadout = loadouts[player]
	if loadout ~= nil then
		loadout.firecrackers = Config.Firecracker.PerPlayer
		pushState(player, loadout)
	end
end

function Combat.init()
	stateEvent = Remotes.remoteEvent("CombatState") -- server → เจ้าของ
	fxEvent = Remotes.remoteEvent("CombatFx") -- server → ทุกคน (เส้นกระสุน)

	Remotes.remoteEvent("CombatFire").OnServerEvent:Connect(onFire)
	Remotes.remoteEvent("CombatReload").OnServerEvent:Connect(onReload)
	Remotes.remoteEvent("CombatThrow").OnServerEvent:Connect(onThrow)
	Remotes.remoteEvent("CombatSwing").OnServerEvent:Connect(onSwing)
	Remotes.remoteEvent("CombatSelectSlot").OnServerEvent:Connect(onSelectSlot)
	Remotes.remoteEvent("CombatSelectGun").OnServerEvent:Connect(onSelectGun)

	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		loadouts[player] = nil
		firecrackersLeft[player] = nil
	end)
end

return Combat
