--!strict
-- RateLimit: จำกัดความถี่คำขอจาก client ต่อผู้เล่นต่อชนิดคำขอ (ใช้กับทุก RemoteEvent)

local Players = game:GetService("Players")

local RateLimit = {}

local lastClock: { [Player]: { [string]: number } } = {}

-- คืน true ถ้าผ่าน (ห่างจากครั้งก่อนอย่างน้อย minInterval วินาที) แล้วบันทึกเวลาให้
function RateLimit.allow(player: Player, key: string, minInterval: number): boolean
	local perPlayer = lastClock[player]
	if perPlayer == nil then
		perPlayer = {}
		lastClock[player] = perPlayer
	end
	local now = os.clock()
	local last = perPlayer[key]
	if last ~= nil and now - last < minInterval then
		return false
	end
	perPlayer[key] = now
	return true
end

Players.PlayerRemoving:Connect(function(player: Player)
	lastClock[player] = nil
end)

return RateLimit
