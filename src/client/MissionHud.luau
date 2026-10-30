--!strict
-- MissionHud: ส่วนของ HUD ที่เกี่ยวกับภารกิจ — ถือของ / ถวายอาหาร / กินขนม / บั้งไฟ / เป้าหมาย / เลือดชั่วคราว / ข้อความจากพระ
-- client "โง่": ส่งแค่เจตนา (CarryPickUp / CarryDrop / OfferFood / EatSnack / RocketIgnite / RocketTie) แล้ววาดตามสถานะที่เซิร์ฟเวอร์ส่งมา
-- - ข้อมูลที่เห็นมาจาก: MissionState (ผ่าน LobbyUi.onSnapshot) · Attribute ของ Character (CarryKind, CarryCount, TempHealth)
--   · Attribute ของของใน Workspace.MissionObjects (ItemKind, Held) · DataChanged (ขนมที่เซฟไว้)
-- - ปุ่มตามสถานการณ์ (ถวาย/หยิบ) ใช้ปุ่มกลางขวา hud.context ร่วมกับปุ่มชุบ — Controls เรียก getContext() ทุกเฟรม
--   ลำดับความสำคัญ: ชุบเพื่อน (Controls) > ถวายอาหาร > หยิบของใกล้สุด (ถ้ามือว่าง) > จุดชนวน/มัดตัวบั้งไฟ
-- - ระยะทุกอย่างที่นี่ใช้แค่ "โชว์ปุ่ม" — เซิร์ฟเวอร์คิดระยะจริงซ้ำเองทุกครั้ง

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Hud = require(script.Parent.Hud)

export type ContextAction = {
	kind: string, -- "offer" (ถวายอาหาร) | "pickup" (หยิบของ) | "ignite" (จุดชนวนบั้งไฟ) | "tie" (มัดตัวขึ้นบั้งไฟ) | "untie" (แก้มัด)
	text: string, -- ข้อความบนปุ่ม
	itemName: string?, -- ชนิดของที่จะหยิบ (kind = "pickup")
}

export type Api = {
	onSnapshot: (snapshot: { [string]: any }) -> (),
	onData: (payload: any) -> (),
	getContext: () -> ContextAction?,
	isTied: () -> boolean, -- มัดตัวบนบั้งไฟอยู่ (ปุ่มกลางขวาต้องเป็น "แก้มัด" ไม่ใช่ "ชุบเพื่อน")
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
	local igniteRemote = remotes:WaitForChild("RocketIgnite") :: RemoteEvent
	local tieRemote = remotes:WaitForChild("RocketTie") :: RemoteEvent
	local untieRemote = remotes:WaitForChild("RocketUntie") :: RemoteEvent

	-- สถานะจากเซิร์ฟเวอร์
	local active = false -- อยู่ในภารกิจ (ช่วง InMission / Rocket และเป็นผู้ร่วมภารกิจ)
	local phaseName = "Lobby"
	local rocketInfo: { [string]: any }? = nil -- สถานะบนบั้งไฟจากเซิร์ฟเวอร์ (มีเฉพาะช่วง Rocket)
	local offered = false
	local kutiPos: Vector3? = nil
	local rocketPos: Vector3? = nil
	local savedSnacks = 0 -- ขนมที่เซฟไว้ในตัว (จาก DataChanged)

	local pickupActions: { [string]: ContextAction } = {}
	local offerAction: ContextAction = { kind = "offer", text = "ถวายอาหาร", itemName = nil }
	local igniteAction: ContextAction =
		{ kind = "ignite", text = "จุดชนวนบั้งไฟ", itemName = nil }
	local tieAction: ContextAction =
		{ kind = "tie", text = "มัดตัวขึ้นบั้งไฟ", itemName = nil }
	local untieAction: ContextAction = { kind = "untie", text = "แก้มัด", itemName = nil }
	local waitActions: { [number]: ContextAction } = {} -- ปุ่มข้อความล้วน "ยื้อไว้! มัดตัวได้ใน N วิ" (กดแล้วไม่ส่งอะไร) แยกตาม N

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

	-- ===== ปุ่มตามสถานการณ์ (ถวายอาหาร / หยิบของ / จุดชนวน / มัดตัว) =====
	-- ระยะแนวราบจากบั้งไฟ (จุด RocketPad) ใช้แค่โชว์ปุ่ม — เซิร์ฟเวอร์คิดระยะจริงซ้ำเอง
	local function nearRocket(root: BasePart, range: number): boolean
		local target = rocketPos
		if target == nil then
			return false
		end
		local dx, dz = target.X - root.Position.X, target.Z - root.Position.Z
		return math.sqrt(dx * dx + dz * dz) <= range
	end

	local function isTiedNow(): boolean
		local info = rocketInfo
		return phaseName == "Rocket" and info ~= nil and info.mine == true
	end

	-- ปุ่มบั้งไฟ: ถวายอาหารแล้วอยู่ใกล้ → จุดชนวน · ช่วงนับถอยหลังยังมีที่ว่างและยังไม่ได้มัด → มัดตัว
	local function rocketAction(root: BasePart): ContextAction?
		if phaseName == "InMission" and offered then
			if nearRocket(root, Config.Rocket.IgniteRange) then
				return igniteAction
			end
		elseif phaseName == "Rocket" then
			local info = rocketInfo
			if info ~= nil and info.launching ~= true and info.mine ~= true then
				local freeSpots = info.freeSpots
				local endsAt = info.endsAt
				if
					type(freeSpots) == "number"
					and freeSpots > 0
					and type(endsAt) == "number"
					and endsAt > Workspace:GetServerTimeNow()
					and nearRocket(root, Config.Rocket.TieRange)
				then
					-- ต้องยื้อก่อน: มัดตัวได้เฉพาะ TieWindowSeconds วิสุดท้าย (เซิร์ฟเวอร์ตรวจซ้ำเอง)
					local untilTie = endsAt - Workspace:GetServerTimeNow() - Config.Rocket.TieWindowSeconds
					if untilTie > 0 then
						local n = math.ceil(untilTie)
						local waitAction = waitActions[n]
						if waitAction == nil then
							waitAction = {
								kind = "wait",
								text = "ยื้อไว้! มัดตัวได้ใน " .. n .. " วิ",
								itemName = nil,
							}
							waitActions[n] = waitAction
						end
						return waitAction
					end
					return tieAction
				end
			end
		end
		return nil
	end

	local function getContext(): ContextAction?
		if not active or ownStateName() ~= "Alive" then
			return nil
		end
		if isTiedNow() then
			-- มัดอยู่: ปุ่มกลางขวาเป็น "แก้มัด" จนกว่าจะยิงบั้งไฟ (เซิร์ฟเวอร์ตรวจซ้ำเอง)
			local info = rocketInfo
			local endsAt = if info ~= nil then info.endsAt else nil
			if
				info ~= nil
				and info.launching ~= true
				and type(endsAt) == "number"
				and endsAt > Workspace:GetServerTimeNow()
			then
				return untieAction
			end
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
				-- พระอยู่ใน MapObjects (โฟลเดอร์ถาวร) ไม่ใช่ MissionObjects ที่เก็บของภารกิจ
				local mapFolder = Workspace:FindFirstChild(Config.Map.ObjectsFolderName)
				local monk = if mapFolder ~= nil then mapFolder:FindFirstChild(Config.Monk.Name) else nil
				local monkPos = if monk ~= nil then pivotPositionOf(monk) else nil
				if monkPos ~= nil and (monkPos - root.Position).Magnitude <= Config.Monk.OfferRange then
					return offerAction
				end
			end
			return nil
		end
		if kind ~= "" then
			return rocketAction(root) -- ถือของอื่นอยู่ หยิบเพิ่มไม่ได้ (แต่จุดชนวน/มัดตัวได้ — ของติดตัวไปกับบั้งไฟ)
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
		if nearest ~= nil then
			return nearest -- มือว่างและมีของให้หยิบ: หยิบก่อน (ถุงเงิน/ขนมต้องขึ้นบั้งไฟไปด้วย)
		end
		return rocketAction(root)
	end

	local function activate(action: ContextAction)
		if action.kind == "offer" then
			offerRemote:FireServer()
		elseif action.kind == "pickup" and action.itemName ~= nil then
			pickUpRemote:FireServer(action.itemName)
		elseif action.kind == "ignite" then
			igniteRemote:FireServer()
		elseif action.kind == "tie" then
			tieRemote:FireServer()
		elseif action.kind == "untie" then
			untieRemote:FireServer()
		end
	end

	-- ===== กินขนม / วางของ =====
	local lastEatClock = 0

	-- มัดตัวบนบั้งไฟ/กำลังยิงขึ้นฟ้า: กินขนม/วางของไม่ได้ (ซ่อนปุ่มด้วย)
	local function actionsLocked(): boolean
		local info = rocketInfo
		return isTiedNow() or (phaseName == "Rocket" and info ~= nil and info.launching == true)
	end

	local function requestEat()
		if not active or ownStateName() ~= "Alive" or actionsLocked() then
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
		if heldKind() ~= "" and not actionsLocked() then
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

		-- ช่วงบั้งไฟ: นับถอยหลังทีละวินาที (เวลาจากเซิร์ฟเวอร์) · มัดแล้ว = ยื้อไว้ · ยังไม่มัด = บอกระยะไปบั้งไฟ
		local info = rocketInfo
		if phaseName == "Rocket" and info ~= nil then
			local endsAt = info.endsAt
			local secondsLeft = if type(endsAt) == "number"
				then math.max(0, math.ceil(endsAt - Workspace:GetServerTimeNow()))
				else 0
			local launching = info.launching == true
			local mine = info.mine == true
			local key = "RK|" .. tostring(launching) .. "|" .. tostring(mine) .. "|" .. secondsLeft .. "|" .. meters
			if key ~= lastObjKey then
				lastObjKey = key
				if launching then
					lastObjText = "บั้งไฟกำลังขึ้น!"
				elseif mine then
					lastObjText = "อยู่บนบั้งไฟแล้ว — ยื้อไว้!\nเหลือ "
						.. secondsLeft
						.. " วิ"
				elseif secondsLeft > Config.Rocket.TieWindowSeconds then
					-- ยังไม่ถึงช่วงมัดตัว: ต้องยื้อก่อน (ลิงกำลังบุก)
					lastObjText = "ยื้อไว้จนถึง "
						.. Config.Rocket.TieWindowSeconds
						.. " วิสุดท้าย แล้วมัดตัว\nเหลือ "
						.. secondsLeft
						.. " วิ"
				else
					lastObjText = "มัดตัวขึ้นบั้งไฟ! เหลือ "
						.. secondsLeft
						.. " วิ"
					if meters >= 0 then
						lastObjText ..= "\nอีก " .. meters .. " ม."
					end
				end
			end
			return lastObjText
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

	-- ===== แผงสถานะบั้งไฟ (ใต้ข้อความเป้าหมาย · โผล่เฉพาะช่วงนับถอยหลัง) =====
	-- บรรทัด 1: มัดแล้ว x/N + ชื่อคนมัด · บรรทัด 2: ถุงเงิน/ขนมขึ้นบั้งไฟแล้วหรือยัง (ใช้ตัวหนังสือ มี/ไม่มี ไม่พึ่งฟอนต์สัญลักษณ์)
	local rocketPanel = Instance.new("Frame")
	rocketPanel.Name = "RocketStatus"
	-- ขอบขวา 0.56 — ไม่ทับปุ่มโทรเรียกเพื่อน (0.62, 0.36) · ขอบซ้าย 0.20 พ้นปุ่มแผนที่ (ซ้ายกลางจอ) และแถบเลือด
	rocketPanel.Position = UDim2.fromScale(0.2, 0.245)
	rocketPanel.Size = UDim2.fromScale(0.36, 0.1)
	rocketPanel.BackgroundColor3 = Color3.fromRGB(25, 28, 33)
	rocketPanel.BackgroundTransparency = 0.4
	rocketPanel.BorderSizePixel = 0
	rocketPanel.Visible = false
	rocketPanel.Parent = hud.gui
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0.2, 0)
	panelCorner.Parent = rocketPanel
	local tiedLabel = Hud.makeLabel(rocketPanel, "Tied", "", UDim2.fromScale(0.03, 0.04), UDim2.fromScale(0.94, 0.44))
	local itemsLabel = Hud.makeLabel(rocketPanel, "Items", "", UDim2.fromScale(0.03, 0.52), UDim2.fromScale(0.94, 0.44))
	itemsLabel.RichText = true

	local MARK_ON = '<font color="#78e678">มี</font>'
	local MARK_OFF = '<font color="#ff6e64">ไม่มี</font>'
	local lastPanelKey = ""
	local function refreshRocketPanel()
		local info = rocketInfo
		local show = active and phaseName == "Rocket" and info ~= nil
		rocketPanel.Visible = show
		if not show or info == nil then
			lastPanelKey = ""
			return
		end
		local tiedCount = if type(info.tiedCount) == "number" then info.tiedCount else 0
		local total = if type(info.total) == "number" then info.total else 0
		local names: { string } = {}
		if type(info.tied) == "table" then
			for _, entry in info.tied do
				if type(entry) == "table" and type(entry.name) == "string" and #names < 4 then
					table.insert(names, entry.name)
				end
			end
		end
		local moneyOn = info.moneyBag == true
		local snackOn = info.snackPack == true
		local key = tiedCount
			.. "/"
			.. total
			.. "|"
			.. table.concat(names, ",")
			.. "|"
			.. tostring(moneyOn)
			.. tostring(snackOn)
		if key == lastPanelKey then
			return
		end
		lastPanelKey = key
		local tiedText = "มัดแล้ว " .. tiedCount .. "/" .. total
		if #names > 0 then
			tiedText ..= " · " .. table.concat(names, ", ")
		end
		tiedLabel.Text = tiedText
		itemsLabel.Text = "ถุงเงิน: "
			.. (if moneyOn then MARK_ON else MARK_OFF)
			.. "   ขนม: "
			.. (if snackOn then MARK_ON else MARK_OFF)
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
		local locked = actionsLocked()
		local showEat = active and alive and snackCount > 0 and not locked
		if snackCount ~= lastSnackCount then
			lastSnackCount = snackCount
			lastSnackText = "กินขนม (" .. snackCount .. ")"
		end
		hud.setEat(showEat, lastSnackText)
		hud.setDrop(active and kind ~= "" and ownStateName() ~= "Dead" and not locked)
	end)

	return {
		onSnapshot = function(snapshot: { [string]: any })
			local phase = snapshot.phase
			phaseName = if type(phase) == "string" then phase else "Lobby"
			active = (phaseName == "InMission" or phaseName == "Rocket") and snapshot.inLobby ~= true
			offered = snapshot.offered == true
			rocketInfo = if type(snapshot.rocket) == "table" then snapshot.rocket else nil
			refreshRocketPanel()
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
		isTied = isTiedNow,
		activate = activate,
	}
end

return MissionHud
