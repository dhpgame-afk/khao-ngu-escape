--!strict
-- Fx: เอฟเฟกต์ภาพฝั่ง client (เส้นกระสุน BB เล็ก ๆ) — ผลจริงมาจากเซิร์ฟเวอร์ ไม่มีเสียง ไม่มีเลือด

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Fx = {}

local MAX_TRACER_LENGTH = 400

function Fx.tracer(origin: Vector3, target: Vector3)
	local offset = target - origin
	local length = math.min(offset.Magnitude, MAX_TRACER_LENGTH)
	if length < 0.5 then
		return
	end
	local part = Instance.new("Part")
	part.Name = "Tracer"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 230, 120)
	part.Size = Vector3.new(0.12, 0.12, length)
	part.CFrame = CFrame.lookAt(origin, target) * CFrame.new(0, 0, -length / 2)
	part.Parent = Workspace
	Debris:AddItem(part, Config.Combat.TracerSeconds)
end

return Fx
