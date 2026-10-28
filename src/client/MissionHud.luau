--!strict
-- MissionHud: ส่วนของ HUD ที่เกี่ยวกับภารกิจ — ถือของ / ถวายอาหาร / กินขนม / เป้าหมาย / เลือดชั่วคราว / ข้อความจากพระ
-- client "โง่": ส่งแค่เจตนา (CarryPickUp / CarryDrop / OfferFood / EatSnack) แล้ววาดตามสถานะที่เซิร์ฟเวอร์ส่งมา
-- - ข้อมูลที่เห็นมาจาก: MissionState (ผ่าน LobbyUi.onSnapshot) · Attribute ของ Character (CarryKind, CarryCount, TempHealth)
--   · Attribute ของของใน Workspace.MissionObjects (ItemKind, Held) · DataChanged (ขนมที่เซฟไว้)
-- - ปุ่มตามสถานการณ์ (ถวาย/หยิบ) ใช้ปุ่มกลางขวา hud.context ร่วมกับปุ่มชุบ — Controls เรียก getContext() ทุกเฟรม
--   ลำดับความสำคัญ: ชุบเพื่อน (Controls) > ถวายอาหาร > หยิบของใกล้สุด
-- - ระยะทุกอย่างที่นี่ใช้แค่ "โชว์ปุ่ม" — เซิร์ฟเวอร์คิดระยะจริงซ้ำเองทุกครั้ง

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Hud = require(script.Parent.Hud)

export type ContextAction = {
	kind: string, -- "offer" (ถวายอาหาร) | "pickup" (หยิบของ)
	text: string, -- ข้อความบนปุ่ม
	itemName: string?, -- ชนิดของที่จะหยิบ (kind = "pickup")
}

export type Api = {
	onSnapshot: (snapshot: { [string]: any }) -> (),
	onData: (payload: any) -> (),
	getContext: () -> ContextAction?,
	activate: (action: ContextAction) -> (),
}

local MissionHud = {}

local MAX_BANNER_SECONDS = 10 -- ไม่เชื่อค่าเวลาจากเซิร์ฟเวอร์เกินนี้ (กันค้างจอ)

function MissionHud.start(hud: Hud.Refs): Api
	local player = Players.LocalPlayer
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local pickUpRemote = remotes:WaitForChild("CarryPickUp") :: RemoteEvent
	local dropRemote = remotes:WaitForChild("CarryDrop") :: RemoteEvent
	local offerRemote = remotes:WaitForChild("OfferFood") :: RemoteEvent
	local eatRemote = remotes:WaitForChild("EatSnack") :: RemoteEvent
	local toastRemote = remotes:WaitForChild("MissionToast") :: RemoteEvent

	-- สถานะจากเซิร์ฟเวอร์
	local active = false -- อยู่ในภารกิจ (ช่วง InMission และเป็นผู้ร่วมภารกิจ)
	local offered = false
	local kutiPos: Vector3? = nil
	local rocketPos: Vector3? = nil
	local savedSnacks = 0 -- ขนมที่เซฟไว้ในตัว (จาก DataChanged)

	local pickupActions: { [string]: ContextAction } = {}
	local offerAction: ContextAction = { kind = "offer", text = "ถวายอาหาร", itemName = nil }

	-- ===== อ่านสถานะตัวเอง =====
	local function ownCharacter(): Model?
		return player.Character
	end

	local function ownRoot(): BasePart?
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

	-- ชนิดของที่ถืออยู่ ("" = ไม่ได้ถือ) และจำนวนห่อขนมในมือ
	local function heldKind(): string
		local character = player.Character
		if character == nil then
			return ""
		end
		local value = character:GetAttribute("CarryKind")
		return if type(value) == "string" then value else ""
	end

	local function heldCount(): number
		local character = player.Character
		if character == nil then
			return 0
		end
		local value = character:GetAttribute("CarryCount")
		return if type(value) == "number" then value else 0
	end

	local function pivotPositionOf(inst: Instance): Vector3?
		if inst:IsA("Model") then
			return inst:GetPivot().Position
		elseif inst:IsA("BasePart") then
			return inst.Position
		end
		return nil
	end

	-- ===== ปุ่มตามสถานการณ์ (ถวายอาหาร / หยิบของ) =====
	local function getContext(): ContextAction?
		if not active or ownStateName() ~= "Alive" then
			return nil
		end
		local root = ownRoot()
		local folder = Workspace:FindFirstChild(Config.Mission.ObjectsFolderName)
		if root == nil or folder == nil then
			return nil
		end
		local kind = heldKind()

		-- 2) ถวายอาหาร: ถือตะกร้า ยังไม่เคยถวาย และอยู่ใกล้พระ
		if kind == "FoodBasket" then
			if not offered then
				local monk = folder:FindFirstChild(Config.Monk.Name)
				local monkPos = if monk ~= nil then pivotPositionOf(monk) else nil
				if monkPos ~= nil and (monkPos - root.Position).Magnitude <= Config.Monk.OfferRange then
					return offerAction
				end
			end
			return nil
		end
		if kind ~= "" then
			return nil -- ถือของอื่นอยู่ หยิบเพิ่มไม่ได้
		end

		-- 3) หยิบของที่ใกล้สุดในระยะ (ของที่มีคนถืออยู่ข้าม)
		local nearest: ContextAction? = nil
		local nearestDist = Config.Carry.PickupRange
		for _, child in folder:GetChildren() do
			local itemKind = child:GetAttribute("ItemKind")
			if type(itemKind) == "string" and child:GetAttribute("Held") ~= true then
				local position = pivotPositionOf(child)
				local def = Config.Carry.Items[itemKind]
				if position ~= nil and def ~= nil then
					local dist = (position - root.Position).Magnitude
					if dist <= nearestDist then
						nearestDist = dist
						local action = pickupActions[itemKind]
						if action == nil then
							action = { kind = "pickup", text = "หยิบ" .. def.displayName, itemName = itemKind }
							pickupActions[itemKind] = action
						end
						nearest = action
					end
				end
			end
		end
		return nearest
	end

	local function activate(action: ContextAction)
		if action.kind == "offer" then
			offerRemote:FireServer()
		elseif action.kind == "pickup" and action.itemName ~= nil then
			pickUpRemote:FireServer(action.itemName)
		end
	end

	-- ===== กินขนม / วางของ =====
	local lastEatClock = 0
	local function requestEat()
		if not active or ownStateName() ~= "Alive" then
			return
		end
		local now = os.clock()
		if now - lastEatClock < Config.Snacks.EatMinIntervalSeconds then
			return
		end
		lastEatClock = now
		eatRemote:FireServer()
	end

	local function requestDrop()
		if heldKind() ~= "" then
			dropRemote:FireServer()
		end
	end

	hud.eat.Activated:Connect(requestEat)
	hud.drop.Activated:Connect(requestDrop)

	-- คีย์ลัดบนคอม (มือถือใช้ปุ่มบนจอ): F = กินขนม · Q = วางของ
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if input.KeyCode == Enum.KeyCode.F then
			requestEat()
		elseif input.KeyCode == Enum.KeyCode.Q then
			requestDrop()
		end
	end)

	-- ข้อความจากเซิร์ฟเวอร์ (พระให้ของ ฯลฯ) — ตรวจชนิดค่าและจำกัดเวลาโชว์
	toastRemote.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		local text = payload.text
		local seconds = payload.seconds
		if type(text) ~= "string" or type(seconds) ~= "number" or seconds ~= seconds then
			return
		end
		hud.showBanner(text, math.clamp(seconds, 1, MAX_BANNER_SECONDS))
	end)

	-- ===== วนอัปเดตทุกเฟรม (HUD cache ค่าเดิม เขียนเมื่อเปลี่ยนเท่านั้น) =====
	-- ข้อความเป้าหมาย: สร้างใหม่เฉพาะเมื่อ (สถานะภารกิจ / ถวายแล้วหรือยัง / ระยะเมตรที่ปัดแล้ว) เปลี่ยน
	local lastObjKey = ""
	local lastObjText: string? = nil
	local function objectiveText(root: BasePart?): string?
		if not active then
			lastObjKey = "off"
			lastObjText = nil
			return nil
		end
		local target = if offered then rocketPos else kutiPos
		local meters = -1 -- -1 = ไม่รู้ระยะ
		if target ~= nil and root ~= nil then
			local dx, dz = target.X - root.Position.X, target.Z - root.Position.Z
			meters = math.floor(math.sqrt(dx * dx + dz * dz) * Config.Map.MetersPerStud + 0.5)
		end
		local key = (if offered then "R" else "K") .. meters
		if key ~= lastObjKey then
			lastObjKey = key
			local title = if offered
				then "ไปฐานบั้งไฟ"
				else "พาตะกร้าไปถวายพระที่กุฏิ"
			lastObjText = if meters >= 0 then title .. "\nอีก " .. meters .. " ม." else title
		end
		return lastObjText
	end

	local lastSnackCount = -1
	local lastSnackText = ""

	RunService.RenderStepped:Connect(function()
		local character = ownCharacter()
		local root = ownRoot()
		local alive = ownStateName() == "Alive"
		local kind = heldKind()

		hud.setObjective(objectiveText(root))

		-- เลือดชั่วคราว: หมดเวลาแล้วถือว่าไม่มี (เซิร์ฟเวอร์จะเคลียร์ตามภายใน ~0.2 วิ)
		local temp = 0
		if character ~= nil then
			local value = character:GetAttribute("TempHealth")
			local endsAt = character:GetAttribute("TempHealthEndsAt")
			if type(value) == "number" and type(endsAt) == "number" and endsAt > Workspace:GetServerTimeNow() then
				temp = value
			end
		end
		hud.setTempHealth(temp, Config.Snacks.TempHealth)

		-- ปุ่มกินขนม: n = ห่อในมือ (ถ้าถือขนมพระ) + ขนมที่เซฟไว้ในตัว
		local snackCount = savedSnacks + (if kind == "SnackPack" then heldCount() else 0)
		local showEat = active and alive and snackCount > 0
		if snackCount ~= lastSnackCount then
			lastSnackCount = snackCount
			lastSnackText = "กินขนม (" .. snackCount .. ")"
		end
		hud.setEat(showEat, lastSnackText)
		hud.setDrop(active and kind ~= "" and ownStateName() ~= "Dead")
	end)

	return {
		onSnapshot = function(snapshot: { [string]: any })
			active = snapshot.phase == "InMission" and snapshot.inLobby ~= true
			offered = snapshot.offered == true
			local markers = snapshot.markers
			if type(markers) == "table" then
				local kuti: Vector3? = nil
				local rocket: Vector3? = nil
				for _, marker in markers do
					if type(marker) == "table" and type(marker.x) == "number" and type(marker.z) == "number" then
						-- ใช้แค่ระนาบ X-Z (ความสูงไม่ใช้คิดระยะ)
						if marker.name == "Kuti" then
							kuti = Vector3.new(marker.x, 0, marker.z)
						elseif marker.name == "RocketPad" then
							rocket = Vector3.new(marker.x, 0, marker.z)
						end
					end
				end
				kutiPos, rocketPos = kuti, rocket
			end
		end,
		onData = function(payload: any)
			if type(payload) == "table" and type(payload.snacks) == "number" then
				savedSnacks = payload.snacks
			end
		end,
		getContext = getContext,
		activate = activate,
	}
end

return MissionHud
