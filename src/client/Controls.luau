--!strict
-- Controls: ต่อปุ่มบนจอ/คีย์บอร์ด/เมาส์ เข้ากับคำขอไปเซิร์ฟเวอร์ + อัปเดต HUD ทุกเฟรม
-- client ส่งแค่ "ทิศที่เล็ง" กับคำขอ — เซิร์ฟเวอร์ตัดสินว่าโดนไหม/กระสุนพอไหม/ชุบได้ไหม
-- ปุ่มบนจอ = ทางหลัก (มือถือ) · คีย์บอร์ด: คลิกซ้ายยิง · คลิกขวาเล็ง · R เปลี่ยนแม็ก · 1/2/3 สลับช่อง · G ขว้างประทัด · E กดค้างชุบ

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Hud = require(script.Parent.Hud)
local Fx = require(script.Parent.Fx)

local SLOT_GUN = 1
local SLOT_FIRECRACKER = 2
local SLOT_BROOM = 3
local CLIENT_INTERVAL_MARGIN = 1.05 -- ส่งช้ากว่าเพดานของเซิร์ฟเวอร์นิดหน่อย กันคำขอถูกทิ้งเพราะเน็ตกระตุก

type CombatState = {
	slot: number,
	gunId: string?,
	ammo: number,
	magSize: number,
	firecrackers: number,
	reloadEndsAt: number,
	carrying: boolean,
}

local Controls = {}

function Controls.start(hud: Hud.Refs): { onData: (payload: any) -> () }
	local player = Players.LocalPlayer
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local fireRemote = remotes:WaitForChild("CombatFire") :: RemoteEvent
	local reloadRemote = remotes:WaitForChild("CombatReload") :: RemoteEvent
	local throwRemote = remotes:WaitForChild("CombatThrow") :: RemoteEvent
	local swingRemote = remotes:WaitForChild("CombatSwing") :: RemoteEvent
	local selectSlotRemote = remotes:WaitForChild("CombatSelectSlot") :: RemoteEvent
	local selectGunRemote = remotes:WaitForChild("CombatSelectGun") :: RemoteEvent
	local stateRemote = remotes:WaitForChild("CombatState") :: RemoteEvent
	local fxRemote = remotes:WaitForChild("CombatFx") :: RemoteEvent
	local reviveRemote = remotes:WaitForChild("ReviveHold") :: RemoteEvent

	local combat: CombatState = {
		slot = SLOT_GUN,
		gunId = nil,
		ammo = 0,
		magSize = 0,
		firecrackers = 0,
		reloadEndsAt = 0,
		carrying = false,
	}
	local ownedGuns: { string } = {}

	local firing = false
	local aiming = false
	local reviveHeld = false
	local activeReviveTarget: number? = nil
	local lastPrimaryClock = 0
	local usingTouch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

	-- ===== ตัวช่วยอ่านสถานะตัวเอง =====
	local function ownCharacter(): (Model?, Humanoid?)
		local character = player.Character
		if character == nil then
			return nil, nil
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		return character, humanoid
	end

	local function ownStateName(): string
		local character = player.Character
		if character == nil then
			return "Dead"
		end
		local value = character:GetAttribute("State")
		if type(value) == "string" then
			return value
		end
		return "Alive"
	end

	local function currentGunDef(): Config.GunDef?
		local id = combat.gunId
		if id == nil then
			return nil
		end
		return Config.Guns[id]
	end

	-- ===== เล็ง =====
	-- เล็งจากกลางจอ (มือถือ) หรือตำแหน่งเมาส์ (คอม) แล้วคิดทิศจาก "หัวตัวละคร" ไปยังจุดนั้น
	local function applyAimAssist(dir: Vector3, origin: Vector3): Vector3
		if not UserInputService.TouchEnabled then
			return dir
		end
		local bestAngle = math.rad(Config.Hud.AimAssistDegrees)
		local bestDir: Vector3? = nil
		for _, inst in CollectionService:GetTagged("Monkey") do
			if inst:IsA("Model") and inst:GetAttribute("Dead") ~= true then -- ข้ามซาก
				local toMonkey = inst:GetPivot().Position - origin
				local dist = toMonkey.Magnitude
				if dist > 0.5 and dist <= Config.Hud.AimAssistRange then
					local angle = math.acos(math.clamp(toMonkey.Unit:Dot(dir), -1, 1))
					if angle < bestAngle then
						bestAngle = angle
						bestDir = toMonkey.Unit
					end
				end
			end
		end
		if bestDir ~= nil then
			local blended = dir:Lerp(bestDir, Config.Hud.AimAssistStrength)
			if blended.Magnitude > 0.01 then
				return blended.Unit
			end
		end
		return dir
	end

	local function getAimDirection(): Vector3?
		local character = player.Character
		local camera = Workspace.CurrentCamera
		if character == nil or camera == nil then
			return nil
		end
		local head = character:FindFirstChild("Head")
		if head == nil or not head:IsA("BasePart") then
			return nil
		end
		local screenPoint: Vector2
		if usingTouch then
			-- ใช้กลางครอสแฮร์จริง (พิกัดเดียวกับ viewport เพราะ Hud ตั้ง IgnoreGuiInset = true)
			local ch = hud.crosshair
			if ch.AbsoluteSize.X > 0 then
				screenPoint = ch.AbsolutePosition + ch.AbsoluteSize / 2
			else
				screenPoint = camera.ViewportSize / 2
			end
		else
			screenPoint = UserInputService:GetMouseLocation()
		end
		local ray = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local reach = Config.Combat.MaxRange
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * reach, params)
		local target = if hit ~= nil then hit.Position else ray.Origin + ray.Direction * reach
		local offset = target - head.Position
		local dir = if offset.Magnitude > 0.5 then offset.Unit else ray.Direction.Unit
		return applyAimAssist(dir, head.Position)
	end

	-- หันตัวไปทางที่ยิง (แนวราบ)
	local function faceDirection(dir: Vector3)
		local character = player.Character
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if root ~= nil and root:IsA("BasePart") then
			local flat = Vector3.new(dir.X, 0, dir.Z)
			if flat.Magnitude > 0.05 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
			end
		end
	end

	local function setAiming(on: boolean)
		if on and (combat.carrying or ownStateName() ~= "Alive") then
			on = false -- ถือของ/ล้ม/ตาย เล็กไม่ได้
		end
		aiming = on
		hud.setAimActive(on)
		local camera = Workspace.CurrentCamera
		if camera ~= nil then
			local fov = if on then Config.Hud.AimFov else Config.Hud.NormalFov
			TweenService:Create(camera, TweenInfo.new(0.15), { FieldOfView = fov }):Play()
		end
	end

	-- ===== การกระทำ =====
	local function requestReload()
		if ownStateName() ~= "Alive" or combat.slot ~= SLOT_GUN or combat.carrying then
			return
		end
		if combat.reloadEndsAt ~= 0 or combat.ammo >= combat.magSize then
			return
		end
		reloadRemote:FireServer()
	end

	local function primaryInterval(): number
		if combat.slot == SLOT_GUN then
			local gun = currentGunDef()
			return if gun ~= nil then 1 / gun.fireRate else 0.3
		elseif combat.slot == SLOT_FIRECRACKER then
			return Config.Firecracker.ThrowCooldownSeconds
		end
		return Config.Broom.SwingCooldownSeconds
	end

	local function throwFirecracker()
		if ownStateName() ~= "Alive" or combat.firecrackers <= 0 then
			return
		end
		local dir = getAimDirection()
		if dir == nil then
			return
		end
		faceDirection(dir)
		combat.firecrackers -= 1
		throwRemote:FireServer(dir)
	end

	-- ปุ่มยิงใหญ่: ทำตามช่องอาวุธที่เลือก (ปืน = ยิง · ประทัด = ขว้าง · ไม้กวด = ฟาด)
	local function tryPrimary()
		if ownStateName() ~= "Alive" then
			return
		end
		local now = os.clock()
		if now - lastPrimaryClock < primaryInterval() * CLIENT_INTERVAL_MARGIN then
			return
		end
		if combat.slot == SLOT_GUN then
			if combat.reloadEndsAt ~= 0 then
				return
			end
			if combat.ammo <= 0 then
				requestReload() -- แม็กหมด → เปลี่ยนให้เอง
				return
			end
			local dir = getAimDirection()
			if dir == nil then
				return
			end
			lastPrimaryClock = now
			faceDirection(dir)
			combat.ammo -= 1
			fireRemote:FireServer(dir)
		elseif combat.slot == SLOT_FIRECRACKER then
			lastPrimaryClock = now
			throwFirecracker()
		else
			local dir = getAimDirection()
			if dir == nil then
				return
			end
			lastPrimaryClock = now
			faceDirection(dir)
			swingRemote:FireServer(dir)
		end
	end

	local function selectSlot(slot: number)
		-- กดช่อง 1 ซ้ำ = วนไปปืนกระบอกถัดไปที่มี
		if slot == SLOT_GUN and combat.slot == SLOT_GUN and #ownedGuns > 1 then
			local sorted = table.clone(ownedGuns)
			table.sort(sorted, function(a: string, b: string)
				local ga, gb = Config.Guns[a], Config.Guns[b]
				local pa = if ga ~= nil then ga.price else 0
				local pb = if gb ~= nil then gb.price else 0
				return pa < pb
			end)
			local index = table.find(sorted, combat.gunId or "") or 0
			local nextId = sorted[(index % #sorted) + 1]
			selectGunRemote:FireServer(nextId)
			return
		end
		combat.slot = slot -- เปลี่ยนในจอทันที เซิร์ฟเวอร์จะส่งค่าจริงทับ
		selectSlotRemote:FireServer(slot)
	end

	-- ===== ชุบเพื่อน =====
	local function findReviveTarget(): Player?
		local character = player.Character
		local myRoot = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if myRoot == nil or not myRoot:IsA("BasePart") then
			return nil
		end
		local best: Player? = nil
		local bestDist = Config.Player.ReviveRange
		for _, other in Players:GetPlayers() do
			local otherChar = other.Character
			if other ~= player and otherChar ~= nil and otherChar:GetAttribute("State") == "Downed" then
				local otherRoot = otherChar:FindFirstChild("HumanoidRootPart")
				if otherRoot ~= nil and otherRoot:IsA("BasePart") then
					local dist = (otherRoot.Position - myRoot.Position).Magnitude
					if dist <= bestDist then
						bestDist = dist
						best = other
					end
				end
			end
		end
		return best
	end

	-- ===== ต่อปุ่มบนจอ =====
	Hud.bindHold(hud.fire, function()
		firing = true
		tryPrimary()
	end, function()
		firing = false
	end)
	hud.aim.Activated:Connect(function()
		setAiming(not aiming)
	end)
	hud.reload.Activated:Connect(requestReload)
	hud.throw.Activated:Connect(throwFirecracker)
	Hud.bindHold(hud.context, function()
		reviveHeld = true
	end, function()
		reviveHeld = false
	end)
	for i, button in hud.slots do
		button.Activated:Connect(function()
			selectSlot(i)
		end)
	end

	-- ===== คีย์บอร์ด/เมาส์ (คอม) =====
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		-- จำว่าอินพุตล่าสุดเป็นนิ้วหรือเมาส์ (ไว้เลือกว่าเล็งจากกลางจอหรือตำแหน่งเมาส์)
		if input.UserInputType == Enum.UserInputType.Touch then
			usingTouch = true
		elseif
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Keyboard
		then
			usingTouch = false
		end
		if processed then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 then
			usingTouch = false
			firing = true
			tryPrimary()
		elseif t == Enum.UserInputType.MouseButton2 then
			usingTouch = false
			setAiming(true)
		elseif t == Enum.UserInputType.Keyboard then
			local key = input.KeyCode
			if key == Enum.KeyCode.R then
				requestReload()
			elseif key == Enum.KeyCode.One then
				selectSlot(SLOT_GUN)
			elseif key == Enum.KeyCode.Two then
				selectSlot(SLOT_FIRECRACKER)
			elseif key == Enum.KeyCode.Three then
				selectSlot(SLOT_BROOM)
			elseif key == Enum.KeyCode.G then
				throwFirecracker()
			elseif key == Enum.KeyCode.E then
				reviveHeld = true
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 then
			firing = false
		elseif t == Enum.UserInputType.MouseButton2 then
			setAiming(false)
		elseif t == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.E then
			reviveHeld = false
		end
	end)

	-- ===== รับข้อมูลจากเซิร์ฟเวอร์ =====
	stateRemote.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if type(payload.slot) == "number" then
			combat.slot = payload.slot
		end
		combat.gunId = if type(payload.gunId) == "string" then payload.gunId else nil
		combat.ammo = if type(payload.ammo) == "number" then payload.ammo else 0
		combat.magSize = if type(payload.magSize) == "number" then payload.magSize else 0
		combat.firecrackers = if type(payload.firecrackers) == "number" then payload.firecrackers else 0
		combat.reloadEndsAt = if type(payload.reloadEndsAt) == "number" then payload.reloadEndsAt else 0
		combat.carrying = payload.carrying == true
		if combat.carrying then
			setAiming(false)
		end
	end)

	fxRemote.OnClientEvent:Connect(function(origin: any, ends: any)
		if typeof(origin) ~= "Vector3" or type(ends) ~= "table" then
			return
		end
		for _, endPoint in ends do
			if typeof(endPoint) == "Vector3" then
				Fx.tracer(origin, endPoint)
			end
		end
	end)

	-- ขอสถานะล่าสุดจากเซิร์ฟเวอร์ (ตอนเริ่ม และทุกครั้งที่เกิดใหม่) — ส่งค่าอะไรก็ได้ที่ไม่ใช่ 1–3 = ขอดูเฉย ๆ
	player.CharacterAdded:Connect(function()
		setAiming(false)
		task.wait(0.5)
		selectSlotRemote:FireServer(0)
	end)
	selectSlotRemote:FireServer(0)

	-- ===== วนอัปเดตทุกเฟรม =====
	local slotNames = { "ปืน", "ประทัด", "ไม้กวด" }

	RunService.Heartbeat:Connect(function()
		-- ยิงรัว: ปืนกลหรือไม้กวด กดค้างแล้วยิง/ฟาดซ้ำ
		if firing then
			local gun = currentGunDef()
			if (combat.slot == SLOT_GUN and gun ~= nil and gun.automatic) or combat.slot == SLOT_BROOM then
				tryPrimary()
			end
		end
	end)

	-- cache ค่าเดิม ไม่เขียน Text/property ซ้ำทุกเฟรม (ประหยัดเครื่องมือถือ)
	local lastHp, lastMaxHp = -1, -1
	local lastOverlayKey = ""
	local lastLabelKey = ""
	local lastAmmoKey = ""
	local lastThrowEnabled: boolean? = nil
	local lastCrosshair: boolean? = nil
	local lastContext: boolean? = nil
	local lastProgress: number? = nil
	local lastProgressText = ""

	RunService.RenderStepped:Connect(function()
		local character, humanoid = ownCharacter()
		local stateName = ownStateName()

		if humanoid ~= nil and (humanoid.Health ~= lastHp or humanoid.MaxHealth ~= lastMaxHp) then
			lastHp, lastMaxHp = humanoid.Health, humanoid.MaxHealth
			hud.setHealth(lastHp, lastMaxHp)
		end

		-- จอล้ม / ตาย (ยังไม่มีตัวละคร = ไม่ขึ้นจอ "ตายแล้ว")
		local remaining = 0
		if character ~= nil then
			local endsAt = character:GetAttribute("StateEndsAt")
			if type(endsAt) == "number" then
				remaining = endsAt - Workspace:GetServerTimeNow()
			end
		end
		local overlayKind = if character == nil then "Alive" else stateName
		local overlayKey = overlayKind .. ":" .. math.max(0, math.ceil(remaining))
		if overlayKey ~= lastOverlayKey then
			lastOverlayKey = overlayKey
			hud.setOverlay(overlayKind, remaining)
		end
		-- แถบเลือดตอนล้ม (แสดงเฉพาะตอนล้ม · Hud cache ค่าเดิมเอง)
		local downedFraction: number? = nil
		if stateName == "Downed" and character ~= nil then
			local dh = character:GetAttribute("DownedHealth")
			if type(dh) == "number" then
				downedFraction = dh / Config.Player.DownedHealth
			end
		end
		hud.setDownedHealth(downedFraction)
		if stateName ~= "Alive" and aiming then
			setAiming(false)
		end

		-- แถบอาวุธ + กระสุน
		local gun = currentGunDef()
		local gunName = if gun ~= nil then gun.displayName else slotNames[1]
		local labelKey = gunName .. "|" .. combat.firecrackers .. "|" .. combat.slot
		if labelKey ~= lastLabelKey then
			lastLabelKey = labelKey
			hud.setSlotLabels({ gunName, slotNames[2] .. " ×" .. combat.firecrackers, slotNames[3] }, combat.slot)
		end
		local ammoKey = combat.slot
			.. "|"
			.. combat.ammo
			.. "|"
			.. combat.magSize
			.. "|"
			.. combat.firecrackers
			.. "|"
			.. tostring(combat.reloadEndsAt ~= 0)
		if ammoKey ~= lastAmmoKey then
			lastAmmoKey = ammoKey
			local ammoText: string
			if combat.slot == SLOT_GUN then
				if combat.reloadEndsAt ~= 0 then
					ammoText = "กำลังเปลี่ยนแม็ก…"
				else
					ammoText = combat.ammo .. " / " .. combat.magSize
				end
				ammoText ..= "  ·  ประทัด ×" .. combat.firecrackers
			elseif combat.slot == SLOT_FIRECRACKER then
				ammoText = "ประทัด ×" .. combat.firecrackers
			else
				ammoText = "ไม้กวด ใช้ได้ไม่จำกัด"
			end
			hud.setAmmoText(ammoText)
		end
		local throwEnabled = combat.firecrackers > 0 and stateName == "Alive"
		if throwEnabled ~= lastThrowEnabled then
			lastThrowEnabled = throwEnabled
			hud.setThrowEnabled(throwEnabled)
		end
		local crosshairVisible = stateName == "Alive"
		if crosshairVisible ~= lastCrosshair then
			lastCrosshair = crosshairVisible
			hud.crosshair.Visible = crosshairVisible
		end

		-- ปุ่มชุบ (โผล่เมื่ออยู่ใกล้เพื่อนที่ล้ม)
		local target = if stateName == "Alive" then findReviveTarget() else nil
		local contextVisible = target ~= nil
		if contextVisible ~= lastContext then
			lastContext = contextVisible
			hud.setContext(contextVisible, "กดค้างเพื่อชุบ")
		end
		if reviveHeld and target ~= nil then
			if activeReviveTarget ~= target.UserId then
				activeReviveTarget = target.UserId
				reviveRemote:FireServer(target.UserId, true)
			end
		elseif activeReviveTarget ~= nil then
			reviveRemote:FireServer(activeReviveTarget, false)
			activeReviveTarget = nil
		end

		-- แถบความคืบหน้าการชุบ (ทั้งฝั่งคนชุบและคนถูกชุบ)
		local progress: number? = nil
		local progressText = ""
		if target ~= nil and target.Character ~= nil then
			local p = target.Character:GetAttribute("ReviveProgress")
			if type(p) == "number" and p > 0 then
				progress = p
				progressText = "กำลังชุบ…"
			end
		elseif stateName == "Downed" and character ~= nil then
			local p = character:GetAttribute("ReviveProgress")
			if type(p) == "number" and p > 0 then
				progress = p
				progressText = "เพื่อนกำลังชุบคุณ…"
			end
		end
		if progress ~= lastProgress or progressText ~= lastProgressText then
			lastProgress = progress
			lastProgressText = progressText
			hud.setProgress(progress, progressText)
		end
	end)

	return {
		onData = function(payload: any)
			if type(payload) ~= "table" then
				return
			end
			if type(payload.money) == "number" then
				hud.setMoney(payload.money)
			end
			if type(payload.ownedGuns) == "table" then
				local list: { string } = {}
				for _, id in payload.ownedGuns do
					if type(id) == "string" then
						table.insert(list, id)
					end
				end
				ownedGuns = list
			end
			if type(payload.message) == "string" then
				warn("[Client]", payload.message)
			end
		end,
	}
end

return Controls
