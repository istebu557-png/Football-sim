--[[
	SimLoop — sunucu otoritesi (yarım saha, 1 kaleci, 1 şutçu).

	Akış (her Heartbeat):
	  1) Kaleci AI'sı bir adım atar: topun kale düzlemine varacağı noktayı ve
	     yüksekliğini tahmin eder, dalış hedefini kilitler.
	  2) Şutçu NPC'si topa yürür, ayak mesafesine gelince topun gerçek konumuna
	     göre adaptif şut pozisyonu seçer.
	  3) Oyuncuların top-oyuncu ilişkisi işlenir (dokunuş, kapatma, gövde).
	  4) Gövdeler simülasyona verilir; top 240 Hz'de ilerler, direklere/gövdelere
	     çarpar, kaleye girerse FILE takılır (Net).
	  5) ANİMASYON (tamamen kodla, asset yok): kaleci dalışı, şutçu şutu ve
	     oyuncunun R15 eklemleri sunucuda FK ile pozlanır.
	  6) Görseller güncellenir; gol olursa skor + santra.

	Animasyon nedenseldir: şutun topu bıraktığı an, animasyonun TEMAS anıdır
	(0.24 s). Oyuncu şut tuşuna bastığında top hemen ayrılmaz; savurma tamamlanır.
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
local Striker = require(Shared.Player.Striker)
local KeeperAnim = require(Shared.Anim.KeeperAnim)
local KickAnim = require(Shared.Anim.KickAnim)
local HumanoidPose = require(Shared.Anim.HumanoidPose)

local S = Config.STUDS_PER_METER
local R = Config.BALL.radius
local P = Config.PITCH
local ANIM = Config.ANIM or {}

-- ---------------------------------------------------------------- 1) Sahne
local scene = SceneBuilder.build({ half = true, goalSide = 1 })
local ballPart = scene.ball
local keeperModel = scene.keeper
local strikerModel = scene.striker
local backNet = scene.backNet
local backNetX = scene.backX -- metre

-- ------------------------------------------------------------ 2) Simülasyon
local sim = Sim.new({ seed = 2026 })
local goalNet = Net.new(Config, scene.goalSide)
sim.nets[1] = goalNet

local keeper = Keeper.new(Config, scene.goalSide)
local striker = Striker.new(Config, { side = scene.goalSide, pos = scene.strikerStart })
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

local stats = { goals = 0, saves = 0, kicks = 0, shots = 0 }

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
	-- Şutçu da başlangıç noktasına döner
	striker.pos = scene.strikerStart
	striker.vel = Vec3.new(0, 0, 0)
	striker.kick = nil
	striker.kickT = 0
	striker.cooldown = 0.6
	striker.walkPhase = 0
end

resetBall()

-- --------------------------------------------------------------- 5) Şut
-- Oyuncunun şutu: tuşa basıldığında pozisyon seçilir, top TEMAS anında ayrılır.
local lastKickAt = {}
local pending = {} -- player -> { t, kick, speed, aimY, aimZ, spin, fired }

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
	if pending[player] then
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

	-- Topun oyuncuya göre konumu -> adaptif şut pozisyonu (hangi ayak, vole mi?)
	local toBall = Vec3.withY(Vec3.sub(sim.ball.pos, state.pos), 0)
	local forward = Vec3.new(math.cos(state.facing), 0, math.sin(state.facing))
	local right = Vec3.cross(forward, Vec3.new(0, 1, 0))
	local kick = KickAnim.new({
		ballHeight = sim.ball.pos.y,
		ballLateral = Vec3.dot(toBall, right),
		ballForward = Vec3.dot(toBall, forward),
		charge = c,
	})

	local speed = control:speedForCharge(c)
	-- Falso: alçak şut topspin, yüksek köşe backspin (Ballistics.shotSpin)
	local spin = Ballistics.shotSpin(speed, targetY, targetZ)

	pending[player] = {
		t = 0,
		kick = kick,
		speed = speed,
		aimY = targetY,
		aimZ = targetZ + lateral,
		spin = Vec3.add(spin, Vec3.new(0, rng:symmetric(10), 0)),
		fired = false,
	}
end)

resetRemote.OnServerEvent:Connect(function()
	resetBall()
end)

-- ------------------------------------------------------- 6) Ana döngü
local resetTimer = 0
local idleTime = 0
local lastKeeperHits = 0

local keeperAnim = nil
local keeperAnimT = 0
local keeperDiveRef = nil

local READY_POSE = KeeperAnim.new({ dz = 0, height = 0.5 }):sample(0.15).pose

-- Kaleci pozu: dalış hedefi değiştiğinde yeni animasyon başlar
local function keeperPose(dt)
	if not ANIM.keeperPoseEnabled then
		return nil
	end
	local target = keeper.diveTarget
	if target and target ~= keeperDiveRef then
		keeperDiveRef = target
		keeperAnim = KeeperAnim.new({
			dz = target.dz,
			height = target.height,
			speed = target.speed,
		})
		keeperAnimT = 0
	end
	if keeperAnim then
		keeperAnimT = keeperAnimT + dt
		if keeperAnimT < keeperAnim:duration() then
			return keeperAnim:sample(keeperAnimT).pose
		end
		keeperAnim = nil
		keeperDiveRef = keeper.diveTarget
	end
	return READY_POSE
end

local function broadcastState(event, extra)
	if stateRemote then
		stateRemote:FireAllClients({
			goals = stats.goals,
			saves = stats.saves,
			kicks = stats.kicks,
			shots = stats.shots,
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

	-- 2) Şutçu NPC: yürü -> şut pozisyonu -> TEMAS anında top ayrılır
	if ANIM.strikerEnabled and strikerModel then
		local shot = striker:step(frameDt, sim.ball)
		if shot and shot.type == "shoot" then
			local velocity = Ballistics.solveLaunch(sim.ball.pos, shot.target, shot.speed, Config.GRAVITY)
			if velocity then
				sim.ball.vel = velocity
				sim.ball.spin = Ballistics.shotSpin(shot.speed, shot.target.y, shot.target.z)
				sim.ball.mode = "air"
				stats.shots = stats.shots + 1
			end
		end
		SceneBuilder.updateStrikerModel(strikerModel, striker:pose(), striker.pos, striker.facing, S)
	end

	-- 3) Oyuncuların şutları: savurma tamamlanınca top ayrılır
	for player, shot in pairs(pending) do
		shot.t = shot.t + frameDt
		if not shot.fired and shot.t >= KickAnim.CONTACT_TIME then
			shot.fired = true
			local velocity = Ballistics.solveLaunch(
				sim.ball.pos,
				Vec3.new(P.halfLength, shot.aimY, shot.aimZ),
				shot.speed,
				Config.GRAVITY
			)
			if velocity then
				getControl(player):kick(sim.ball, nil, velocity, shot.spin, sim.time)
				stats.kicks = stats.kicks + 1
			end
		end
		-- Sunucu tarafı R15 pozu (deneysel; Config.ANIM.poseHumanoid ile kapanır)
		local character = player.Character
		if ANIM.poseHumanoid and character and HumanoidPose.supported(character) then
			HumanoidPose.apply(character, shot.kick:sample(shot.t).pose)
		end
		if shot.t >= shot.kick:duration() then
			if character and ANIM.poseHumanoid then
				HumanoidPose.clear(character)
			end
			pending[player] = nil
		end
	end

	-- 4) Oyuncular: dokunuş / kapatma / gövde
	for _, player in ipairs(Players:GetPlayers()) do
		local state = playerState(player)
		if state then
			getControl(player):update(sim.ball, state, sim.time)
		end
	end

	-- 5) Gövdeleri simülasyona ver (240 Hz çarpışma için)
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

	-- 6) Simülasyon (240 Hz sabit adım)
	sim:update(frameDt)

	-- 7) Görseller + animasyon
	local bp = sim.ball.pos
	ballPart.CFrame = CFrame.new(bp.x * S, bp.y * S, bp.z * S)

	SceneBuilder.updateKeeperModel(keeperModel, keeperPose(frameDt), keeper.pos, S)
	backNet.CFrame = CFrame.new((backNetX + goalNet.sag) * S, (P.goalHeight / 2) * S, 0)

	-- Kurtarış sayacı
	if (keeperBody.hits or 0) > lastKeeperHits then
		stats.saves = stats.saves + (keeperBody.hits - lastKeeperHits)
		broadcastState("save")
	end
	lastKeeperHits = keeperBody.hits or 0

	-- 8) Gol
	if sim.lastGoal then
		local goal = sim.lastGoal
		sim.lastGoal = nil
		stats.goals = stats.goals + 1
		resetTimer = 2.4
		idleTime = 0
		broadcastState("goal", { side = goal.side, speed = sim.ball:speed() })
		print(string.format(
			"[MAC] GOL | toplam %d gol, %d kurtaris, %d sut | ag esnemesi %.2f m",
			stats.goals, stats.saves, stats.kicks + stats.shots, goalNet.sag
		))
		return
	end

	-- Şutçu kapalıysa: top boşta kalırsa demo şutu (sahne canlı kalsın)
	if not ANIM.strikerEnabled and sim.ball:speed() < 0.2 and resetTimer <= 0 then
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
	pending[player] = nil
end)

print(string.format(
	"[FootballSim] Hazir | yarim saha | 1 kaleci + 1 sutcu (prosedurel iskelet) | top fizigi %d Hz | %d direk engeli",
	Config.SIM_HZ,
	#sim.obstacles
))
