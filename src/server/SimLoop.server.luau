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
local Validate = require(Shared.Core.Validate)
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
local PlayerPose = require(Shared.Anim.PlayerPose)

local S = Config.STUDS_PER_METER
local P = Config.PITCH
local ANIM = Config.ANIM or {}

-- Lua 5.3: math.atan(y, x) | Luau: math.atan2(y, x). Ikisi de desteklensin
-- (Vec3 ve SceneBuilder ile ayni desen; test kosucusu Lua 5.3 kullanir).
local atan2 = math.atan2 or math.atan

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
	local facing = atan2(look.Z, look.X) -- +x'ten +z'ye (Vec3.yaw ile aynı)
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
-- Oyuncu karakterlerinin prosedürel animasyon saati (yürüyüş fazı + nefes).
-- Şut beklemede OLMASA da karakter pozlanır: eskiden yalnızca şut sırasında
-- poz yazıldığı için oyuncu "animasyonlar çalışmıyor" diyordu.
local playerAnimClock = 0
-- Yürüyüş fazı ve genliği BİRİKTİRİLİR: faz eskiden (mutlak zaman * anlık hız)
-- ile hesaplanıyordu; hız değişince eklemler bir karede sıçrıyordu. Oyuncu
-- başına bir state; weak key tablo ayrılan oyuncuları otomatik bırakır.
local playerPoseState = setmetatable({}, { __mode = "k" })
local pending = {} -- player -> { t, kick, speed, aimY, aimZ, spin, fired }
-- ŞUT TAMPONU: menzil dışındaki istek çöpe gitmez, kısa bir pencere bekletilir.
-- player -> { at = sim.time, charge, aimZ, aimY, shotType, foot }
local buffered = {}

-- broadcastState aşağıda tanımlı; Lua'da local'ler bildirim noktasından sonra
-- görünür olduğu için burada ileri bildirim gerekiyor.
local broadcastState

--[[ Şut geri bildirimi: istemcide HUD satırında kısa süre gösterilir. ]]
local function shotHint(kind, text)
	if broadcastState then
		broadcastState(kind, nil, text)
	end
end

--[[ İstemciden gelen HER değer güvenilmezdir (exploiter arbitrary tablo/string
	gönderebilir). KickAnim, `SHOT[shotType]` ve `"hip" .. foot` kullandığı için
	doğrulanmamış girdi sunucu handler'ını patlatır (ör. shotType = "labels" ->
	sp.power = nil -> aritmetik hatası; foot = {} -> concatenate hatası).
	Bu yüzden beyaz liste: listede yoksa varsayılana düş. ]]
-- Politika: BEYAZ LİSTE + VARSAYILANA DÜŞ. Kurallar src/shared/Core/Validate.luau
-- içinde (birim testli); burada yalnızca bu dosyanın kullandığı kısa adlar bağlanır.
-- Çağrı yerleri (isFiniteVec3/sanitize*) bilerek aynı isimde kalır:
-- tools/verify.js "her launch bölgesi isFiniteVec3 ile korunmuş mu?" diye statik
-- denetim yapar.
local VALID_SHOT_TYPES = Validate.shotTypeSet(Config.SHOT)

local function sanitizeShotType(value)
	return Validate.shotType(value, VALID_SHOT_TYPES)
end

local function sanitizeFoot(value)
	return Validate.foot(value)
end

-- NaN/inf istemciden gelebilir: math.min(1, NaN) = NaN olduğu için clamp yetmez,
-- sonlu sayı denetimi şart. Bu yüzden güç/nişan Validate.clamp'ten geçer (önce
-- sonluluk, sonra aralık); topa yazılacak hız ise aşağıdaki isFiniteVec3'ten.
-- Topa YAZILACAK hız için son savunma hattı: Ballistics.solveLaunch ulaşılamayan
-- hedefte NaN üretebilir ve NaN hız simülasyonun geri kalanını kalıcı bozar.
local function isFiniteVec3(v)
	return Validate.vec3(v)
end

local KICK_COOLDOWN = 0.35 -- iki şut isteği arasındaki en az süre (s)

--[[ Şut isteğini uygular (hem doğrudan istek hem tampondaki istek aynı yoldan
     geçer; böylece iki yol farklı kural uygulayamaz).
     Dönüş: true -> vuruş başladı | false, neden, tamponlanabilir mi ]]
local function startShot(player, charge, aimZ, aimY, shotType, foot)
	local BC = Config.BALL_CONTROL
	local state = playerState(player)
	if not state then
		return false, "karakter hazır değil (HumanoidRootPart yok)", false
	end

	local control = getControl(player)
	if not control:canKick(sim.ball, state, sim.time) then
		if sim.ball.pos.y > BC.kickHeight then
			return false, string.format(
				"top %.2f m havada — vuruş yüksekliği %.1f m", sim.ball.pos.y, BC.kickHeight), false
		end
		local gap = control:shotGap(sim.ball, state)
		return false, string.format(
			"top %.1f m önde — şut menzili %.1f m", gap, BC.possessionReach), gap <= BC.shotBufferReach
	end
	if pending[player] then
		return false, "şut zaten sürüyor", false
	end

	local c = Validate.clamp(charge, 0, 1, 0.5)
	local targetZ = Validate.clamp(aimZ, -3.3, 3.3, 0)
	local targetY = Validate.clamp(aimY, 0.2, 2.3, 1.0)

	-- Nişan hatası: yanal sapma (deterministik RNG)
	local errRad = rng:normal(0, math.rad(BC.aimErrorDeg))
	local dx = P.halfLength - sim.ball.pos.x
	local dz = targetZ - sim.ball.pos.z
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist < 0.5 then
		return false, "kale ağzındasın: nişan düzlemi kurulamıyor", false
	end
	local lateral = math.tan(errRad) * dist

	-- Topun oyuncuya göre konumu -> adaptif şut pozisyonu (vuruş türü + ayak)
	local toBall = Vec3.withY(Vec3.sub(sim.ball.pos, state.pos), 0)
	local forward = Vec3.new(math.cos(state.facing), 0, math.sin(state.facing))
	local right = Vec3.cross(forward, Vec3.new(0, 1, 0))
	local kick = KickAnim.new({
		ballHeight = sim.ball.pos.y,
		ballLateral = Vec3.dot(toBall, right),
		ballForward = Vec3.dot(toBall, forward),
		charge = c,
		shotType = sanitizeShotType(shotType),
		foot = sanitizeFoot(foot), -- nil -> otomatik (topun yanına göre)
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
	return true
end

kickRemote.OnServerEvent:Connect(function(player, charge, aimZ, aimY, shotType, foot)
	local now = os.clock()
	if lastKickAt[player] and now - lastKickAt[player] < KICK_COOLDOWN then
		shotHint("shotRejected", string.format("şut çıkmadı: çok hızlı, iki şut arası en az %.2f s", KICK_COOLDOWN))
		return
	end

	local ok, reason, bufferable = startShot(player, charge, aimZ, aimY, shotType, foot)
	if ok then
		lastKickAt[player] = now
		return
	end

	-- SESSİZ RED YOK. Top sürüşten öndeyse istek TAMPONA alınır: oyuncu topa
	-- yetişince şut kendiliğinden çıkar (bkz. adım 3a). Tampon menzili de
	-- aşıldıysa oyuncuya nedeni yazılır.
	if bufferable and not buffered[player] then
		buffered[player] = {
			at = sim.time,
			charge = charge,
			aimZ = aimZ,
			aimY = aimY,
			shotType = shotType,
			foot = foot,
		}
		lastKickAt[player] = now
		shotHint("shotBuffered", "şut bekliyor → topa yetiş, kendiliğinden çıkacak (" .. reason .. ")")
	else
		shotHint("shotRejected", "şut çıkmadı: " .. reason)
	end
end)

-- Sıfırlama da hız sınırlı: herhangi bir istemci bunu spamleyip maçı
-- kilitleyemesin (sunucu otoritesi).
local lastResetAt = 0
resetRemote.OnServerEvent:Connect(function()
	local now = os.clock()
	if now - lastResetAt < 0.5 then
		return
	end
	lastResetAt = now
	resetBall()
end)

-- ------------------------------------------------------- 6) Ana döngü
local resetTimer = 0
local lastKeeperHits = 0

local keeperAnim = nil
local keeperAnimT = 0
local keeperDiveRef = nil

local keeperClock = 0 -- kaleci idle animasyonunun saati (nefes/salinim)

-- Kaleci pozu: yeni dalış hedefi geldiğinde animasyon başlar; süresi bittiğinde canlı idle pozuna (nefes + salınım) döner.
local function keeperPose(dt)
	if not ANIM.keeperPoseEnabled then
		return nil
	end
	keeperClock = keeperClock + dt
	local target = keeper.diveTarget
	if target and (not keeperAnim or keeperAnimT >= keeperAnim:duration()) then
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
	end
	-- Dalış yoksa heykel değil: nefes + ağırlık salınımı (sahne canlı kalır)
	return KeeperAnim.idle(keeperClock)
end

-- hint: şut isteğinin NEDEN çıkmadığı (ya da tampondan çıktığı) oyuncuya
-- yazıyla bildirilir. Sessiz red, "şut çekemiyorum" şikayetinin köküydü.
function broadcastState(event, extra, hint)
	if stateRemote then
		stateRemote:FireAllClients({
			goals = stats.goals,
			saves = stats.saves,
			kicks = stats.kicks,
			shots = stats.shots,
			sag = goalNet.sag,
			event = event,
			extra = extra,
			hint = hint,
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
		local shot = striker:step(frameDt, sim.ball, keeper)
		if shot and shot.type == "shoot" then
			local velocity = Ballistics.solveLaunch(sim.ball.pos, shot.target, shot.speed, Config.GRAVITY)
			if isFiniteVec3(velocity) then
				sim.ball.vel = velocity
				sim.ball.spin = Ballistics.shotSpin(shot.speed, shot.target.y, shot.target.z)
				sim.ball.mode = "air"
				stats.shots = stats.shots + 1
			end
		end
		SceneBuilder.updateStrikerModel(strikerModel, striker:pose(), striker.pos, striker.facing, S)
	end

	-- 3a) Tampondaki şut istekleri: oyuncu topa yetişince şut kendiliğinden çıkar
	for player, req in pairs(buffered) do
		if sim.time - req.at > Config.BALL_CONTROL.shotBufferTime then
			buffered[player] = nil
			shotHint("shotExpired", string.format(
				"şut kaçtı: %.2f s içinde topa yetişemedin", Config.BALL_CONTROL.shotBufferTime))
		elseif startShot(player, req.charge, req.aimZ, req.aimY, req.shotType, req.foot) then
			buffered[player] = nil
			shotHint("shotFired", "şut çıktı (topa yetişildi)")
		end
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
			if isFiniteVec3(velocity) then
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
			-- clear() çağırmıyoruz: vuruş biter bitmez eklemleri kimliğe
			-- sıfırlamak karakteri bir kare "donmuş" gösteriyordu. Bunun
			-- yerine 3b'deki yürüyüş pozu devralır (geçiş sürekli).
			pending[player] = nil
		end
	end

	-- 3b) Oyuncu karakterleri: yürüyüş/duruş pozu her karede yazılır.
	-- Şut bekleyen oyuncunun pozu yukarıdaki döngüde KickAnim'den gelir;
	-- burada yalnızca şut beklemeyenler pozlanır (KickAnim önceliği korunsun).
	if ANIM.poseHumanoid then
		playerAnimClock = playerAnimClock + frameDt
		for _, player in ipairs(Players:GetPlayers()) do
			if not pending[player] then
				local character = player.Character
				if character and HumanoidPose.supported(character) then
					local state = playerState(player)
					local speed = (state and state.speed) or 0 -- m/s (yatay)
					local walkState = playerPoseState[player]
					if not walkState then
						walkState = PlayerPose.newState()
						playerPoseState[player] = walkState
					end
					HumanoidPose.apply(character,
						PlayerPose.step(walkState, frameDt, playerAnimClock, speed))
				end
			end
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
		broadcastState("goal", { side = goal.side, speed = sim.ball:speed() })
		print(string.format(
			"[MAC] GOL | toplam %d gol, %d kurtaris, %d sut | ag esnemesi %.2f m",
			stats.goals, stats.saves, stats.kicks + stats.shots, goalNet.sag
		))
		return
	end

end)

Players.PlayerRemoving:Connect(function(player)
	controls[player] = nil
	lastKickAt[player] = nil
	pending[player] = nil
	buffered[player] = nil
end)

-- Banner gerçegi soylesin: sutu kim atiyor?
print(string.format(
	"[FootballSim] Hazir | yarim saha | 1 kaleci (AI) + %s | top fizigi %d Hz | %d direk engeli",
	Config.ANIM.strikerEnabled and "1 sutcu NPC (demo)" or "sut: oynayan oyuncu",
	Config.SIM_HZ,
	#sim.obstacles
))
