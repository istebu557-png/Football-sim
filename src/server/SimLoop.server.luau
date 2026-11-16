--[[
	SimLoop — sunucu otoritesi (Adım 2).

	Görevleri:
	  1) Sahne yoksa kur (SceneBuilder).
	  2) Simülasyonu 240 Hz sabit adımla çalıştır (Sim).
	  3) Topun CFrame'ini simülasyondan yaz (Roblox fiziği kullanılmaz).
	  4) Golü duyur, topu merkeze al, demo atışları yap.
	  5) İstemciden gelen şut isteğini (RemoteEvent) doğrula ve uygula.

	Neden sunucu otoritesi? İstemci topu kendi başına hareket ettiremez; aksi halde
	hile (speed hack, teleport) mümkün olur. Adım 7'de istemci tahmini eklenecek;
	şimdilik istemci sadece görüntüyü yumuşatıyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Vec3 = require(Shared.Core.Vec3)
local Rng = require(Shared.Core.Rng)
local Ballistics = require(Shared.Core.Ballistics)
local Sim = require(Shared.Sim)
local SceneBuilder = require(Shared.World.SceneBuilder)

local S = Config.STUDS_PER_METER
local R = Config.BALL.radius

-- 1) Sahne
local scene = SceneBuilder.build()
local ballPart = scene.ball

-- 2) Simülasyon (sabit tohum: aynı maç tekrar oynatılabilir)
local sim = Sim.new({ seed = 2026 })
local shotRng = Rng.new(90210)

-- 3) İstemci -> sunucu: şut isteği
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end
local kickRemote = remotes:FindFirstChild("Kick")
if not kickRemote then
	kickRemote = Instance.new("RemoteEvent")
	kickRemote.Name = "Kick"
	kickRemote.Parent = remotes
end

local function resetBall()
	sim.ball:setState(Vec3.new(0, R, 0), Vec3.new(0, 0, 0), Vec3.new(0, 0, 0))
end

--[[ Demo/şut: rastgele bir noktadan kaleye nişan alır.
	Nişan hatası ve falso gerçek oyuncu dağılımından gelir (Rng deterministik). ]]
local function takeShot()
	local fromX = 52.5 - shotRng:range(16, 30)
	local fromZ = shotRng:symmetric(14)
	local from = Vec3.new(fromX, R, fromZ)

	-- Hedef: kale ağzı içinde, bazen direğe yakın (kaçan şutlar da olsun)
	local targetZ = shotRng:symmetric(3.2)
	local targetY = shotRng:range(0.3, 2.1)
	local to = Vec3.new(52.5, targetY, targetZ)

	local speed = shotRng:range(19, 28)
	local velocity = Ballistics.solveLaunch(from, to, speed, Config.GRAVITY)
	if not velocity then
		return
	end

	-- Falso: rastgele yan spin (bazı şutlar bükülür)
	local spin = Vec3.new(0, shotRng:symmetric(45), 0)
	sim.ball:setState(from, velocity, spin)
end

local lastKickAt = {}
kickRemote.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if lastKickAt[player] and now - lastKickAt[player] < 0.6 then
		return -- istek taşması koruması
	end
	lastKickAt[player] = now
	if sim.ball:speed() > 0.5 then
		return -- top hareketliyken yeni şut yok
	end
	takeShot()
end)

Players.PlayerRemoving:Connect(function(player)
	lastKickAt[player] = nil
end)

-- 4) Ana döngü
local goalCooldown = 0
local idleTime = 0
local DEMO_IDLE = 6.0

RunService.Heartbeat:Connect(function(frameDt)
	sim:update(frameDt)

	local p = sim.ball.pos
	ballPart.CFrame = CFrame.new(p.x * S, p.y * S, p.z * S)

	if sim.lastGoal then
		local goal = sim.lastGoal
		sim.lastGoal = nil
		print(string.format("[MAC] GOL! %s takimi | t=%.2f s | hiz=%.1f m/s",
			goal.side == "home" and "Ev" or "Deplasman", sim.time, sim.ball:speed()))

		-- Ağ topu tuttu: topu olduğu yerde bırak, kısa süre sonra santra
		goalCooldown = 2.5
		idleTime = 0
		return
	end

	if goalCooldown > 0 then
		goalCooldown = goalCooldown - frameDt
		if goalCooldown <= 0 then
			resetBall()
		end
		return
	end

	-- Top durduysa demo atışı yap (sahne boş kalmasın)
	if sim.ball:speed() < 0.25 then
		idleTime = idleTime + frameDt
		if idleTime >= DEMO_IDLE then
			idleTime = 0
			takeShot()
		end
	else
		idleTime = 0
	end
end)

print("[FootballSim] Sunucu hazir. Top fizigi 240 Hz, sahne kuruldu.")
print("[FootballSim] Istatistik: " .. tostring(#sim.obstacles) .. " direk/ust direk engeli, "
	.. tostring(Config.PITCH.length) .. "x" .. tostring(Config.PITCH.width) .. " m saha")
