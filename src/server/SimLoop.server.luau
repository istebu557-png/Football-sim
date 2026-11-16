--[[
	SimLoop — sunucu tarafı simülasyon döngüsü (Adım 1: iskelet).

	Bu script, motorun Roblox içindeki giriş noktasıdır. Önemli tasarım kararı:

	  TOP ROBLOX FİZİĞİ İLE HAREKET ETMEZ.
	  Parça Anchored'dır ve konumu her karede simülasyonun çıktısından yazılır.

	Neden? Çünkü Roblox fiziği:
	  * float32 çalışır (biriken yuvarlama hatası),
	  * sunucu/istemci arasında birebir aynı sonucu üretmez (prediction imkânsız),
	  * hava direnci, Magnus/falso, drag crisis gibi modelleri içermez,
	  * sekme katsayısı ve temas davranışı ayarlanamaz.

	Adım 2'de bu döngü: saha, kale, kamera ve istemci interpolasyonu ile genişleyecek.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Vec3 = require(Shared.Core.Vec3)
local Sim = require(Shared.Sim)

local sim = Sim.new({ seed = 2026 })

-- Metre -> stud
local S = Config.STUDS_PER_METER

local function ensureBallPart()
	local part = Workspace:FindFirstChild("MatchBall")
	if part then
		return part
	end
	part = Instance.new("Part")
	part.Name = "MatchBall"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1, 1, 1) * (Config.BALL.radius * 2 * S)
	part.Anchored = true -- fizik motoru değil, simülasyon sürer
	part.CanCollide = false
	part.CanTouch = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(245, 248, 250)
	part.Parent = Workspace
	return part
end

local ballPart = ensureBallPart()

RunService.Heartbeat:Connect(function(frameDt)
	sim:update(frameDt)

	local p = sim.ball.pos
	ballPart.CFrame = CFrame.new(p.x * S, p.y * S, p.z * S)

	if sim.lastGoal then
		warn("GOL! " .. sim.lastGoal.side .. " takimi, t=" .. string.format("%.2f", sim.time) .. " s")
		sim.lastGoal = nil
		-- Adım 5'te burada santra yeniden başlatılacak; şimdilik topu merkeze al.
		sim.ball:setState(Vec3.new(0, Config.BALL.radius, 0), Vec3.new(0, 0, 0), Vec3.new(0, 0, 0))
	end
end)
