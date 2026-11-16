--[[
	SimLoop — sunucu otoritesi (Adım 3: yarım saha, 1 kaleci, 1 şutçu).

	Akış (her Heartbeat):
	  1) Kaleci AI'sı bir adım atar (topun geleceğini tahmin eder, dalar).
	  2) Oyuncuların gerçek karakterlerinden top-oyuncu ilişkisi işlenir
	     (dokunuş, kapatma, gövde çarpması) — BallControl.
	  3) Gövdeler (oyuncu + kaleci) simülasyona verilir; top 240 Hz'de ilerler,
	     gövdelere ve direklere çarpar, kaleye girerse FILE takılır (Net).
	  4) Görseller güncellenir: top, kaleci modeli, esneyen arka ağ.
	  5) Gol olursa skor/duyuru, ardından santra.

	Top her zaman sunucuda simüle edilir; istemci yalnızca istek gönderir.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Vec3 = require(Shared.Core.Vec3)
local Rng = require(Shared.Core.Rng)
local Ballistics = require(Shared.Core.Ballistics)
local Sim = require(Shared.Sim)
local SceneBuilder = require(Shared.World.SceneBuilder)
local Net = require(Shared.Physics.Net)
local BallControl = require(Shared.Player.BallControl)
local Keeper = require(Shared.Player.Keeper)

local S = Config.STUDS_PER_METER
local R = Config.BALL.radius
local P = Config.PITCH

-- ---------------------------------------------------------------- 1) Sahne
local scene = SceneBuilder.build({ half = true, goalSide = 1 })
local ballPart = scene.ball
local keeperModel = scene.keeper
local backNet = scene.backNet
local backNetX = scene.backX -- metre

-- ------------------------------------------------------------ 2) Simülasyon
local sim = Sim.new({ seed = 2026 })
local goalNet = Net.new(Config, scene.goalSide)
sim.nets[1] = goalNet

local keeper = Keeper.new(Config, scene.goalSide)
local rng = Rng.new(4242)

local controls = {}
local function getControl(player)
	local c = controls[player]
	if not c then
		c = BallControl.new(Config)
		controls[player] = c
	end
	return c
end

local stats = { goals = 0, saves = 0, kicks = 0 }

-- -------------------------------------------------------------- 3) Remotes
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local function ensureRemote(name)
	local ev = remotes:FindFirstChild(name)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = remotes
	end
	return ev
end

local kickRemote = ensureRemote("Kick")
local resetRemote = ensureRemote("ResetBall")
local stateRemote = ensureRemote("MatchState") -- sunucu -> istemci: skor/olay

-- ------------------------------------------------------- 4) Oyuncu durumu
local function playerState(player)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	local look = hrp.CFrame.LookVector
	local facing = math.atan2(look.Z, look.X) -- +x'ten +z'ye (Vec3.yaw ile aynı)
	return BallControl.playerState(
		Vector3.new(hrp.Position.X, 0, hrp.Position.Z),
		hrp.AssemblyLinearVelocity,
		facing,
		S
	)
end

local function resetBall()
	local start = scene.ballStart
	sim.ball:setState(
		Vec3.new(start.X / S, start.Y / S, start.Z / S),
		Vec3.new(0, 0, 0),
		Vec3.new(0, 0, 0)
	)
	goalNet:resetSag()
end

resetBall()

-- --------------------------------------------------------------- 5) Şut
local lastKickAt = {}

kickRemote.OnServerEvent:Connect(function(player, charge, aimZ, aimY)
	local now = os.clock()
	if lastKickAt[player] and now - lastKickAt[player] < 0.35 then
		return
	end

	local state = playerState(player)
	if not state then
		return
	end

	local control = getControl(player)
	if not control:canKick(sim.ball, state) then
		return
	end

	lastKickAt[player] = now

	local c = math.max(0, math.min(1, tonumber(charge) or 0.5))
	local targetZ = math.max(-3.3, math.min(3.3, tonumber(aimZ) or 0))
	local targetY = math.max(0.2, math.min(2.3, tonumber(aimY) or 1.0))

	-- Nişan hatası: yanal sapma (deterministik RNG)
	local errRad = rng:normal(0, math.rad(Config.BALL_CONTROL.aimErrorDeg))
	local dx = P.halfLength - sim.ball.pos.x
	local dz = targetZ - sim.ball.pos.z
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist < 0.5 then
		return
	end
	local lateral = math.tan(errRad) * dist
	local aim = Vec3.new(P.halfLength, targetY, targetZ + lateral)

	local speed = control:speedForCharge(c)
	local velocity = Ballistics.solveLaunch(sim.ball.pos, aim, speed, Config.GRAVITY)
	if not velocity then
		return
	end

	-- Topspin: güç arttıkça artar (top fileye girerken "dalan" bir şut)
	local backspin = (c < 0.2) and 12 or 0 -- çok yavaş vuruşta hafif aşırtma
	local spin = Vec3.new(0, rng:symmetric(10), -math.min(70, speed * 1.6) + backspin)

	control:kick(sim.ball, state, velocity, spin, sim.time)
	stats.kicks = stats.kicks + 1
end)

resetRemote.OnServerEvent:Connect(function()
	resetBall()
end)

-- ------------------------------------------------------- 6) Ana döngü
local resetTimer = 0
local idleTime = 0
local lastKeeperHits = 0

local function broadcastState(event, extra)
	if stateRemote then
		stateRemote:FireAllClients({
			goals = stats.goals,
			saves = stats.saves,
			kicks = stats.kicks,
			sag = goalNet.sag,
			event = event,
			extra = extra,
		})
	end
end

RunService.Heartbeat:Connect(function(frameDt)
	if resetTimer > 0 then
		resetTimer = resetTimer - frameDt
		if resetTimer <= 0 then
			resetBall()
		end
	end

	-- 1) Kaleci
	local keeperBody = keeper:step(sim.ball, frameDt)

	-- 2) Oyuncular: dokunuş / kapatma / gövde
	for _, player in ipairs(Players:GetPlayers()) do
		local state = playerState(player)
		if state then
			local event = getControl(player):update(sim.ball, state, sim.time)
			if event == "trap" then
				-- ilk dokunuş: top yavaşladı
			elseif event == "touch" then
				-- top sürme dokunuşu
			end
		end
	end

	-- 3) Gövdeleri simülasyona ver (240 Hz çarpışma için)
	local bodies = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local state = playerState(player)
		if state then
			bodies[#bodies + 1] = {
				pos = state.pos,
				vel = state.vel,
				radius = Config.BALL_CONTROL.bodyRadius,
				height = Config.BALL_CONTROL.bodyHeight,
				restitution = 0.35,
				friction = 0.25,
			}
		end
	end
	bodies[#bodies + 1] = keeperBody
	sim.bodies = bodies

	-- 4) Simülasyon
	sim:update(frameDt)

	-- 5) Görseller
	local bp = sim.ball.pos
	ballPart.CFrame = CFrame.new(bp.x * S, bp.y * S, bp.z * S)

	SceneBuilder.updateKeeperModel(keeperModel, keeper, S)
	backNet.CFrame = CFrame.new((backNetX + goalNet.sag) * S, (P.goalHeight / 2) * S, 0)

	-- Kurtarış sayacı
	if (keeperBody.hits or 0) > lastKeeperHits then
		stats.saves = stats.saves + (keeperBody.hits - lastKeeperHits)
		broadcastState("save")
	end
	lastKeeperHits = keeperBody.hits or 0

	-- 6) Gol
	if sim.lastGoal then
		local goal = sim.lastGoal
		sim.lastGoal = nil
		stats.goals = stats.goals + 1
		resetTimer = 2.4
		idleTime = 0
		broadcastState("goal", { side = goal.side, speed = sim.ball:speed() })
		print(string.format(
			"[MAC] GOL | toplam %d gol, %d kurtaris, %d sut | ag esnemesi %.2f m",
			stats.goals, stats.saves, stats.kicks, goalNet.sag
		))
		return
	end

	-- Top boşta kalırsa demo şutu (sahne canlı kalsın)
	if sim.ball:speed() < 0.2 and resetTimer <= 0 then
		idleTime = idleTime + frameDt
		if idleTime > 12 then
			idleTime = 0
			local from = sim.ball.pos
			local target = Vec3.new(P.halfLength, rng:range(0.5, 2.0), rng:symmetric(2.8))
			local velocity = Ballistics.solveLaunch(from, target, rng:range(18, 26), Config.GRAVITY)
			if velocity then
				sim.ball:setState(from, velocity, Vec3.new(0, rng:symmetric(30), 0))
			end
		end
	else
		idleTime = 0
	end
end)

Players.PlayerRemoving:Connect(function(player)
	controls[player] = nil
	lastKickAt[player] = nil
end)

print(string.format(
	"[FootballSim] Hazir | yarim saha | 1 kaleci | top fizigi %d Hz | %d direk engeli",
	Config.SIM_HZ,
	#sim.obstacles
))
