--!strict
-- ตัวแทนชั่วคราว (ยังไม่มี UI): พิมพ์เงิน/ขนมที่เซิร์ฟเวอร์ส่งมา เพื่อเช็คว่าข้อมูลถูกต้อง
-- ข้อมูลส่งผ่าน Remote ถึงเจ้าของคนเดียว (ไม่ใช้ Attribute เพราะคนอื่นจะเห็นด้วย)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local dataChanged = remotes:WaitForChild("DataChanged") :: RemoteEvent
local getMyData = remotes:WaitForChild("GetMyData") :: RemoteFunction

local function show(payload: any)
	if type(payload) ~= "table" then
		return
	end
	print("[Client] Money =", payload.money, "Snacks =", payload.snacks, "Guns =", table.concat(payload.ownedGuns or {}, ","))
	if type(payload.message) == "string" then
		warn("[Client]", payload.message)
	end
end

dataChanged.OnClientEvent:Connect(show)
show(getMyData:InvokeServer())
