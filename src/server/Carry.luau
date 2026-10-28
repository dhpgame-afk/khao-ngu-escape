--!strict
-- Carry: ของที่ต้องถือ (ตะกร้าอาหาร FoodBasket / ถุงเงิน MoneyBag / ขนมพระ SnackPack) — เซิร์ฟเวอร์ตัดสินทุกอย่าง
-- - ถือได้ทีละชิ้นต่อคน และชิ้นหนึ่งมีคนถือได้คนเดียว (แต่ละชนิดมีได้ชิ้นเดียวในภารกิจ)
-- - ขณะถือ: Combat.setCarrying(true) (ยิงแบบไม่เล็ง เปลี่ยนแม็กไม่ได้) · วิ่งเร็วปกติ · ของ weld ติดตัวละคร ทุกคนเห็น
-- - ของหล่นตรงที่ยืนเมื่อ: ตาย (State = Dead) · ออกเกม · ภารกิจจบ · กดวางของ · (ล้ม "ไม่" ทำของหล่น)
-- - สถานะของอยู่ฝั่งเซิร์ฟเวอร์ · ส่งให้ client ผ่าน Attribute (ไม่ใช่ข้อมูลลับ):
--     Model ของ: ItemKind, Held (boolean), Count (ขนมพระ)
--     Character ของคนถือ: CarryKind ("" = ไม่ได้ถือ), CarryCount
-- - client ส่งได้แค่เจตนา: CarryPickUp(ชื่อของ) / CarryDrop() — ระยะ/สถานะ/ความถี่ตรวจที่เซิร์ฟเวอร์

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local RateLimit = require(script.Parent.RateLimit)
local PlayerHealth = require(script.Parent.PlayerHealth)
local Combat = require(script.Parent.Combat)

local CarryCfg = Config.Carry

type Item = {
	kind: string,
	model: Model,
	body: BasePart,
	label: TextLabel,
	holder: Player?,
	count: number, -- จำนวนห่อ (ใช้กับ SnackPack เท่านั้น)
	weld: Weld?,
	connections: { RBXScriptConnection },
	lastGood: Vector3?, -- ตำแหน่งบนพื้นดีล่าสุดของของชิ้นนี้/คนถือ (ไว้เป็นที่วางสำรองถ้าเรย์หาพื้นไม่โดน)
}

local Carry = {}

local itemsByKind: { [string]: Item } = {}
local heldBy: { [Player]: Item } = {}
-- Mission ตั้งให้: จุดปลอดภัยที่ของที่ตกโลกจะกลับมา (ข้างพระถ้าถวายแล้ว · ไม่งั้นจุดลง) · nil = ไม่มี
local getSafeSpot: () -> Vector3? = function(): Vector3?
	return nil
end
-- Mission ตั้งให้: ตอนนี้อยู่ในภารกิจ (InMission) และผู้เล่นคนนี้เป็นผู้ร่วมภารกิจไหม
local canInteract: (Player) -> boolean = function(_player: Player): boolean
	return false
end

-- Mission ตั้งให้: ผู้เล่นคนนี้ถูกตรึงอยู่กับบั้งไฟ (มัดตัวแล้ว) → หยิบ/วางของไม่ได้ ของที่ถืออยู่ต้องติดตัวไปกับบั้งไฟ
local isLocked: (Player) -> boolean = function(_player: Player): boolean
	return false
end

function Carry.setLockGuard(guard: (Player) -> boolean)
	isLocked = guard
end

-- ===== ตัวช่วย =====

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

function Carry.getFolder(): Folder
	local existing = Workspace:FindFirstChild(Config.Mission.ObjectsFolderName)
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = Config.Mission.ObjectsFolderName
	folder.Parent = Workspace
	return folder
end

local function setAnchored(model: Model, anchored: boolean)
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.Anchored = anchored
		end
	end
end

local function labelTextOf(item: Item): string
	local def = CarryCfg.Items[item.kind]
	local name = if def ~= nil then def.displayName else item.kind
	if item.kind == "SnackPack" then
		return name .. " ×" .. item.count
	end
	return name
end

local function refreshItemAttributes(item: Item)
	item.model:SetAttribute("Count", item.count)
	item.label.Text = labelTextOf(item)
	local holder = item.holder
	if holder ~= nil and holder.Character ~= nil then
		holder.Character:SetAttribute("CarryCount", item.count)
	end
end

-- ยิงเรย์ลงหาพื้น · ไม่นับตัวละคร ลิง และของภารกิจ (ไม่งั้นวางทับตัวเอง)
local function groundRayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { Carry.getFolder() }
	local monkeys = Workspace:FindFirstChild("Monkeys")
	if monkeys ~= nil then
		table.insert(ignore, monkeys)
	end
	for _, player in Players:GetPlayers() do
		if player.Character ~= nil then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	return params
end

-- หาพื้นใต้จุด near · รอบแรกเริ่มยิงจากระดับตัว (ไม่เกาะหินที่ยื่นเหนือหัว) รอบสองเริ่มสูงขึ้น
-- พื้นที่ต่ำกว่า VoidY (ตกโลก) ถือว่าไม่เจอ · คืน nil ถ้าไม่เจอ
local function findGround(near: Vector3, params: RaycastParams): Vector3?
	local direction = Vector3.new(0, -CarryCfg.DropRayLength, 0)
	for _, up in { CarryCfg.DropRayStartUp, CarryCfg.DropRayUp } do
		local result = Workspace:Raycast(near + Vector3.new(0, up, 0), direction, params)
		if result ~= nil and result.Position.Y >= CarryCfg.VoidY then
			return result.Position
		end
	end
	return nil
end

-- วางของบนพื้นใต้จุด `near` (ตามแนวดิ่ง)
-- ถ้าหาพื้นไม่เจอ (เช่น ตายเหนือเหว/นอกแมพ) ลองตามลำดับ: ตำแหน่งดีล่าสุดของของ → จุดปลอดภัยจาก Mission → ต่ำกว่าจุดเดิมนิดเดียว
local function placeOnGround(item: Item, near: Vector3)
	local def = CarryCfg.Items[item.kind]
	local restHeight = if def ~= nil then def.restHeight else 1
	local params = groundRayParams()
	local ground = findGround(near, params)
	if ground == nil and item.lastGood ~= nil then
		ground = findGround(item.lastGood, params)
	end
	if ground == nil then
		local safe = getSafeSpot()
		if safe ~= nil then
			warn(
				"[Carry] หาพื้นให้",
				item.kind,
				"ไม่เจอ — ย้ายกลับจุดปลอดภัย"
			)
			ground = findGround(safe, params) or safe
		end
	end
	if ground == nil then
		ground = Vector3.new(near.X, near.Y - CarryCfg.DropFallbackDown, near.Z)
	end
	item.lastGood = ground
	item.model:PivotTo(CFrame.new(ground.X, ground.Y + restHeight, ground.Z))
end

-- ===== สร้างของ =====

local function buildItem(kind: string, count: number): Item?
	local def = CarryCfg.Items[kind]
	if def == nil then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = kind
	local body: BasePart? = nil
	for _, spec in def.parts do
		local part = Instance.new("Part")
		part.Name = spec.name
		part.Shape = spec.shape
		part.Size = spec.size
		part.Color = spec.color
		part.Material = spec.material
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Anchored = true
		part.CanCollide = false -- ไม่กีดขวางผู้เล่นและลิง
		part.CanQuery = false -- ไม่บังกระสุน ไม่ให้ raycast ของลิง/ปืนโดน
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		if body == nil then
			body = part
			part.CFrame = CFrame.new(0, 0, 0)
		else
			part.CFrame = CFrame.new(spec.offset)
		end
		if body ~= part then
			-- ประกอบชิ้นเข้ากับ Body (ตั้งตำแหน่งก่อนแล้วค่อย weld)
			local weldConstraint = Instance.new("WeldConstraint")
			weldConstraint.Part0 = body
			weldConstraint.Part1 = part
			weldConstraint.Parent = part
		end
		part.Parent = model
	end
	if body == nil then
		model:Destroy()
		return nil
	end
	model.PrimaryPart = body

	-- ป้ายลอยให้หาเจอบนแมพใหญ่
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ItemLabel"
	billboard.Size = CarryCfg.LabelSize
	billboard.StudsOffset = CarryCfg.LabelStudsOffset
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = CarryCfg.LabelMaxDistance
	billboard.Parent = body
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = CarryCfg.LabelColor
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.Parent = billboard

	model:SetAttribute("ItemKind", kind)
	model:SetAttribute("Held", false)
	local item: Item = {
		kind = kind,
		model = model,
		body = body,
		label = label,
		holder = nil,
		count = count,
		weld = nil,
		connections = {},
		lastGood = nil,
	}
	refreshItemAttributes(item)
	return item
end

-- ===== ถือ / วาง =====

local function clearHolderState(player: Player)
	heldBy[player] = nil
	local character = player.Character
	if character ~= nil then
		character:SetAttribute("CarryKind", "")
		character:SetAttribute("CarryCount", 0)
	end
	Combat.setCarrying(player, false)
end

-- ปล่อยของจากมือ (ยังไม่วางบนพื้น) — ใช้ร่วมกันทั้งวาง/ทำลาย
local function detach(item: Item)
	for _, connection in item.connections do
		connection:Disconnect()
	end
	item.connections = {}
	local weld = item.weld
	if weld ~= nil then
		weld:Destroy()
		item.weld = nil
	end
	local holder = item.holder
	item.holder = nil
	item.model:SetAttribute("Held", false)
	if holder ~= nil and heldBy[holder] == item then
		clearHolderState(holder)
	end
end

-- วางลงพื้นที่จุด `near` (เรย์ลงพื้น)
local function dropItem(item: Item, near: Vector3)
	detach(item)
	setAnchored(item.model, true) -- ตรึงก่อนย้าย กันตกลงหรือสะบัด
	placeOnGround(item, near)
end

-- ของหล่นตรงที่คนถือยืน (ตาย/ออกเกม/ภารกิจจบ): ถ้าไม่มีตัวละครแล้วใช้ตำแหน่งของที่ติดตัวอยู่
local function dropAtHolder(item: Item)
	local holder = item.holder
	local root = if holder ~= nil then rootOf(holder) else nil
	local near = if root ~= nil then root.Position else item.body.Position
	dropItem(item, near)
end

local function attachToPlayer(player: Player, item: Item): boolean
	local root = rootOf(player)
	local character = player.Character
	if root == nil or character == nil then
		return false
	end
	local def = CarryCfg.Items[item.kind]
	if def == nil then
		return false
	end
	item.holder = player
	heldBy[player] = item
	item.model:SetAttribute("Held", true)
	item.lastGood = item.body.Position -- ตอนหยิบ ของอยู่บนพื้น

	-- ย้ายของไปตำแหน่งถือก่อน weld แล้วค่อยปลดตรึง (Part ในโมเดลต่อกันด้วย WeldConstraint อยู่แล้ว)
	item.model:PivotTo(root.CFrame * CFrame.new(def.holdOffset))
	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part0 = root
	weld.Part1 = item.body
	weld.C0 = CFrame.new(def.holdOffset)
	weld.Parent = item.body
	item.weld = weld
	setAnchored(item.model, false)

	character:SetAttribute("CarryKind", item.kind)
	character:SetAttribute("CarryCount", item.count)
	Combat.setCarrying(player, true)

	-- เฝ้าเหตุที่ต้องทำของหล่น: ตาย (ล้ม "ไม่" หล่น) · ตัวละครหาย
	table.insert(
		item.connections,
		character:GetAttributeChangedSignal("State"):Connect(function()
			if character:GetAttribute("State") == "Dead" and item.holder == player then
				dropAtHolder(item)
			end
		end)
	)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		table.insert(
			item.connections,
			humanoid.Died:Connect(function()
				if item.holder == player then
					dropAtHolder(item)
				end
			end)
		)
	end
	if humanoid ~= nil then
		-- คนถือยืนบนพื้นเมื่อไรจำตำแหน่งไว้ — ถ้าตายตอนตกเหว ของจะกลับมาที่จุดนี้
		table.insert(
			item.connections,
			humanoid:GetPropertyChangedSignal("FloorMaterial"):Connect(function()
				if humanoid.FloorMaterial ~= Enum.Material.Air and item.holder == player then
					item.lastGood = root.Position
				end
			end)
		)
	end
	table.insert(
		item.connections,
		character.Destroying:Connect(function()
			if item.holder == player then
				dropAtHolder(item)
			end
		end)
	)
	return true
end

-- ===== คำขอจาก client =====

local function onPickUp(player: Player, itemName: any)
	if not RateLimit.allow(player, "CarryPickUp", CarryCfg.PickupMinIntervalSeconds) then
		return
	end
	if type(itemName) ~= "string" or CarryCfg.Items[itemName] == nil then
		return
	end
	if not canInteract(player) or PlayerHealth.getState(player) ~= "Alive" or isLocked(player) then
		return
	end
	if heldBy[player] ~= nil then
		return -- ถือของอยู่แล้ว (ทีละชิ้น)
	end
	local item = itemsByKind[itemName]
	if item == nil or item.holder ~= nil or item.model.Parent == nil then
		return
	end
	local root = rootOf(player)
	if root == nil then
		return
	end
	-- ระยะคิดที่เซิร์ฟเวอร์เอง ไม่เชื่อตำแหน่งจาก client
	if (root.Position - item.body.Position).Magnitude > CarryCfg.PickupRange + CarryCfg.RangeTolerance then
		return
	end
	attachToPlayer(player, item)
end

local function onDrop(player: Player)
	if not RateLimit.allow(player, "CarryDrop", CarryCfg.DropMinIntervalSeconds) then
		return
	end
	local item = heldBy[player]
	if item == nil then
		return
	end
	if PlayerHealth.getState(player) == "Dead" then
		return -- ตายแล้ว ของหล่นไปแล้วจากตัวเฝ้า
	end
	if isLocked(player) then
		return -- มัดตัวบนบั้งไฟแล้ว: ของที่ถืออยู่ต้องติดไปกับบั้งไฟ
	end
	local root = rootOf(player)
	if root == nil then
		dropAtHolder(item)
		return
	end
	-- วางห่างหน้าตัวเล็กน้อย (แนวราบ) ไม่ทับตัวเอง
	local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local near = root.Position
	if forward.Magnitude > 0.05 then
		near += forward.Unit * CarryCfg.DropForwardStuds
	end
	dropItem(item, near)
end

-- ===== API ให้ระบบอื่น =====

-- ลบของชนิดนี้ทิ้ง (ถ้ามีคนถือ ปลดมือให้ด้วย)
function Carry.destroyItem(kind: string)
	local item = itemsByKind[kind]
	if item == nil then
		return
	end
	itemsByKind[kind] = nil
	detach(item)
	item.model:Destroy()
end

-- สร้างของที่ตำแหน่ง position (กึ่งกลาง Body) แบบตรึงอยู่กับที่ · ชนิดเดิมที่มีอยู่ก่อนจะถูกลบ (มีได้ชิ้นเดียวต่อชนิด)
function Carry.spawnItem(kind: string, position: Vector3, count: number?): Model
	Carry.destroyItem(kind)
	local item = buildItem(kind, count or 1)
	if item == nil then
		error("[Carry] ไม่รู้จักชนิดของ " .. kind)
	end
	item.model:PivotTo(CFrame.new(position))
	item.model.Parent = Carry.getFolder()
	itemsByKind[kind] = item
	return item.model
end

-- สร้างของบนพื้นใต้จุด near
function Carry.spawnItemOnGround(kind: string, near: Vector3, count: number?): Model
	local model = Carry.spawnItem(kind, near, count)
	local item = itemsByKind[kind]
	if item ~= nil then
		placeOnGround(item, near)
	end
	return model
end

-- กึ่งกลาง Body สูงจากพื้นเท่าไรตอนวางบนพื้น (ให้ Mission คิดจุดลงของตะกร้า)
function Carry.restHeight(kind: string): number
	local def = CarryCfg.Items[kind]
	return if def ~= nil then def.restHeight else 1
end

-- คนที่ถือของชนิดนี้อยู่ (nil = ไม่มีของนี้ในภารกิจ หรืออยู่บนพื้น)
function Carry.getHolder(kind: string): Player?
	local item = itemsByKind[kind]
	if item == nil then
		return nil
	end
	return item.holder
end

-- ชนิดของที่ผู้เล่นถืออยู่ (nil = ไม่ได้ถือ)
function Carry.getHeldKind(player: Player): string?
	local item = heldBy[player]
	return if item ~= nil then item.kind else nil
end

-- จำนวนห่อขนมในมือ (0 ถ้าไม่ได้ถือขนมพระ)
function Carry.getHeldSnackCount(player: Player): number
	local item = heldBy[player]
	if item ~= nil and item.kind == "SnackPack" then
		return item.count
	end
	return 0
end

-- กินขนมจากห่อที่ถืออยู่ 1 ห่อ · หมดห่อแล้วของหายไป · คืน true ถ้ากินได้
function Carry.consumeHeldSnack(player: Player): boolean
	local item = heldBy[player]
	if item == nil or item.kind ~= "SnackPack" or item.count <= 0 then
		return false
	end
	item.count -= 1
	if item.count <= 0 then
		Carry.destroyItem("SnackPack")
	else
		refreshItemAttributes(item)
	end
	return true
end

-- ภารกิจจบ/เริ่มใหม่: คนถือทุกคนปล่อยของ (เคลียร์สถานะถือ + carrying) แล้วลบของทั้งหมด
function Carry.clearAll()
	local kinds: { string } = {}
	for kind in itemsByKind do
		table.insert(kinds, kind)
	end
	for _, kind in kinds do
		Carry.destroyItem(kind)
	end
end

-- ผู้เล่นออกเกม: ของที่ถือหล่นตรงนั้น
local function onPlayerRemoving(player: Player)
	local item = heldBy[player]
	if item ~= nil then
		dropAtHolder(item)
	end
	heldBy[player] = nil
end

-- canInteractFn(player) → true เมื่อภารกิจอยู่ช่วง InMission และผู้เล่นร่วมภารกิจ (Mission เป็นคนตัดสิน)
function Carry.init(canInteractFn: (Player) -> boolean, safeSpotFn: () -> Vector3?)
	canInteract = canInteractFn
	getSafeSpot = safeSpotFn
	Remotes.remoteEvent("CarryPickUp").OnServerEvent:Connect(onPickUp) -- (itemName: string)
	Remotes.remoteEvent("CarryDrop").OnServerEvent:Connect(onDrop) -- ()
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return Carry
