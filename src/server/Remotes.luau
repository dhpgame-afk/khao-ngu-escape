--!strict
-- Remotes: ตัวช่วยหา/สร้าง Remote ใน ReplicatedStorage.Remotes (ใช้ที่ประกาศใน Rojo ถ้ามี ไม่มีก็สร้างตอนรัน)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

function Remotes.getFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
	return folder
end

function Remotes.remoteEvent(name: string): RemoteEvent
	local folder = Remotes.getFolder()
	local existing = folder:FindFirstChild(name)
	if existing ~= nil and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

function Remotes.remoteFunction(name: string): RemoteFunction
	local folder = Remotes.getFolder()
	local existing = folder:FindFirstChild(name)
	if existing ~= nil and existing:IsA("RemoteFunction") then
		return existing
	end
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = folder
	return remote
end

return Remotes
