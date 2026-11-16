--[[
	FootballSim — TEK KURULUM DOSYASI (otomatik üretilir, elle düzenlemeyin).

	KULLANIM
	  1) Roblox Studio'da oyunu aç.
	  2) View > Command Bar (komut çubuğu) aç.
	  3) Bu dosyanın TAMAMINI kopyalayıp komut çubuğuna yapıştır, Enter.
	  4) Sahne kurulur, scriptler yerleşir. Play'e bas: SPACE ile şut çek.

	Yeniden üretmek için: npm run install:build
	Kaynak: src/ (17 modül)
]]

local SOURCES = {
	["client/BallView"] = { class = "LocalScript", source = [=[
--[[
	BallView — istemci (Adım 3): üçüncü şahıs kamera, nişan, güç barı, top görseli.

	  * Sunucu topunu lokal olarak gizler, yumuşatılmış kopyasını çizer
	    (replikasyon 20-30 Hz, top 27 m/s -> aradaki hareket doldurulur).
	  * Kamera karakterin arkasında, kaleye bakacak şekilde konumlanır.
	  * Ekranın ortasındaki ışın kale düzlemini keser -> nişan noktası.
	  * SPACE basılı tut = şut gücü, bırak = şut. Sunucu sadece isteği alır;
	    gücü/nişanı doğrular ve şutu kendi uygular.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Config (varsa gerçek değerler, yoksa makul varsayılanlar)
local Config
do
	local Shared = ReplicatedStorage:WaitForChild("Shared", 20)
	if Shared then
		local ok, mod = pcall(require, Shared:WaitForChild("Config", 10))
		if ok then
			Config = mod
		end
	end
end
local S = Config and Config.STUDS_PER_METER or 3.5714
local R = Config and Config.BALL.radius or 0.11
local PITCH = Config and Config.PITCH
local HALF_LENGTH = PITCH and PITCH.halfLength or 52.5
local GOAL_PLANE = HALF_LENGTH * S
local CHARGE_TIME = (Config and Config.BALL_CONTROL and Config.BALL_CONTROL.chargeTime) or 0.9

-- ---------------------------------------------------------------- karakter
local character, hrp
local function bindCharacter(char)
	character = char
	hrp = char:WaitForChild("HumanoidRootPart", 10)
end
if player.Character then
	bindCharacter(player.Character)
end
player.CharacterAdded:Connect(bindCharacter)

-- -------------------------------------------------------------------- top
local serverBall = Workspace:WaitForChild("MatchBall", 30)
if not serverBall then
	return
end
serverBall.LocalTransparencyModifier = 1

local visual = serverBall:Clone()
visual.Name = "MatchBallVisual"
visual.Anchored = true
visual.CanCollide = false
visual.CanQuery = false
visual.Transparency = 0
visual.LocalTransparencyModifier = 0
visual.Parent = Workspace

local trail = Instance.new("Trail")
trail.Attachment0 = Instance.new("Attachment")
trail.Attachment1 = Instance.new("Attachment")
trail.Attachment0.Parent = visual
trail.Attachment1.Parent = visual
trail.Attachment1.Position = Vector3.new(0.05, 0, 0)
trail.Lifetime = 0.3
trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
trail.Color = ColorSequence.new(Color3.fromRGB(180, 230, 255))
trail.Parent = visual

-- -------------------------------------------------------------- nişan işareti
local marker = Instance.new("Part")
marker.Name = "AimMarker"
marker.Shape = Enum.PartType.Cylinder
marker.Size = Vector3.new(0.12 * S, 0.55 * S, 0.55 * S)
marker.Anchored = true
marker.CanCollide = false
marker.CanQuery = false
marker.Material = Enum.Material.Neon
marker.Color = Color3.fromRGB(90, 255, 160)
marker.Transparency = 0.35
marker.Parent = Workspace

-- -------------------------------------------------------------------- HUD
local gui = Instance.new("ScreenGui")
gui.Name = "FootballHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -26)
hint.Size = UDim2.new(0, 560, 0, 34)
hint.BackgroundColor3 = Color3.fromRGB(10, 16, 20)
hint.BackgroundTransparency = 0.25
hint.BorderSizePixel = 0
hint.TextColor3 = Color3.fromRGB(232, 240, 246)
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 15
hint.Text = "SPACE basılı tut → güç  ·  bırak → şut   |   R → topu sıfırla"
hint.Parent = gui

local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 8)
hintCorner.Parent = hint

-- Güç barı
local barBack = Instance.new("Frame")
barBack.AnchorPoint = Vector2.new(0.5, 1)
barBack.Position = UDim2.new(0.5, 0, 1, -68)
barBack.Size = UDim2.new(0, 320, 0, 14)
barBack.BackgroundColor3 = Color3.fromRGB(24, 32, 40)
barBack.BorderSizePixel = 0
barBack.Visible = false
barBack.Parent = gui

local barBackCorner = Instance.new("UICorner")
barBackCorner.CornerRadius = UDim.new(0, 7)
barBackCorner.Parent = barBack

local barFill = Instance.new("Frame")
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(61, 220, 132)
barFill.BorderSizePixel = 0
barFill.Parent = barBack

local barFillCorner = Instance.new("UICorner")
barFillCorner.CornerRadius = UDim.new(0, 7)
barFillCorner.Parent = barFill

-- Skor / duyuru
local scoreLabel = Instance.new("TextLabel")
scoreLabel.AnchorPoint = Vector2.new(0.5, 0)
scoreLabel.Position = UDim2.new(0.5, 0, 0, 14)
scoreLabel.Size = UDim2.new(0, 420, 0, 28)
scoreLabel.BackgroundTransparency = 1
scoreLabel.TextColor3 = Color3.fromRGB(240, 246, 250)
scoreLabel.Font = Enum.Font.GothamBold
scoreLabel.TextSize = 17
scoreLabel.Text = "GOL 0  ·  KURTARIŞ 0  ·  ŞUT 0"
scoreLabel.Parent = gui

-- ---------------------------------------------------------------- remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes", 25)
local kickRemote = remotes and remotes:WaitForChild("Kick", 10)
local resetRemote = remotes and remotes:WaitForChild("ResetBall", 10)
local stateRemote = remotes and remotes:WaitForChild("MatchState", 10)

if stateRemote then
	stateRemote.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		scoreLabel.Text = string.format(
			"GOL %d  ·  KURTARIŞ %d  ·  ŞUT %d",
			payload.goals or 0,
			payload.saves or 0,
			payload.kicks or 0
		)
		if payload.event == "goal" then
			scoreLabel.TextColor3 = Color3.fromRGB(120, 255, 160)
		elseif payload.event == "save" then
			scoreLabel.TextColor3 = Color3.fromRGB(255, 210, 110)
		end
	end)
end

-- ------------------------------------------------------------ şut / nişan
local charging = false
local charge = 0

local function computeAim()
	local origin = camera.CFrame.Position
	local dir = camera.CFrame.LookVector
	if dir.X <= 0.05 then
		return nil
	end
	local t = (GOAL_PLANE - origin.X) / dir.X
	if t <= 0 then
		return nil
	end
	local hit = origin + dir * t
	local z = math.clamp(hit.Z, -3.3 * S, 3.3 * S)
	local y = math.clamp(hit.Y, 0.25 * S, 2.3 * S)
	return Vector3.new(GOAL_PLANE, y, z)
end

local function fireKick()
	if not kickRemote then
		return
	end
	local aim = computeAim()
	if not aim then
		return
	end
	kickRemote:FireServer(charge, aim.Z / S, aim.Y / S)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Space then
		charging = true
		charge = 0
		barBack.Visible = true
	elseif input.KeyCode == Enum.KeyCode.R and resetRemote then
		resetRemote:FireServer()
	end
end)

UserInputService.InputEnded:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.Space and charging then
		charging = false
		barBack.Visible = false
		fireKick()
		charge = 0
		barFill.Size = UDim2.new(0, 0, 1, 0)
	end
end)

-- ------------------------------------------------------------- kare döngüsü
local renderPos = serverBall.Position
local lastTarget = serverBall.Position
local ballVel = Vector3.zero
local camPos = Vector3.new(-90, 60, 25)
local camLook = Vector3.zero
local camInit = false
local stats = { goals = 0, saves = 0, kicks = 0 }

local function onFrame(dt)
	-- Top: sunucu konumunu yumuşat + hız tahmini
	local target = serverBall.Position
	local k = 1 - math.exp(-16 * dt)
	ballVel = ballVel:Lerp((target - lastTarget) / math.max(dt, 1e-3), 1 - math.exp(-7 * dt))
	lastTarget = target
	local predicted = target + ballVel * 0.03
	renderPos = renderPos:Lerp(predicted, k)
	visual.CFrame = CFrame.new(renderPos)

	-- Kamera: karakterin arkasında, kaleye bakacak şekilde
	if camera then
		local focus = renderPos
		if hrp and hrp.Parent then
			focus = hrp.Position
		end
		local desiredPos = focus + Vector3.new(-30, 20, 9)
		local desiredLook = focus + Vector3.new(34, -3, 0)
		if not camInit then
			camPos = desiredPos
			camLook = desiredLook
			camInit = true
		else
			local ck = 1 - math.exp(-6 * dt)
			camPos = camPos:Lerp(desiredPos, ck)
			camLook = camLook:Lerp(desiredLook, ck)
		end
		camera.CFrame = CFrame.lookAt(camPos, camLook)
		camera.CameraType = Enum.CameraType.Scriptable
	end

	-- Nişan işareti
	local aim = computeAim()
	if aim then
		marker.CFrame = CFrame.new(aim) * CFrame.Angles(0, 0, math.rad(90))
		marker.Transparency = charging and 0.15 or 0.45
		marker.Color = charging and Color3.fromRGB(255, 220, 90) or Color3.fromRGB(90, 255, 160)
	else
		marker.Transparency = 1
	end

	-- Güç barı
	if charging then
		charge = math.min(1, charge + dt / CHARGE_TIME)
		barFill.Size = UDim2.new(charge, 0, 1, 0)
		barFill.BackgroundColor3 = Color3.fromRGB(
			61 + math.floor(194 * charge),
			220 - math.floor(120 * charge),
			132 - math.floor(60 * charge)
		)
	end
end

RunService.RenderStepped:Connect(onFrame)
]=] },
	["server/SimLoop"] = { class = "Script", source = [=[
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
]=] },
	["shared/Config"] = { class = "ModuleScript", source = [=[
--[[
	Config — motorun tüm ayar parametreleri.

	Birim sistemi: SI (metre, saniye, kilogram, radyan).
	Roblox sahnesi için STUD_PER_METER ile çevrim yapılır (1 stud ≈ 0.28 m).
	Böylece fizik "gerçek dünya" sayılarıyla çalışır; Roblox'un 20 stud'luk
	"dev" ölçeğine sıkışmayız.

	Değerler gerçek FIFA ölçüleri ve spor bilimi literatüründen alınmıştır:
	  saha 105 x 68 m, kale 7.32 x 2.44 m, top çapı 22 cm (0.43 kg), hava 1.225 kg/m³
]]

local Config = {}

Config.STUDS_PER_METER = 1 / 0.28 -- 3.5714 stud/metre

-- Simülasyon frekansı. 240 Hz: 25 m/s'lik bir şutta top adım başına ~10 cm ilerler,
-- yani yarıçapından (11 cm) az — tünel geçişi (tunneling) fiziksel olarak imkânsız.
Config.SIM_HZ = 240
Config.FIXED_DT = 1 / Config.SIM_HZ
Config.MAX_FRAME_DT = 0.25 -- tek karede işlenecek maksimum gerçek zaman (spiral ölüm koruması)
Config.MAX_SUBSTEPS = 60

Config.GRAVITY = 9.81

Config.AIR = {
	density = 1.225, -- kg/m³ (deniz seviyesi, 15 °C)
}

local BALL_RADIUS = 0.11 -- FIFA: çevre 68-70 cm -> yarıçap ~0.11 m
Config.BALL = {
	radius = BALL_RADIUS,
	mass = 0.43, -- kg (FIFA: 410-450 g)
	crossSection = math.pi * BALL_RADIUS * BALL_RADIUS, -- m²

	-- Hava direnci: a = -0.5 * rho * A * Cd * |v| * v / m
	-- Cd=0.25 türbülanslı akış rejimi (hızlı şut). Yavaş topta Cd 0.4-0.5'e çıkar;
	-- bu geçiş "drag crisis" olarak adlandırılır ve Knuckleball etkisinin kaynağıdır.
	dragCoefficient = 0.25,
	dragCoefficientSlow = 0.47,
	dragCrisisSpeed = 12, -- m/s: bu hızın altında Cd yavaş değere doğru geçer
	dragCrisisWidth = 6, -- m/s: geçişin yumuşaklığı

	-- Magnus (spin) kuvveti: F = 0.5 * rho * A * Cl * v² * (ω̂ × v̂)
	-- Cl (kaldırma katsayısı) spin oranı S = ω*r/v ile artar, doyuma ulaşır.
	magnusScale = 0.8, -- Cl = min(magnusMax, magnusScale * S)
	magnusMax = 0.32,
	spinDecay = 0.06, -- 1/s: hava sürtünmesiyle spin sönümü (üssel)

	-- Zemin teması (çim, kuru)
	restitution = 0.74, -- dikey sekme katsayısı (zemin testi: 2 m'den ~1.10 m sekme)
	contactFriction = 0.45, -- Coulomb sürtünme katsayısı (teğetsel impuls sınırı)
	rollResistance = 0.06, -- yuvarlanma direnci; ivme = -mu * g ≈ 0.59 m/s²
	rollThreshold = 0.9, -- m/s: bundan yavaş dikey çarpmada sekmez, yuvarlanmaya geçer
	stopSpeed = 0.15, -- m/s: bu hızın altında top durur

	-- Sekme sonrası spinin dikey zıplamaya etkisi (backspin topu alçak tutar).
	spinBounceCoupling = 0.06,

	-- Direk/üst direk çarpışması (metal, çimden daha canlı sekmez)
	postRestitution = 0.62,
	postFriction = 0.35,
}

Config.PITCH = {
	length = 105,
	width = 68,
	halfLength = 52.5,
	halfWidth = 34,
	goalHalfWidth = 3.66, -- 7.32 m kale ağzı
	goalHeight = 2.44,
	goalDepth = 2.0,
	penaltyAreaLength = 16.5,
	penaltyAreaHalfWidth = 20.16,
	goalAreaLength = 5.5,
	goalAreaHalfWidth = 9.16,
	penaltySpot = 11,
	centerCircleRadius = 9.15,
	cornerArcRadius = 1,

	-- Direkler: top bunlara çarpıp döner (Colliders modülü)
	postRadius = 0.06, -- 12 cm direk
	crossbarRadius = 0.06,
}

Config.PLAYER = {
	radius = 0.35,
	maxSpeed = 7.6, -- m/s (27 km/h) — iyi bir amatörün sprint hızı
	sprintMultiplier = 1.0,
	acceleration = 6.5, -- m/s² (0-27 km/h ~1.2 s)
	deceleration = 9.0, -- m/s²
	turnRate = 7.0, -- rad/s (~400°/s) gövde dönüş hızı
	staminaDrainSprint = 0.045, -- 1/s (tam sprintte)
	staminaRegen = 0.07, -- 1/s (dururken)
	staminaMinFactor = 0.72, -- yorgunken hız çarpanı
}

--[[ Oyuncu-top ilişkisi (yakın kontrol / top sürme / şut) ]]
Config.BALL_CONTROL = {
	bodyRadius = 0.42, -- oyuncu gövde yarıçapı (m)
	bodyHeight = 1.80,
	controlRadius = 1.45, -- bu mesafede top "ayakta" sayılır
	kickReach = 1.70, -- şut atılabilen maksimum mesafe
	dribbleReach = 1.60,

	-- Dokunuş (touch) modeli: gerçekte top sürerken saniyede ~3 dokunuş olur
	touchInterval = 0.34,
	touchSpeedFactor = 1.0, -- (artık kullanılmıyor; dokunuş hızı çözülerek bulunuyor)
	touchForward = 0.18, -- dokunuşun ileri bileşeni (m/s) — küçük düzeltme
	maxTouchSpeed = 10.5,
	sprintTouchPenalty = 0.30, -- hızlı koşarken dokunuş aşırıya kaçar (top kaçar)

	-- İlk dokunuş / kapatma (trap)
	trapSpeedThreshold = 6.0,
	trapFactor = 0.30, -- gelen hızlı topun ne kadarı kalır
	trapRadius = 0.95,

	-- Şut
	minKickSpeed = 13,
	maxKickSpeed = 31,
	chargeTime = 0.9, -- tam güç için basılı tutma süresi
	kickHeight = 1.0, -- top bu yüksekliğin altındaysa vurulabilir
	aimErrorDeg = 2.2, -- nişan hatası (derece, standart sapma)
}

--[[ Kaleci AI ]]
Config.KEEPER = {
	height = 1.90,
	radius = 0.44,
	lineOffset = 0.55, -- kale çizgisinden öne mesafe (m)
	maxSpeed = 6.0, -- yan kayma hızı
	diveSpeed = 8.5,
	diveAccel = 22,
	reachZ = 3.15, -- direklerin içinde kalır
	restitution = 0.45,
	reactionTime = 0.12,
}

--[[ File (ağ) fiziği: top ağda yavaşlar, esnetir, geri sektirmez ]]
Config.NET = {
	damping = 7.0, -- ağ içinde üstel hız sönümü (1/s)
	restitution = 0.14, -- ağdan sekme katsayısı (çok ölü)
	sideRestitution = 0.10,
	topRestitution = 0.10,
	friction = 0.55,
	maxSag = 0.38, -- ağın en fazla esneme miktarı (m)
	sagStiffness = 11.0, -- geri toplama yayı
	sagDamping = 3.2,
	sagImpulse = 1.7, -- çarpma hızının esnemeye dönüşümü
}

Config.MATCH = {
	halves = 2,
	halfLengthSeconds = 45 * 60,
	stoppageBase = 60,
	kickoffCountdown = 3,
}

return Config
]=] },
	["shared/Core/Aero"] = { class = "ModuleScript", source = [=[
--[[
	Aero — aerodinamik kuvvetler: hava direnci (drag) ve Magnus etkisi.

	Top havadayken iki kuvvet onu "gerçek" yapar:

	1) DRAG (hava direnci)
	   a = -0.5 * rho * A * Cd * |v| * v / m
	   30 m/s'lik bir şutta ~12 m/s² yavaşlama (1.2 g). Bu yüzden 30 m/s ile
	   vurulan bir şut, 40 m'ye vardığında ~19 m/s'ye düşer. Düz çizgi varsayan
	   basit simülasyonların "top hep kaleye giriyor" hatası buradan gelir.

	2) MAGNUS (spin / falso)
	   a = 0.5 * rho * A * Cl * v² * (ω̂ × v̂) / m
	   Falso ekseni ile hız vektörünün çapraz çarpımı, topun yana (veya yukarı/aşağı)
	   bükülmesini sağlar. Cl, spin oranı S = ω*r/v ile büyür — yavaş topta
	   falso daha çok etki eder, hızlı topta azalır; gerçek futbolun sezgisi budur.

	Cd'nin hıza bağlı olması ("drag crisis"): 12-30 m/s arasında Cd 0.47'den 0.25'e
	düşer. Knuckleball'un düzensiz uçuşunun sebebi budur; burada yumuşak geçiş
	olarak modellenir (tam türbülans modeli Roblox'ta gereksiz maliyetli).
]]

local Vec3 = require(script.Parent.Vec3)

local Aero = {}

local sqrt = math.sqrt
local exp = math.exp

-- Hıza bağlı direnç katsayısı: drag crisis geçişi.
function Aero.dragCoefficientFor(speed, cfg)
	local b = cfg.BALL
	local slow, fast = b.dragCoefficientSlow, b.dragCoefficient
	local mid = b.dragCrisisSpeed
	local width = b.dragCrisisWidth
	-- 1 / (1 + exp((v - mid) / width)) : yavaşta 1, hızlıda 0 olan yumuşak geçiş
	local t = 1 / (1 + exp((speed - mid) / width))
	return fast + (slow - fast) * t
end

-- Hava direnci ivmesi (m/s²).
function Aero.dragAccel(vel, cfg)
	local speedSq = Vec3.lengthSq(vel)
	local speed = sqrt(speedSq)
	if speed < 1e-6 then
		return Vec3.ZERO
	end
	local b = cfg.BALL
	local cd = Aero.dragCoefficientFor(speed, cfg)
	local k = 0.5 * cfg.AIR.density * b.crossSection * cd * speed / b.mass
	return Vec3.scale(vel, -k)
end

-- Magnus (spin) ivmesi (m/s²).
function Aero.magnusAccel(vel, spin, cfg)
	local speed = Vec3.length(vel)
	if speed < 1e-6 then
		return Vec3.ZERO
	end
	local omega = Vec3.length(spin)
	if omega < 1e-6 then
		return Vec3.ZERO
	end
	local b = cfg.BALL
	local spinRatio = omega * b.radius / speed -- S boyutsuz
	local cl = b.magnusScale * spinRatio
	if cl > b.magnusMax then
		cl = b.magnusMax
	end
	-- (ω̂ × v̂): hem yön hem birim uzunluk; cross(ω, v) normalize etmek yeterli
	local dir = Vec3.unit(Vec3.cross(spin, vel))
	local k = 0.5 * cfg.AIR.density * b.crossSection * cl * speed * speed / b.mass
	return Vec3.scale(dir, k)
end

-- Havadaki toplam ivme (yerçekimi + drag + Magnus). Sadece havada çağırın.
function Aero.totalAccel(vel, spin, cfg)
	local acc = Vec3.new(0, -cfg.GRAVITY, 0)
	acc = Vec3.add(acc, Aero.dragAccel(vel, cfg))
	acc = Vec3.add(acc, Aero.magnusAccel(vel, spin, cfg))
	return acc
end

-- Teorik terminal hız: 2mg / (rho*A*Cd) kökü. Test ve telemetri için.
function Aero.terminalSpeed(cfg)
	local b = cfg.BALL
	return sqrt(2 * b.mass * cfg.GRAVITY / (cfg.AIR.density * b.crossSection * b.dragCoefficient))
end

return Aero
]=] },
	["shared/Core/Ballistics"] = { class = "ModuleScript", source = [=[
--[[
	Ballistics — hedefe vuruş açısı çözümü.

	Bir oyuncu (veya AI) "şu noktaya şu hızla" pas/şut atmak istediğinde, yerçekimi
	altında gereken fırlatma açısını burada çözüyoruz. Formül, sabit yerçekimi
	varsayımıyla klasik eğik atış çözümüdür (hava direnci ihmal edilir; %5-8 hata
	yapar, gerçek oyuncunun nişan hatasıyla aynı mertebede).

	Denklem:  tanθ = (v² ± sqrt(v⁴ - g(g·R² + 2·h·v²))) / (g·R)
	  R = yatay mesafe, h = hedefin yükseklik farkı
	  "−" düz (sert) yörünge, "+" aşırtma (lob) yörüngesi

	Çözüm yoksa (hedef menzil dışı) nil döner — AI bunu "pas imkânsız" olarak yorumlar.
]]

local Vec3 = require(script.Parent.Vec3)

local Ballistics = {}

function Ballistics.solveLaunch(from, to, speed, gravity, highArc)
	local g = gravity or 9.81
	local dx = to.x - from.x
	local dz = to.z - from.z
	local h = to.y - from.y
	local horiz = math.sqrt(dx * dx + dz * dz)

	if speed <= 0 then
		return nil
	end
	if horiz < 1e-4 then
		-- Dikey atış
		return Vec3.new(0, speed, 0)
	end

	local v2 = speed * speed
	local disc = v2 * v2 - g * (g * horiz * horiz + 2 * h * v2)
	if disc < 0 then
		return nil
	end
	local root = math.sqrt(disc)
	local tanTheta
	if highArc then
		tanTheta = (v2 + root) / (g * horiz)
	else
		tanTheta = (v2 - root) / (g * horiz)
	end

	local theta = math.atan(tanTheta)
	local dir = Vec3.unit(Vec3.new(dx, 0, dz))
	local cosT = math.cos(theta)
	local sinT = math.sin(theta)

	return Vec3.new(dir.x * speed * cosT, speed * sinT, dir.z * speed * cosT)
end

-- Verilen hızla hedefe ulaşılabilir mi?
function Ballistics.isReachable(from, to, speed, gravity)
	return Ballistics.solveLaunch(from, to, speed, gravity) ~= nil
end

return Ballistics
]=] },
	["shared/Core/Rng"] = { class = "ModuleScript", source = [=[
--[[
	Rng — deterministik sözde rastgele sayı üreteci (Park–Miller / MINSTD).

	Neden math.random değil?
	  * Roblox'un math.random'ı sunucu/istemcide ayrı tohumlanır ve sürümler arası
	    garantisi yoktur. Ağ senkronu ve tekrar oynatma (replay) için aynı tohumdan
	    aynı diziyi üretmemiz şart.
	  * Sadece double aritmetiği kullanır: Lua 5.1, Lua 5.3 ve Luau'da bit-bit aynı
	    sonucu verir (bitwise operatör yok, taşma yok).
]]

local Rng = {}
Rng.__index = Rng

local MOD = 2147483647 -- 2^31 - 1
local MUL = 48271 -- 48271 * 2^31 < 2^53 olduğu için double'da tam duyarlı

function Rng.new(seed)
	local s = math.floor(math.abs(tonumber(seed) or 1)) % MOD
	if s == 0 then
		s = 1
	end
	return setmetatable({ state = s, seed = s }, Rng)
end

-- [0, 1) aralığında float.
function Rng:next()
	self.state = (self.state * MUL) % MOD
	return (self.state - 1) / (MOD - 1)
end

-- [0, 1] aralığında float.
function Rng:nextInclusive()
	self.state = (self.state * MUL) % MOD
	return self.state / MOD
end

-- [a, b) aralığında float.
function Rng:range(a, b)
	return a + (b - a) * self:next()
end

-- [-a, +a] aralığında float.
function Rng:symmetric(a)
	return (self:next() * 2 - 1) * a
end

-- [a, b] aralığında tam sayı.
function Rng:int(a, b)
	if b < a then
		a, b = b, a
	end
	return a + math.floor(self:next() * (b - a + 1))
end

-- Normal dağılım (Box–Muller). Şut/pas hatası için gerçekçi sapma üretir.
function Rng:normal(mean, stddev)
	local u1 = math.max(self:next(), 1e-12)
	local u2 = self:next()
	local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
	return (mean or 0) + z * (stddev or 1)
end

function Rng:chance(p)
	return self:next() < p
end

function Rng:pick(list)
	return list[self:int(1, #list)]
end

function Rng:clone()
	return setmetatable({ state = self.state, seed = self.seed }, Rng)
end

return Rng
]=] },
	["shared/Core/Vec3"] = { class = "ModuleScript", source = [=[
--[[
	Vec3 — saf Lua vektör matematiği.

	Neden Roblox'un Vector3'ü değil?
	  * Çekirdek simülasyonun motor API'sine bağımlı olmaması gerekiyor: aynı kod
	    hem Roblox içinde hem de masaüstünde (test/CI) çalışmalı.
	  * Determinizm: float32 Vector3 yuvarlama hataları birikim yapar; burada
	    standart Lua double (float64) kullanıyoruz.
	  * Roblox katmanı (görsel) bu vektörleri Vector3'e çevirir, o kadar.

	Koordinat sistemi (saha merkezli, sağ el):
	  +x : orta saha çizgisinden bir kaleye doğru (uzunluk ekseni)
	  +z : yan çizgiye doğru (genişlik ekseni)
	  +y : yukarı (yerçekimine zıt)

	Kural: tüm fonksiyonlar YENİ tablo döndürür, argümanları asla değiştirmez.
]]

local Vec3 = {}
local sqrt = math.sqrt
-- Lua 5.3: math.atan(y, x) | Luau: math.atan2(y, x). Ikisi de desteklensin.
local atan2 = math.atan2 or math.atan

local function make(x, y, z)
	return { x = x, y = y, z = z }
end

Vec3.new = function(x, y, z)
	return make(x or 0, y or 0, z or 0)
end

-- Paylaşılan sabitler: değiştirilmemeli (tüm fonksiyonlar yeni tablo döndürür).
Vec3.ZERO = make(0, 0, 0)
Vec3.UP = make(0, 1, 0)

function Vec3.add(a, b)
	return make(a.x + b.x, a.y + b.y, a.z + b.z)
end

function Vec3.sub(a, b)
	return make(a.x - b.x, a.y - b.y, a.z - b.z)
end

function Vec3.scale(v, k)
	return make(v.x * k, v.y * k, v.z * k)
end

function Vec3.negate(v)
	return make(-v.x, -v.y, -v.z)
end

function Vec3.addScaled(a, b, k)
	return make(a.x + b.x * k, a.y + b.y * k, a.z + b.z * k)
end

function Vec3.dot(a, b)
	return a.x * b.x + a.y * b.y + a.z * b.z
end

function Vec3.cross(a, b)
	return make(
		a.y * b.z - a.z * b.y,
		a.z * b.x - a.x * b.z,
		a.x * b.y - a.y * b.x
	)
end

function Vec3.lengthSq(v)
	return v.x * v.x + v.y * v.y + v.z * v.z
end

function Vec3.length(v)
	return sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

-- Yatay (y=0) düzlemdeki hız bileşeni.
function Vec3.horizontal(v)
	return make(v.x, 0, v.z)
end

function Vec3.lengthHorizontal(v)
	return sqrt(v.x * v.x + v.z * v.z)
end

function Vec3.withY(v, y)
	return make(v.x, y, v.z)
end

function Vec3.unit(v)
	local len = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
	if len < 1e-12 then
		return make(0, 0, 0)
	end
	local inv = 1 / len
	return make(v.x * inv, v.y * inv, v.z * inv)
end

function Vec3.lerp(a, b, t)
	return make(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
end

-- a vektörünün b vektörü üzerindeki izdüşümü.
function Vec3.project(a, b)
	local d = Vec3.dot(b, b)
	if d < 1e-12 then
		return make(0, 0, 0)
	end
	return Vec3.scale(b, Vec3.dot(a, b) / d)
end

-- İki vektör arasındaki açı (radyan).
function Vec3.angleBetween(a, b)
	local denom = Vec3.length(a) * Vec3.length(b)
	if denom < 1e-12 then
		return 0
	end
	local c = Vec3.dot(a, b) / denom
	if c > 1 then c = 1 elseif c < -1 then c = -1 end
	return math.acos(c)
end

-- Yatay düzlemde yön açısı: +x ekseninden +z'ye doğru (atan2(z, x)).
function Vec3.yaw(v)
	return atan2(v.z, v.x)
end

function Vec3.fromYaw(angle)
	return make(math.cos(angle), 0, math.sin(angle))
end

function Vec3.distance(a, b)
	return Vec3.length(Vec3.sub(a, b))
end

function Vec3.distanceHorizontal(a, b)
	return Vec3.lengthHorizontal(Vec3.sub(a, b))
end

function Vec3.isFinite(v)
	return v.x == v.x and v.y == v.y and v.z == v.z
		and math.abs(v.x) < 1e30 and math.abs(v.y) < 1e30 and math.abs(v.z) < 1e30
end

function Vec3.tostring(v)
	return string.format("(%.3f, %.3f, %.3f)", v.x, v.y, v.z)
end

return Vec3
]=] },
	["shared/Physics/Ball"] = { class = "ModuleScript", source = [=[
--[[
	Ball — topun deterministik fizik modeli.

	ADIM 1'İN KALBİ. Top Roblox'un fizik motoruna BIRAKILMAZ; burada 240 Hz'de
	kendi entegratörümüzle simüle edilir. Sebepleri:

	  * Roblox fiziği float32 + motor içi çözücü; sekme/temas davranışı ayarlanamaz
	    (restitution ayarı yok, sadece CustomPhysicalProperties ile kaba kontrol).
	  * Sunucu ve istemci aynı sonucu üretmez -> istemci tahmini (prediction) ve
	    gecikme telafisi (lag compensation) yapılamaz.
	  * Gerçek aerodinamik (drag + Magnus + drag crisis) Roblox'ta yok.

	Bu modül şunları yapar:
	  1) Havada: yerçekimi + drag + Magnus, yarı-örtük Euler.
	  2) Zemine teması ANALİTİK olarak yakalar: adım içinde y(t)=r denkleminin
	     kökünü bulur, temas anına kadar entegre eder, sekmeyi uygular, kalan
	     süreyi yeniden işler. Yani sekme yüksekliği adım boyutundan bağımsızdır
	     (tünelleme ve "top zemine gömülüyor" hataları oluşmaz).
	  3) Sekmede Coulomb sürtünmesi: temas noktasındaki kayma hızı, normal impuls
	     ile sınırlı teğetsel impuls üretir. Topspin topu ileri hızlandırır,
	     backspin yavaşlatır — gerçek davranış.
	  4) Yuvarlanma: yuvarlanma direnci + kaymadan yuvarlanma koşulu (ω = v/r).

	Koordinatlar: saha merkezli metre. Zemin y=0, top merkezi y=r iken yuvarlanır.
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)
local Aero = require(script.Parent.Parent.Core.Aero)

local Ball = {}
Ball.__index = Ball

local sqrt = math.sqrt
local abs = math.abs
local min = math.min

--[[
	y(t) = y0 + vy0*t + 0.5*ay*t² = r  denkleminin [0, dt] içindeki en küçük kökü.
	Sabit ivme varsayımı geçerli (bir adım boyunca aerodinamik ivme sabit kabul
	edilir; 1/240 s'de hata ihmal edilebilir).
]]
local function solveContactTime(y0, vy0, ay, r, dt)
	local a = 0.5 * ay
	local b = vy0
	local c = y0 - r

	if abs(a) < 1e-9 then
		if abs(b) < 1e-9 then
			return nil
		end
		local t = -c / b
		if t >= 0 and t <= dt then
			return t
		end
		return nil
	end

	local disc = b * b - 4 * a * c
	if disc < 0 then
		return nil
	end

	local sq = sqrt(disc)
	local inv2a = 1 / (2 * a)
	local t1 = (-b - sq) * inv2a
	local t2 = (-b + sq) * inv2a

	local best = nil
	if t1 >= 0 and t1 <= dt then
		best = t1
	end
	if t2 >= 0 and t2 <= dt and (best == nil or t2 < best) then
		best = t2
	end
	return best
end

function Ball.new(cfg, position)
	local r = cfg.BALL.radius
	local pos = position or Vec3.new(0, r, 0)
	local ball = setmetatable({
		cfg = cfg,
		pos = pos,
		vel = Vec3.new(0, 0, 0),
		spin = Vec3.new(0, 0, 0),
		mode = "ground", -- "air" | "ground"
		contacts = 0, -- toplam zemin teması sayısı (telemetri/test)
		postHits = 0, -- direk/üst direk çarpışması sayısı (telemetri/test)
	}, Ball)
	-- Havada başlıyorsa modu düzelt
	if pos.y > r + 1e-6 then
		ball.mode = "air"
	end
	return ball
end

function Ball:setState(position, velocity, spin)
	self.pos = position or self.pos
	self.vel = velocity or Vec3.new(0, 0, 0)
	self.spin = spin or Vec3.new(0, 0, 0)
	local r = self.cfg.BALL.radius
	-- Mod SADECE konuma bakmaz: zeminde duran topa yukarı doğru vurulursa havaya
	-- çıkar. (Bu satır olmadan tüm vuruşlar "yuvarlanma" olarak yorumlanıyordu.)
	self.mode = (self.pos.y > r + 1e-6 or self.vel.y > 1e-6) and "air" or "ground"
	if self.mode == "ground" then
		self.pos = Vec3.withY(self.pos, r)
	end
end

-- Vuruş: hız ve spin ata. (Adım 4'te pas/şut sistemleri bunu kullanacak.)
function Ball:kick(velocity, spin)
	self.vel = velocity
	self.spin = spin or Vec3.new(0, 0, 0)
	local r = self.cfg.BALL.radius
	self.mode = (self.pos.y > r + 1e-6 or self.vel.y > 1e-6) and "air" or "ground"
end

function Ball:speed()
	return Vec3.length(self.vel)
end

function Ball:spinRps()
	return Vec3.length(self.spin) / (2 * math.pi)
end

function Ball:isFinite()
	return Vec3.isFinite(self.pos) and Vec3.isFinite(self.vel) and Vec3.isFinite(self.spin)
end

function Ball:snapshot()
	return {
		pos = { x = self.pos.x, y = self.pos.y, z = self.pos.z },
		vel = { x = self.vel.x, y = self.vel.y, z = self.vel.z },
		spin = { x = self.spin.x, y = self.spin.y, z = self.spin.z },
		mode = self.mode,
	}
end

function Ball:_decaySpin(dt)
	local k = math.exp(-self.cfg.BALL.spinDecay * dt)
	if k < 1 then
		self.spin = Vec3.scale(self.spin, k)
	end
end

--[[
	Sabit ivme altında TAM çözüm (yamuk kuralı / velocity-Verlet):

		v' = v + a*dt
		p' = p + (v + v')/2 * dt

	Klasik yarı-örtük Euler'in (p' = p + v'*dt) aksine burada serbest düşüş
	yörüngesi adım boyutundan bağımsız olarak doğrudur: 60 Hz ile 240 Hz aynı tepe
	noktasını verir. Fiziksel doğruluk için kritik — aksi halde düşük FPS'te
	oynayan oyuncunun şutları 1-2 m sapardı.
]]
function Ball:_integrate(acc, dt)
	local velNew = Vec3.add(self.vel, Vec3.scale(acc, dt))
	local avgVel = Vec3.scale(Vec3.add(self.vel, velNew), 0.5)
	self.pos = Vec3.add(self.pos, Vec3.scale(avgVel, dt))
	self.vel = velNew
end

--[[
	Sekme çözümü. Gelen dikey hız negatif (top aşağı iniyor).
	1) Dikey: v_y' = -e * v_y
	2) Teğetsel: temas noktasındaki kayma = v_t + ω × (0,-r,0)
	   |J_t| <= mu * |J_n|  (Coulomb)
	   Δω = (offset × Δv) * 5/(2r²)  (katı küre, I = 2/5 m r²)
]]
function Ball:_bounce()
	local cfg = self.cfg
	local b = cfg.BALL
	local r = b.radius
	local vy = self.vel.y

	-- Çok yavaş dikey çarpma: sekmez, yuvarlanmaya geçer.
	if -vy < b.rollThreshold then
		self.pos = Vec3.withY(self.pos, r)
		self.vel = Vec3.withY(self.vel, 0)
		self.spin = Vec3.new(self.vel.z / r, self.spin.y * 0.5, -self.vel.x / r)
		self.mode = "ground"
		self.contacts = self.contacts + 1
		return
	end

	-- Spinin sekme yüksekliğine etkisi (ampirik, küçük katsayı):
	-- topspin topu biraz alçak, backspin biraz yüksek zıplatır.
	local horiz = Vec3.lengthHorizontal(self.vel)
	local e = b.restitution
	if horiz > 0.5 then
		local fwd = Vec3.scale(self.vel, 1 / horiz)
		local axis = Vec3.cross(Vec3.UP, fwd) -- topspin ekseni
		local rollingRate = horiz / r
		local t = Vec3.dot(self.spin, axis) / rollingRate -- [-1, 1] civarı
		if t > 1 then t = 1 elseif t < -1 then t = -1 end
		e = e * (1 - b.spinBounceCoupling * t)
	end

	local jn = (1 + e) * (-vy) -- birim kütle normal impuls (m/s)

	-- Teğetsel impuls
	local offset = Vec3.new(0, -r, 0)
	local surface = Vec3.cross(self.spin, offset) -- ω × offset
	local slip = Vec3.new(self.vel.x + surface.x, 0, self.vel.z + surface.z)
	local slipLen = Vec3.length(slip)
	local maxDv = b.contactFriction * jn

	if slipLen > 1e-6 and maxDv > 1e-6 then
		local dvMag = min(slipLen, maxDv)
		local dvel = Vec3.scale(slip, -dvMag / slipLen)
		self.vel = Vec3.add(self.vel, dvel)
		local dOmega = Vec3.scale(Vec3.cross(offset, dvel), 5 / (2 * r * r))
		self.spin = Vec3.add(self.spin, dOmega)
	end

	self.vel = Vec3.withY(self.vel, -e * vy)
	self.pos = Vec3.withY(self.pos, r)
	self.contacts = self.contacts + 1

	-- Enerji bittiyse yuvarlanmaya geç
	if -e * vy < b.rollThreshold * 0.4 then
		self.mode = "ground"
	end
end

-- Havada bir adım. Dönüş değeri: işlenmemiş kalan süre.
function Ball:_stepAir(dt)
	local cfg = self.cfg
	local r = cfg.BALL.radius
	local acc = Aero.totalAccel(self.vel, self.spin, cfg)

	-- Zeminden yeni ayrılan top (y = r, vy >= 0) için denklemin t=0 kökü çıkar;
	-- bu bir çarpma değildir, yoksa sekme anında dikey hız sıfırlanır.
	if self.pos.y <= r + 1e-9 and self.vel.y >= 0 then
		self:_integrate(acc, dt)
		self:_decaySpin(dt)
		return 0
	end

	local t = solveContactTime(self.pos.y, self.vel.y, acc.y, r, dt)
	if t == nil then
		self:_integrate(acc, dt)
		self:_decaySpin(dt)
		return 0
	end

	-- Zemine değene kadar entegre et, sek, kalan süreyi geri ver.
	self:_integrate(acc, t)
	self:_decaySpin(t)
	self:_bounce()
	return dt - t
end

-- Yerde yuvarlanma.
function Ball:_stepGround(dt)
	local cfg = self.cfg
	local b = cfg.BALL
	local r = b.radius
	local speed = Vec3.lengthHorizontal(self.vel)

	if speed <= b.stopSpeed then
		self.vel = Vec3.new(0, 0, 0)
		self.spin = Vec3.new(0, 0, 0)
		self.pos = Vec3.withY(self.pos, r)
		return 0
	end

	local decel = b.rollResistance * cfg.GRAVITY
	local newSpeed = speed - decel * dt
	if newSpeed < 0 then
		newSpeed = 0
	end

	local dir = Vec3.scale(self.vel, 1 / speed)
	self.vel = Vec3.scale(dir, newSpeed)
	self.pos = Vec3.add(self.pos, Vec3.scale(self.vel, dt))
	self.pos = Vec3.withY(self.pos, r)

	-- Kaymadan yuvarlanma: ω = (vz/r, ωy, -vx/r)
	self.spin = Vec3.new(self.vel.z / r, self.spin.y, -self.vel.x / r)
	return 0
end

-- Tek simülasyon adımı. dt sabit (Config.FIXED_DT) olmalıdır.
function Ball:step(dt)
	if dt <= 0 then
		return
	end
	local remaining = dt
	local guard = 0
	while remaining > 1e-9 do
		guard = guard + 1
		if guard > 6 then
			remaining = 0
			break
		end
		if self.mode == "ground" then
			remaining = self:_stepGround(remaining)
		else
			remaining = self:_stepAir(remaining)
		end
	end
end

-- Gelecekteki durumu tahmin et (kaleciler, istemci tahmini, AI için).
-- Simülasyonun kopyası üzerinde çalışır; asıl topu etkilemez.
function Ball:clone()
	local copy = Ball.new(self.cfg, Vec3.new(self.pos.x, self.pos.y, self.pos.z))
	copy.vel = Vec3.new(self.vel.x, self.vel.y, self.vel.z)
	copy.spin = Vec3.new(self.spin.x, self.spin.y, self.spin.z)
	copy.mode = self.mode
	copy.contacts = self.contacts
	copy.postHits = self.postHits
	return copy
end

-- Belirli bir süre sonraki durumu döndürür (topu değiştirmez).
function Ball:predict(dt, steps)
	local copy = self:clone()
	local n = steps or math.max(1, math.ceil(dt / self.cfg.FIXED_DT))
	local h = dt / n
	for _ = 1, n do
		copy:step(h)
	end
	return copy
end

return Ball
]=] },
	["shared/Physics/Body"] = { class = "ModuleScript", source = [=[
--[[
	Body — hareketli gövde (oyuncu/kaleci) ile top çarpışması.

	Oyuncu ve kaleci dikey bir kapsül (silindir) olarak modellenir. Top küre.
	Çarpışma anında:
	  * top yüzeyin dışına taşınır,
	  * gövdeye GÖRE bağıl hız yansıtılır (koşan oyuncu topa hız katar),
	  * teğetsel sürtünme uygulanır.

	Neden bağıl hız? Sabit gövdeye çarpan top sadece seker; koşan bir oyuncunun
	bacağına çarpan top ise oyuncunun hızını da alır. Bu, "top oyuncudan sekiyor"
	hissini veren kritik detaydır.

	Roblox API'si kullanmaz -> test edilebilir.
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)

local Body = {}

local sqrt = math.sqrt
local min = math.min

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

-- Bir noktaya, dikey doğru parçası üzerindeki en yakın nokta.
local function closestOnVerticalSegment(point, base, height)
	local y = clamp(point.y, base.y, base.y + height)
	return Vec3.new(base.x, y, base.z)
end

--[[ Topu gövdeye karşı çözer. body:
	{ pos = Vec3 (ayak seviyesi), vel = Vec3, radius, height, restitution, hits }
	Dönüş: çarpıştı mı? ]]
function Body.collide(ball, body)
	if not body or not body.pos then
		return false
	end
	local ballR = ball.cfg.BALL.radius
	local bodyR = body.radius or 0.42
	local height = body.height or 1.8
	local e = body.restitution or 0.42

	local closest = closestOnVerticalSegment(ball.pos, body.pos, height)
	local delta = Vec3.sub(ball.pos, closest)
	local dist = Vec3.length(delta)
	local minDist = ballR + bodyR

	if dist >= minDist then
		return false
	end

	local n
	if dist > 1e-9 then
		n = Vec3.scale(delta, 1 / dist)
	else
		n = Vec3.negate(Vec3.unit(ball.vel))
		if Vec3.lengthSq(n) < 1e-9 then
			n = Vec3.new(1, 0, 0)
		end
	end

	-- Topu dışarı taşı
	ball.pos = Vec3.add(closest, Vec3.scale(n, minDist + 1e-4))

	-- Bağıl hız: top - gövde
	local bodyVel = body.vel or Vec3.ZERO
	local relVel = Vec3.sub(ball.vel, bodyVel)
	local vn = Vec3.dot(relVel, n)

	if vn < 0 then
		-- Normal bileşen: yansıt ve gövde hızını ekle
		local newRel = Vec3.sub(relVel, Vec3.scale(n, (1 + e) * vn))

		-- Teğetsel sürtünme (top ayağa sürtünür)
		local normalPart = Vec3.scale(n, Vec3.dot(newRel, n))
		local tangent = Vec3.sub(newRel, normalPart)
		local tangentSpeed = Vec3.length(tangent)
		if tangentSpeed > 1e-6 then
			local mu = body.friction or 0.30
			local reduce = min(tangentSpeed, mu * (1 + e) * (-vn))
			tangent = Vec3.scale(tangent, 1 - reduce / tangentSpeed)
		end

		ball.vel = Vec3.add(Vec3.add(bodyVel, normalPart), tangent)
		ball.spin = Vec3.scale(ball.spin, 0.7)
		body.hits = (body.hits or 0) + 1
	end

	return true
end

--[[ Bir gövdenin topa uzanıp uzanamayacağını ölçer (kaleci uzanma mesafesi,
	oyuncu kademesi). Dönüş: mesafe (m). ]]
function Body.reachDistance(ball, body)
	local closest = closestOnVerticalSegment(ball.pos, body.pos, body.height or 1.8)
	return Vec3.length(Vec3.sub(ball.pos, closest))
end

return Body
]=] },
	["shared/Physics/Colliders"] = { class = "ModuleScript", source = [=[
--[[
	Colliders — top ile direk/üst direk çarpışması.

	Direkler silindir, üst direk yatay silindirdir. Bunları "doğru parçası + yarıçap"
	(kapsül) olarak modelliyoruz; top da bir küre. Böylece genel bir çözücü yeterli:

	  1) Topun bu adımdaki hareket doğrusu (önceki konum -> yeni konum) ile direk
	     ekseni arasındaki EN YAKIN noktalar bulunur.
	  2) Mesafe (top yarıçapı + direk yarıçapı)'ndan küçükse çarpışma vardır.
	  3) Top yüzeyin dışına taşınır, normal bileşen -e ile yansıtılır, teğetsel
	     bileşene sürtünme uygulanır.

	Neden hareket doğrusu üzerinden? 30 m/s'lik bir şut 240 Hz'de adım başına
	12.5 cm ilerler; direk yarıçapı 6 cm olduğu için sadece konum kontrolü
	(discrete) bazı çarpışmaları kaçırırdı. Sürekli (continuous) test bunu önler.

	Bu modül Roblox API'si kullanmaz: aynı kod hem sunucuda hem testte çalışır.
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)

local Colliders = {}

local sqrt = math.sqrt
local min = math.min

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

--[[ İki doğru parçası arasındaki en yakın noktalar (Ericson, Real-Time Collision
	Detection, 5.1.9). Dönüş: c1 (p1-q1 üzerinde), c2 (p2-q2 üzerinde). ]]
local function closestPointsBetweenSegments(p1, q1, p2, q2)
	local d1 = Vec3.sub(q1, p1)
	local d2 = Vec3.sub(q2, p2)
	local r = Vec3.sub(p1, p2)

	local a = Vec3.dot(d1, d1)
	local e = Vec3.dot(d2, d2)
	local f = Vec3.dot(d2, r)

	local s, t

	if a <= 1e-12 and e <= 1e-12 then
		s, t = 0, 0
	elseif a <= 1e-12 then
		s = 0
		t = clamp(f / e, 0, 1)
	else
		local c = Vec3.dot(d1, r)
		if e <= 1e-12 then
			t = 0
			s = clamp(-c / a, 0, 1)
		else
			local b = Vec3.dot(d1, d2)
			local denom = a * e - b * b
			if denom > 1e-12 then
				s = clamp((b * f - c * e) / denom, 0, 1)
			else
				s = 0
			end
			t = (b * s + f) / e
			if t < 0 then
				t = 0
				s = clamp(-c / a, 0, 1)
			elseif t > 1 then
				t = 1
				s = clamp((b - c) / a, 0, 1)
			end
		end
	end

	local c1 = Vec3.add(p1, Vec3.scale(d1, s))
	local c2 = Vec3.add(p2, Vec3.scale(d2, t))
	return c1, c2
end

Colliders.closestPointsBetweenSegments = closestPointsBetweenSegments

--[[ Tek bir kapsül engeline karşı çarpışma çözümü. Dönüş: çarpıştı mı? ]]
local function resolveObstacle(ball, obs, fromPos)
	local cfg = ball.cfg
	local r = cfg.BALL.radius

	local c1, c2 = closestPointsBetweenSegments(fromPos, ball.pos, obs.a, obs.b)
	local delta = Vec3.sub(c1, c2)
	local dist = Vec3.length(delta)
	local minDist = r + (obs.radius or 0.06)

	if dist >= minDist then
		return false
	end

	-- Normal: direk ekseninden topa doğru
	local n
	if dist > 1e-9 then
		n = Vec3.scale(delta, 1 / dist)
	else
		n = Vec3.negate(Vec3.unit(ball.vel))
		if Vec3.lengthSq(n) < 1e-9 then
			n = Vec3.new(1, 0, 0)
		end
	end

	-- Topu yüzeyin dışına taşı (gömülmeyi önler)
	ball.pos = Vec3.add(c2, Vec3.scale(n, minDist + 1e-4))

	local vn = Vec3.dot(ball.vel, n)
	if vn >= 0 then
		-- Uzaklaşıyor: sadece konum düzeltmesi yeterli
		return true
	end

	local e = cfg.BALL.postRestitution or 0.62
	local vt = Vec3.sub(ball.vel, Vec3.scale(n, vn))
	local tangentSpeed = Vec3.length(vt)

	if tangentSpeed > 1e-6 then
		local mu = cfg.BALL.postFriction or 0.35
		local normalImpulse = (1 + e) * (-vn) -- birim kütle
		local reduce = min(tangentSpeed, mu * normalImpulse)
		vt = Vec3.scale(vt, 1 - reduce / tangentSpeed)
	end

	ball.vel = Vec3.add(Vec3.scale(n, -e * vn), vt)

	-- Spini gerçekçi biçimde sönümle (çarpma enerjinin bir kısmını yutar)
	ball.spin = Vec3.scale(ball.spin, 0.55)
	ball.postHits = (ball.postHits or 0) + 1
	return true
end

--[[ Topu tüm engellere karşı kontrol eder. fromPos: adım öncesi konum. ]]
function Colliders.resolve(ball, obstacles, fromPos)
	if not obstacles or #obstacles == 0 then
		return 0
	end
	local from = fromPos or ball.pos
	local hits = 0
	for i = 1, #obstacles do
		if resolveObstacle(ball, obstacles[i], from) then
			hits = hits + 1
		end
	end
	return hits
end

return Colliders
]=] },
	["shared/Physics/Net"] = { class = "ModuleScript", source = [=[
--[[
	Net — file (ağ) fiziği: top kaleye girdiğinde ne olur?

	Gerçek futbolda top fileye girdiğinde:
	  * hızı hızla düşer (ağ enerjiyi yutar, top "ölür"),
	  * file esner, sonra toparlanır,
	  * top geri sekmez — file bir yay değil, sönümleyicidir,
	  * top file içinde kalır (yan/üst/arka ağ onu tutar).

	Bu modül top kale kutusunun içindeyken:
	  1) Üstel sönüm uygular: v *= exp(-k·dt)  (k = NET.damping)
	  2) Arka/y an/üst ağ düzlemlerine çok düşük sekme katsayısıyla çarptırır
	  3) Ağın esnemesini yay-sönümleyici olarak modeller (sag)

	Esneme (sag) görsel olarak da kullanılır: sunucu arka ağ parçasını öteleyerek
	topun ağa gömülmesini gösterir.

	Roblox API'si kullanmaz -> aynı kod testte ve oyunda çalışır.
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)

local Net = {}
Net.__index = Net

local abs = math.abs
local min = math.min
local max = math.max
local exp = math.exp

function Net.new(cfg, side)
	return setmetatable({
		cfg = cfg,
		side = side or 1, -- 1: +x kalesi, -1: -x kalesi
		sag = 0,
		sagVel = 0,
		contacts = 0,
		lastImpactSpeed = 0,
	}, Net)
end

-- Top kale kutusunun içinde mi? (ağ bölgesi)
function Net:isInsideGoalBox(pos)
	local P = self.cfg.PITCH
	local r = self.cfg.BALL.radius
	local x0 = self.side * P.halfLength
	local x1 = self.side * (P.halfLength + P.goalDepth)
	local lo, hi = min(x0, x1), max(x0, x1)
	return pos.x >= lo - r and pos.x <= hi + r and abs(pos.z) <= P.goalHalfWidth + r and pos.y <= P.goalHeight + r
end

--[[ Ağın esneme dinamiği: yay + sönümleyici. ]]
function Net:_stepSag(dt)
	local N = self.cfg.NET
	local accel = -N.sagStiffness * self.sag - N.sagDamping * self.sagVel
	self.sagVel = self.sagVel + accel * dt
	self.sag = self.sag + self.sagVel * dt
	if self.sag < 0 then
		self.sag = 0
		if self.sagVel < 0 then
			self.sagVel = 0
		end
	elseif self.sag > N.maxSag then
		self.sag = N.maxSag
		if self.sagVel > 0 then
			self.sagVel = 0
		end
	end
end

--[[ Topu ağ içinde işler. Dönüş: ağ teması oldu mu? ]]
function Net:stepBall(ball, dt)
	local P = self.cfg.PITCH
	local N = self.cfg.NET
	local r = ball.cfg.BALL.radius

	self:_stepSag(dt)

	if not self:isInsideGoalBox(ball.pos) then
		return false
	end

	-- 1) Ağ içindeki hava/sürtünme kaybı: top "ölür"
	local k = exp(-N.damping * dt)
	ball.vel = Vec3.scale(ball.vel, k)
	ball.spin = Vec3.scale(ball.spin, k)

	local touched = false

	-- 2) Arka ağ: x = side * (halfLength + goalDepth - r + sag)
	local backLimit = self.side * (P.halfLength + P.goalDepth - r + self.sag)
	if self.side > 0 and ball.pos.x > backLimit then
		if ball.vel.x > 0 then
			self.lastImpactSpeed = ball.vel.x
			self.sagVel = self.sagVel + ball.vel.x * N.sagImpulse
			ball.vel.x = -N.restitution * ball.vel.x
			ball.vel.y = ball.vel.y * 0.55
			ball.vel.z = ball.vel.z * (1 - N.friction * 0.6)
			touched = true
		end
		ball.pos.x = backLimit
	elseif self.side < 0 and ball.pos.x < backLimit then
		if ball.vel.x < 0 then
			self.lastImpactSpeed = -ball.vel.x
			self.sagVel = self.sagVel - ball.vel.x * N.sagImpulse
			ball.vel.x = -N.restitution * ball.vel.x
			ball.vel.y = ball.vel.y * 0.55
			ball.vel.z = ball.vel.z * (1 - N.friction * 0.6)
			touched = true
		end
		ball.pos.x = backLimit
	end

	-- 3) Yan ağlar
	local sideLimit = P.goalHalfWidth - r
	if abs(ball.pos.z) > sideLimit then
		local sign = ball.pos.z > 0 and 1 or -1
		ball.pos.z = sign * sideLimit
		if ball.vel.z * sign > 0 then
			ball.vel.z = -N.sideRestitution * ball.vel.z
			touched = true
		end
	end

	-- 4) Üst ağ
	local topLimit = P.goalHeight - r
	if ball.pos.y > topLimit then
		ball.pos.y = topLimit
		if ball.vel.y > 0 then
			ball.vel.y = -N.topRestitution * ball.vel.y
			touched = true
		end
	end

	if touched then
		self.contacts = self.contacts + 1
	end

	return touched
end

function Net:resetSag()
	self.sag = 0
	self.sagVel = 0
end

return Net
]=] },
	["shared/Physics/Pitch"] = { class = "ModuleScript", source = [=[
--[[
	Pitch — saha geometrisi ve çizgi/kale olayları.

	Saha 105 x 68 m, merkez orijinde:
	  x ∈ [-52.5, +52.5]  (uzunluk)
	  z ∈ [-34, +34]      (genişlik)
	  Ev sahibi takım +x yönüne hücum eder ("home" kalesi +x'te).

	"Top çizgiyi geçti" kuralı gerçek futbolla aynı: topun TAMAMI çizgiyi geçmeli,
	yani merkez çizginin r kadar ötesine ulaşmalı. Bu yüzden kale/taç tespiti
	top yarıçapını hesaba katar.
]]

local Config = require(script.Parent.Parent.Config)
local Vec3 = require(script.Parent.Parent.Core.Vec3)

local Pitch = {}
local P = Config.PITCH

Pitch.halfLength = P.halfLength
Pitch.halfWidth = P.halfWidth
Pitch.goalHalfWidth = P.goalHalfWidth
Pitch.goalHeight = P.goalHeight

-- Saha içinde mi? (çizgiler dahil)
function Pitch.isInside(pos)
	return math.abs(pos.x) <= P.halfLength and math.abs(pos.z) <= P.halfWidth
end

-- Top tamamen saha dışına çıktı mı? (oyun durur: taç/korner/kale vuruşu)
function Pitch.isOutOfPlay(pos, radius)
	local r = radius or 0
	return math.abs(pos.x) > P.halfLength + r or math.abs(pos.z) > P.halfWidth + r
end

--[[
	Kale çizgisi geçildi mi?
	fromPos -> toPos arasında x = ±(halfLength + r) düzlemini kesen noktayı bulur,
	o noktada top kale ağzının içinde ve üst direğin altında mı diye bakar.
	Dönüş: "home" (+x kalesine gol = ev sahibi attı), "away" (-x kalesi), ya da nil.
]]
function Pitch.goalCrossed(fromPos, toPos, radius)
	local r = radius or 0
	local plane = P.halfLength + r

	for _, side in ipairs({ 1, -1 }) do
		local target = side * plane
		local x0, x1 = fromPos.x, toPos.x
		if (x0 - target) * (x1 - target) <= 0 and x1 ~= x0 then
			local t = (target - x0) / (x1 - x0)
			if t >= 0 and t <= 1 then
				local z = fromPos.z + (toPos.z - fromPos.z) * t
				local y = fromPos.y + (toPos.y - fromPos.y) * t
				if math.abs(z) < P.goalHalfWidth - r and y < P.goalHeight and y > -r then
					return side == 1 and "home" or "away"
				end
			end
		end
	end
	return nil
end

-- Top kale ağının içinde mi? (gol sonrası topu tutmak için)
function Pitch.isInsideGoal(pos)
	return math.abs(pos.x) > P.halfLength and math.abs(pos.z) < P.goalHalfWidth and pos.y < P.goalHeight
end

-- Oyun dışı türü. "corner"/"goalKick" ayrımı son dokunan takıma bağlı olduğu için
-- maç mantığında (Adım 5) çözülür; burada sadece çizgi sınıflandırılır.
function Pitch.classifyOutOfPlay(pos, radius)
	local r = radius or 0
	if math.abs(pos.z) > P.halfWidth + r then
		return "touchLine"
	end
	if math.abs(pos.x) > P.halfLength + r then
		return "goalLine"
	end
	return nil
end

--[[ Direk ve üst direk geometrisi: Colliders modülünün kullandığı kapsüller.
	Kale çizgisi x = ±52.5; direkler tam çizgi üzerinde, yükseklik 2.44 m. ]]
function Pitch.buildObstacles(cfg)
	local c = cfg or Config
	local PP = c.PITCH
	local list = {}

	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * PP.halfLength
		-- Yan direkler
		for _, sz in ipairs({ -1, 1 }) do
			list[#list + 1] = {
				kind = "post",
				a = Vec3.new(x, 0, sz * PP.goalHalfWidth),
				b = Vec3.new(x, PP.goalHeight, sz * PP.goalHalfWidth),
				radius = PP.postRadius,
			}
		end
		-- Üst direk
		list[#list + 1] = {
			kind = "crossbar",
			a = Vec3.new(x, PP.goalHeight, -PP.goalHalfWidth),
			b = Vec3.new(x, PP.goalHeight, PP.goalHalfWidth),
			radius = PP.crossbarRadius,
		}
	end

	return list
end

-- Saha üzerinde deterministik başlangıç pozisyonları (Adım 3: diziliş).
function Pitch.kickoffSpot(side)
	return Vec3.new(side * 1.0, Config.BALL.radius, 0)
end

-- Oyuncu pozisyonunun sahanın içine kırpılması (AI taşmasın).
function Pitch.clampPosition(pos, margin)
	local m = margin or 1.0
	return Vec3.new(
		math.max(-P.halfLength + m, math.min(P.halfLength - m, pos.x)),
		pos.y,
		math.max(-P.halfWidth + m, math.min(P.halfWidth - m, pos.z))
	)
end

-- Sahanın önemli noktaları (Adım 3+: diziliş, korner, penaltı).
Pitch.points = {
	center = Vec3.new(0, 0, 0),
	penaltySpotHome = Vec3.new(P.halfLength - P.penaltySpot, 0, 0),
	penaltySpotAway = Vec3.new(-(P.halfLength - P.penaltySpot), 0, 0),
	goalHome = Vec3.new(P.halfLength, 0, 0),
	goalAway = Vec3.new(-P.halfLength, 0, 0),
}

return Pitch
]=] },
	["shared/Player/BallControl"] = { class = "ModuleScript", source = [=[
--[[
	BallControl — oyuncu ile top arasındaki ilişki (Adım 3'ün kalbi).

	Gerçek futbolcu topu "sürekli itmez"; saniyede ~3 kez dokunur, top öne kaçar,
	direnç onu yavaşlatır, oyuncu yetişir. Bu modül o ritmi kurar:

	  * DOKUNUŞ (touch): top ayak mesafesindeyse ve oyuncu koşuyorsa, topu
	    ileri doğru oyuncu hızının biraz üstünde iter. Dokunuşlar arası en az
	    `touchInterval` (0.34 s) vardır.
	  * GÖVDE ÇARPMASI: top oyuncunun içinden geçemez; Body modülü bağıl hızla
	    yansıtır (koşan oyuncu topa hız katar).
	  * KAPATMA (trap): hızlı gelen topu duran oyuncu yumuşatır (ilk dokunuş).
	  * SPRINT CEZASI: hızlı koşarken dokunuş gücü düşer -> top kontrolden kaçar.
	    Bu, "top sürerken yavaşlamak zorundasın" hissini verir.

	Roblox API'si kullanmaz -> testte ve sunucuda aynı kod.
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)
local Body = require(script.Parent.Parent.Physics.Body)

local BallControl = {}
BallControl.__index = BallControl

local min, max = math.min, math.max

function BallControl.new(cfg)
	return setmetatable({
		cfg = cfg,
		lastTouch = -999,
		touches = 0,
		traps = 0,
		kicks = 0,
	}, BallControl)
end

-- Oyuncu durumunu toplar: { pos (y=0), vel, facing, speed }
function BallControl.playerState(positionStuds, velocityStuds, facing, studsPerMeter)
	local s = 1 / studsPerMeter
	return {
		pos = Vec3.new(positionStuds.X * s, 0, positionStuds.Z * s),
		vel = Vec3.new(velocityStuds.X * s, 0, velocityStuds.Z * s),
		facing = facing,
		speed = math.sqrt(velocityStuds.X * velocityStuds.X + velocityStuds.Z * velocityStuds.Z) * s,
	}
end

--[[ Ana güncelleme. Dönüş: "touch" | "trap" | "body" | nil ]]
function BallControl:update(ball, player, now)
	local BC = self.cfg.BALL_CONTROL
	local r = ball.cfg.BALL.radius

	local dx = ball.pos.x - player.pos.x
	local dz = ball.pos.z - player.pos.z
	local dist = math.sqrt(dx * dx + dz * dz)
	local playerSpeed = player.speed or Vec3.lengthHorizontal(player.vel)
	local ballSpeed = Vec3.lengthHorizontal(ball.vel)

	-- 1) Gövde: top oyuncunun içinden geçemez (240 Hz'de sim içinde de çağrılır;
	--    burada yalnızca kare bazlı güvenlik ağı).
	local hit = Body.collide(ball, {
		pos = player.pos,
		vel = player.vel,
		radius = BC.bodyRadius,
		height = BC.bodyHeight,
		restitution = 0.35,
		friction = 0.25,
	})
	if hit then
		self.lastTouch = now
		return "body"
	end

	if dist > BC.dribbleReach or ball.pos.y > 1.1 then
		return nil
	end

	local flatDir
	if dist > 1e-6 then
		flatDir = Vec3.new(dx / dist, 0, dz / dist)
	else
		flatDir = Vec3.fromYaw(player.facing)
	end
	local facingDir = Vec3.fromYaw(player.facing)
	local aheadDot = Vec3.dot(flatDir, facingDir) -- 1: tam önünde, -1: arkasında

	-- 2) Sprint cezası: hızlı koşarken dokunuş "aşırı" olur -> top öne kaçar
	local sprintFactor = math.max(0, math.min(1, (playerSpeed - 4.5) / 3.1))
	local controlFactor = 1 + BC.sprintTouchPenalty * sprintFactor

	-- 3) Dokunuş: top önde, oyuncu hareketli, top oyuncudan yavaş
	if
		playerSpeed > 0.6
		and aheadDot > 0.15
		and ballSpeed < playerSpeed + 3.0
		and (now - self.lastTouch) >= BC.touchInterval
	then
		--[[ Dokunuş hızını tahminle değil ÇÖZEREK buluyoruz:
		     Top, bir sonraki dokunuşa kadar (touchInterval) oyuncuyla AYNI mesafeyi
		     katetmeli ki aradaki boşluk sabit kalsın.
		       v_top*t - 0.5*a*t² = v_oyuncu*t     (a = yuvarlanma direnci)
		     => v_top = v_oyuncu + 0.5*a*t
		     Bu yüzden iyi bir top sürücü neredeyse hiç hız kaybetmez; top ayağından
		     kaçmaz. Sprint cezası bu hedefi büyütür (aşırı vurulan dokunuş). ]]
		local dir = Vec3.unit(Vec3.add(Vec3.scale(facingDir, 1.0), Vec3.scale(flatDir, 0.35)))
		local a = self.cfg.BALL.rollResistance * self.cfg.GRAVITY
		local baseSpeed = playerSpeed + 0.5 * a * BC.touchInterval
		local targetSpeed = (baseSpeed + BC.touchForward) * controlFactor
		if targetSpeed > BC.maxTouchSpeed then
			targetSpeed = BC.maxTouchSpeed
		end

		ball.vel = Vec3.new(dir.x * targetSpeed, 0, dir.z * targetSpeed)
		-- Yuvarlanma spini (kaymadan yuvarlanma koşulu)
		ball.spin = Vec3.new(ball.vel.z / r, ball.spin.y, -ball.vel.x / r)
		ball.mode = "ground"
		ball.pos = Vec3.withY(ball.pos, r)

		self.lastTouch = now
		self.touches = self.touches + 1
		return "touch"
	end

	-- 4) Kapatma (trap): hızlı gelen top, duran oyuncunun ayağında söner
	if ballSpeed > BC.trapSpeedThreshold and dist < BC.trapRadius and playerSpeed < 2.2 then
		local factor = BC.trapFactor + 0.12 * (1 - math.min(1, ballSpeed / 25))
		ball.vel = Vec3.scale(ball.vel, factor)
		ball.spin = Vec3.scale(ball.spin, 0.4)
		self.lastTouch = now
		self.traps = self.traps + 1
		return "trap"
	end

	return nil
end

-- Şut atılabilir mi? (mesafe + yükseklik)
function BallControl:canKick(ball, player)
	local BC = self.cfg.BALL_CONTROL
	local dx = ball.pos.x - player.pos.x
	local dz = ball.pos.z - player.pos.z
	local dist = math.sqrt(dx * dx + dz * dz)
	return dist <= BC.kickReach and ball.pos.y <= BC.kickHeight
end

-- Güç -> hız eşlemesi (0..1 -> minKickSpeed..maxKickSpeed)
function BallControl:speedForCharge(charge)
	local BC = self.cfg.BALL_CONTROL
	local c = math.max(0, math.min(1, charge or 0.5))
	return BC.minKickSpeed + (BC.maxKickSpeed - BC.minKickSpeed) * c
end

-- Şutu uygular.
function BallControl:kick(ball, player, velocity, spin, now)
	ball.vel = velocity
	ball.spin = spin or Vec3.new(0, 0, 0)
	ball.mode = (velocity.y > 1e-6) and "air" or "ground"
	self.lastTouch = now or 0
	self.kicks = self.kicks + 1
	return true
end

return BallControl
]=] },
	["shared/Player/Keeper"] = { class = "ModuleScript", source = [=[
--[[
	Keeper — kaleci AI (tek kale, yarım saha provası için).

	Davranış:
	  * Top uzaktayken kale çizgisi önünde açıyı kapatır (topun z'sini takip eder).
	  * Top kaleye geliyorsa, topun GELECEK konumunu simülasyon kopyasıyla
	    hesaplar (Ball:clone + step) ve o noktaya atlar (dive).
	  * Tepki süresi vardır (reactionTime): anında değil, gecikmeyle okur.
	  * Gövdesi fiziksel engeldir: top ona çarparsa seker (Body modülü).

	Kaleci "topu yakaladı" mı? Top gövdeye çarpıp hızının büyük kısmını
	kaybettiyse ve yönü kaleye gitmiyorsa kurtarış sayılır.
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)

local Keeper = {}
Keeper.__index = Keeper

local abs = math.abs
local min = math.min
local max = math.max

function Keeper.new(cfg, side)
	local K = cfg.KEEPER
	local P = cfg.PITCH
	local lineX = (side or 1) * (P.halfLength - K.lineOffset)
	return setmetatable({
		cfg = cfg,
		side = side or 1,
		pos = Vec3.new(lineX, 0, 0),
		vel = Vec3.new(0, 0, 0),
		lineX = lineX,
		state = "idle", -- idle | track | dive
		reactionTimer = 0,
		diveTimer = 0,
		hits = 0,
		saves = 0,
		conceded = 0,
		-- Gövde tablosu KALICI: Body.collide içindeki hit sayacı birikmeli,
		-- her adımda sıfırlanmamalı (kurtarış sayımı buna bağlı).
		body = {
			pos = Vec3.new(lineX, 0, 0),
			vel = Vec3.new(0, 0, 0),
			radius = K.radius,
			height = K.height,
			restitution = K.restitution,
			friction = 0.35,
			hits = 0,
		},
	}, Keeper)
end

-- Topun kale çizgisine varacağı z konumunu simülasyon kopyasıyla tahmin eder.
function Keeper:predictArrivalZ(ball, maxSeconds)
	local copy = ball:clone()
	-- Tahmin 120 Hz'de yapılır: kaleci için yeterli hassasiyet, yarı maliyet
	local dt = 1 / 120
	local steps = math.floor((maxSeconds or 2.5) / dt)
	local P = self.cfg.PITCH
	for _ = 1, steps do
		copy:step(dt)
		if copy.pos.x * self.side >= P.halfLength - self.cfg.KEEPER.lineOffset then
			return copy.pos.z
		end
		if abs(copy.pos.x) > P.halfLength + P.goalDepth then
			return copy.pos.z
		end
	end
	return copy.pos.z
end

--[[ Bir adım. Dönüş: çarpışma için gövde tanımı. ]]
function Keeper:step(ball, dt)
	local K = self.cfg.KEEPER
	local P = self.cfg.PITCH

	-- Top kaleye mi geliyor?
	local towardGoal = ball.vel.x * self.side > 2.5
	local distanceToLine = (self.side * P.halfLength) - ball.pos.x

	local targetZ = 0
	local wantDive = false

	if towardGoal and distanceToLine > 0 and distanceToLine < 18 then
		self.reactionTimer = self.reactionTimer + dt
		if self.reactionTimer >= K.reactionTime then
			local predicted = self:predictArrivalZ(ball, 2.5)
			-- Kaleci hatası: tepki mesafesiyle artan küçük sapma (deterministik)
			targetZ = max(-K.reachZ, min(K.reachZ, predicted))
			wantDive = true
		else
			targetZ = max(-K.reachZ, min(K.reachZ, ball.pos.z))
		end
	else
		self.reactionTimer = 0
		-- Açıyı kapat: top z'sinin %60'ı
		targetZ = max(-K.reachZ, min(K.reachZ, ball.pos.z * 0.6))
	end

	-- Hedefe doğru hareket (ivme sınırlı)
	local speedLimit = wantDive and K.diveSpeed or K.maxSpeed
	local accel = wantDive and K.diveAccel or 12
	local dz = targetZ - self.pos.z
	local desiredVel = 0
	if abs(dz) > 0.04 then
		desiredVel = (dz > 0 and 1 or -1) * speedLimit
	end
	local dv = desiredVel - self.vel.z
	local maxDv = accel * dt
	if abs(dv) > maxDv then
		dv = (dv > 0 and 1 or -1) * maxDv
	end
	self.vel = Vec3.new(0, 0, self.vel.z + dv)
	self.pos = Vec3.new(self.lineX, 0, self.pos.z + self.vel.z * dt)

	if self.pos.z < -K.reachZ then
		self.pos = Vec3.new(self.lineX, 0, -K.reachZ)
		self.vel = Vec3.new(0, 0, 0)
	elseif self.pos.z > K.reachZ then
		self.pos = Vec3.new(self.lineX, 0, K.reachZ)
		self.vel = Vec3.new(0, 0, 0)
	end

	if wantDive then
		self.state = "dive"
		self.diveTimer = self.diveTimer + dt
	else
		self.state = abs(self.vel.z) > 0.5 and "track" or "idle"
		self.diveTimer = 0
	end

	-- Dalış sırasında gövde alçalır (daha geniş ama daha kısa)
	local height = K.height
	if wantDive then
		height = K.height * (1 - 0.35 * min(1, self.diveTimer / 0.45))
	end

	local body = self.body
	body.pos = Vec3.new(self.pos.x, 0, self.pos.z)
	body.vel = Vec3.new(0, 0, self.vel.z)
	body.radius = K.radius
	body.height = height

	return body
end

-- Top gövdeye çarptıktan sonra kurtarış mı, gol mü? (maç mantığı için)
function Keeper:evaluateIncoming(ball)
	if ball.vel.x * self.side > 3 then
		return "incoming"
	end
	return "safe"
end

return Keeper
]=] },
	["shared/Player/Locomotion"] = { class = "ModuleScript", source = [=[
--[[
	Locomotion — oyuncu hareket modeli.

	Roblox'da oyuncuları Humanoid ile yürütmek "gerçekçi" değildir: Humanoid anında
	yön değiştirir, ivme yoktur, yorgunluk yoktur. Burada gerçek spor bilimine yakın
	bir model var:

	  * Hızlanma sınırlı (6.5 m/s²): 0-27 km/h ~1.2 s sürer.
	  * Yavaşlama daha güçlü (9 m/s²).
	  * Dönüş hızı sınırlı: gövde anında dönmez (7 rad/s ≈ 400°/s).
	  * Yorgunluk: sprint atarken stamina düşer, hız tavanı %72'ye kadar iner.
	  * Yön vektörü verilir, gövde açısı ayrı izlenir (animasyon için gerekli).

	Model kara kutu değil: durum (pos, vel, facing, stamina) açıkça tutulur, böylece
	hem sunucu hem istemci aynı girdiyle aynı sonucu üretir (deterministik).
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)

local Locomotion = {}
Locomotion.__index = Locomotion

local abs = math.abs
local min = math.min
local max = math.max

-- Açıyı (-pi, pi] aralığına indirger.
local function wrapAngle(a)
	while a > math.pi do
		a = a - 2 * math.pi
	end
	while a <= -math.pi do
		a = a + 2 * math.pi
	end
	return a
end

Locomotion.wrapAngle = wrapAngle

function Locomotion.new(cfg, position, facing)
	return setmetatable({
		cfg = cfg,
		pos = position or Vec3.new(0, 0, 0),
		vel = Vec3.new(0, 0, 0),
		facing = facing or 0,
		stamina = 1,
		sprinting = false,
	}, Locomotion)
end

function Locomotion:speed()
	return Vec3.lengthHorizontal(self.vel)
end

-- stamina 0..1 -> hız çarpanı
function Locomotion:speedFactor()
	local p = self.cfg.PLAYER
	return p.staminaMinFactor + (1 - p.staminaMinFactor) * self.stamina
end

function Locomotion:maxSpeedNow(sprinting)
	local p = self.cfg.PLAYER
	local m = p.maxSpeed * self:speedFactor()
	if sprinting then
		m = m * p.sprintMultiplier
	end
	return m
end

--[[
	Bir adım ilerlet.
	desiredDir : yön vektörü (uzunluğu önemsiz; yatay bileşen kullanılır)
	sprinting  : bool (verilmezse hız > %55 ise sprint sayılır)
]]
function Locomotion:step(desiredDir, dt, sprinting)
	local p = self.cfg.PLAYER

	local dir = Vec3.horizontal(desiredDir)
	local dirLen = Vec3.length(dir)
	if dirLen > 1e-6 then
		dir = Vec3.scale(dir, 1 / dirLen)
	else
		dir = Vec3.ZERO
	end

	local wantsMove = dirLen > 1e-6
	if sprinting == nil then
		sprinting = wantsMove and self:speed() > p.maxSpeed * 0.55
	end
	self.sprinting = wantsMove and sprinting

	local maxSpeed = self:maxSpeedNow(sprinting)
	local desiredVel = Vec3.scale(dir, maxSpeed)
	local dv = Vec3.sub(desiredVel, self.vel)
	local dvLen = Vec3.length(dv)

	-- Hızlanıyor muyuz, yavaşlıyor muyuz? Hedef hız mevcut hızdan büyükse ivme,
	-- değilse daha güçlü olan yavaşlama kullanılır.
	local accelerating = Vec3.lengthSq(desiredVel) > Vec3.lengthSq(self.vel)
	local rate = accelerating and p.acceleration or p.deceleration
	local maxDv = rate * dt
	if dvLen > maxDv and dvLen > 1e-9 then
		dv = Vec3.scale(dv, maxDv / dvLen)
	end

	self.vel = Vec3.add(self.vel, dv)
	self.pos = Vec3.add(self.pos, Vec3.scale(self.vel, dt))

	-- Gövde yönü: hıza doğru sınırlı hızda döner.
	local speed = Vec3.lengthHorizontal(self.vel)
	if speed > 0.25 then
		local target = Vec3.yaw(self.vel)
		local diff = wrapAngle(target - self.facing)
		local maxTurn = p.turnRate * dt
		self.facing = wrapAngle(self.facing + max(-maxTurn, min(maxTurn, diff)))
	elseif wantsMove then
		-- Duruyorken bile hedef yöne dönmeye başla (ayak yerleşimi/animasyon).
		local target = Vec3.yaw(dir)
		local diff = wrapAngle(target - self.facing)
		local maxTurn = p.turnRate * dt
		self.facing = wrapAngle(self.facing + max(-maxTurn, min(maxTurn, diff)))
	end

	-- Yorgunluk
	local effort = speed / p.maxSpeed
	if effort > 0.55 then
		local intensity = (effort - 0.55) / 0.45
		self.stamina = max(0, self.stamina - p.staminaDrainSprint * intensity * dt)
	else
		self.stamina = min(1, self.stamina + p.staminaRegen * dt)
	end

	return self
end

-- Topa ulaşmak için gereken süre tahmini (AI ve kaleci için, Adım 6).
function Locomotion:timeToReach(targetPos)
	local dist = Vec3.distanceHorizontal(self.pos, targetPos)
	local p = self.cfg.PLAYER
	local v = self:speed()
	if dist <= 0 then
		return 0
	end
	-- Sabit ivmeyle: d = v*t + 0.5*a*t²  ->  t çözümü
	local a = p.acceleration
	local disc = v * v + 2 * a * dist
	local t = (-v + math.sqrt(disc)) / a
	local tAtMax = (self:maxSpeedNow(true) - v) / a
	if t > tAtMax then
		local covered = v * tAtMax + 0.5 * a * tAtMax * tAtMax
		t = tAtMax + (dist - covered) / self:maxSpeedNow(true)
	end
	return t
end

return Locomotion
]=] },
	["shared/Sim"] = { class = "ModuleScript", source = [=[
--[[
	Sim — sabit adımlı simülasyon çekirdeği (fixed timestep).

	Neden sabit adım?
	  Değişken dt ile çalışan fizik, kare hızına göre farklı sonuç üretir: 30 FPS'te
	  oynayan oyuncunun şutu 144 FPS'tekinden farklı yere gider. Rekabetçi bir
	  futbol oyununda bu kabul edilemez. Bu yüzden:

	    * Simülasyon her zaman 1/240 s'lik adımlarla ilerler.
	    * Kare süresi bir "akümülatörde" birikir, yeterince birikince tick çalışır.
	    * Kalan artık zaman bir sonraki kareye taşınır (görsel interpolasyon için).

	Determinizm garantisi: aynı tohum + aynı tick dizisi = aynı sonuç (bit-bit).
]]

local Config = require(script.Parent.Config)
local Vec3 = require(script.Parent.Core.Vec3)
local Rng = require(script.Parent.Core.Rng)
local Ball = require(script.Parent.Physics.Ball)
local Pitch = require(script.Parent.Physics.Pitch)
local Colliders = require(script.Parent.Physics.Colliders)
local Body = require(script.Parent.Physics.Body)

local Sim = {}
Sim.__index = Sim

function Sim.new(opts)
	opts = opts or {}
	local cfg = opts.config or Config
	local self = setmetatable({
		cfg = cfg,
		rng = Rng.new(opts.seed or 1),
		ball = Ball.new(cfg, Vec3.new(0, cfg.BALL.radius, 0)),
		obstacles = Pitch.buildObstacles(cfg),
		bodies = {}, -- hareketli gövdeler (oyuncu/kaleci) — sunucu her karede günceller
		nets = {}, -- file/ağ fizikleri
		ticks = 0, -- islenen sabit adim sayisi (metot adiyla cakismasin)
		time = 0,
		accumulator = 0,
		lastGoal = nil,
		lastSubsteps = 0,
	}, Sim)
	return self
end

-- Tek deterministik adım.
function Sim:tick()
	local dt = self.cfg.FIXED_DT
	local prev = self.ball.pos

	self.ball:step(dt)

	-- Direk / üst direk çarpışması (kale tespitinden ÖNCE: direğe çarpan top gol değil)
	Colliders.resolve(self.ball, self.obstacles, prev)

	-- Hareketli gövdeler (oyuncu bacakları, kaleci) — 240 Hz'de, adım içi hareket
	-- doğrusu ile çarpıştırılır ki hızlı şut oyuncunun içinden geçmesin.
	for i = 1, #self.bodies do
		Body.collide(self.ball, self.bodies[i])
	end

	-- File: top kaleye girdiğinde ağ onu yutar (hız sönümü + esneme)
	for i = 1, #self.nets do
		self.nets[i]:stepBall(self.ball, dt)
	end

	-- Kale tespiti (top bu adımda kale çizgisini geçtiyse)
	local side = Pitch.goalCrossed(prev, self.ball.pos, self.cfg.BALL.radius)
	if side then
		self.lastGoal = { side = side, tick = self.ticks + 1, pos = self.ball.pos }
	end

	self.ticks = self.ticks + 1
	self.time = self.ticks * dt
end

function Sim:advanceTicks(n)
	for _ = 1, n do
		self:tick()
	end
	return self
end

-- Saniye cinsinden ilerlet (testlerde ve sunucu otoritesinde kullanışlı).
function Sim:advance(seconds)
	local n = math.floor(seconds * self.cfg.SIM_HZ + 0.5)
	return self:advanceTicks(n)
end

--[[
	Kare bazlı güncelleme: frameDt kadar gerçek zamanı simüle eder.
	Dönüş: bu karede çalışan tick sayısı.
	Spiral of death koruması: tek karede en fazla MAX_FRAME_DT işlenir.
]]
function Sim:update(frameDt)
	local cfg = self.cfg
	if frameDt < 0 then
		frameDt = 0
	end
	if frameDt > cfg.MAX_FRAME_DT then
		frameDt = cfg.MAX_FRAME_DT
	end

	self.accumulator = self.accumulator + frameDt
	local steps = 0
	while self.accumulator >= cfg.FIXED_DT and steps < cfg.MAX_SUBSTEPS do
		self:tick()
		self.accumulator = self.accumulator - cfg.FIXED_DT
		steps = steps + 1
	end
	-- Çok geride kaldıysak artığı at (yavaş cihazlarda birikmesin)
	if steps >= cfg.MAX_SUBSTEPS then
		self.accumulator = 0
	end
	self.lastSubsteps = steps
	return steps
end

-- Görsel interpolasyon için ara durum (0 = son tick, 1 = bir sonraki tick).
function Sim:interpolatedBall()
	local alpha = self.accumulator / self.cfg.FIXED_DT
	local b = self.ball
	local pred = b:clone()
	pred:step(self.cfg.FIXED_DT)
	return Vec3.lerp(b.pos, pred.pos, alpha)
end

return Sim
]=] },
	["shared/World/SceneBuilder"] = { class = "ModuleScript", source = [=[
--[[
	SceneBuilder — Roblox sahnesini kodla kurar (Adım 2 + Adım 3).

	Adım 3 kapsamı (kullanıcı isteği): YARIM SAHA, 1 kale, 1 kaleci, 1 şutçu.
	`SceneBuilder.build({ half = true })` yarım sahayı kurar; `half = false` tam
	sahayı (ileride 11v11 için) kurar.

	Tüm ölçüler metreden stud'a çevrilir (Config.STUDS_PER_METER): gerçek bir saha
	105 m = 375 stud. Roblox karakteri ~5.5 stud olduğu için ölçek gerçekçi kalır.

	Top dışındaki hiçbir parça fizik motoruna bırakılmaz; hepsi Anchored.
]]

local Config = require(script.Parent.Parent.Config)

local SceneBuilder = {}

local S = Config.STUDS_PER_METER
local P = Config.PITCH
local LINE = 0.12 -- çizgi kalınlığı (metre)
local LINE_Y = 0.03 -- çim üstünden yükseklik (stud)

-- Lua 5.3: math.atan(y, x) | Luau: math.atan2(y, x)
local atan2 = math.atan2 or math.atan

local function makePart(parent, name, sizeStuds, cframe, color, material, opts)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = sizeStuds
	p.CFrame = cframe
	p.Color = color or Color3.fromRGB(240, 244, 248)
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	if opts then
		if opts.shape then
			p.Shape = opts.shape
		end
		if opts.transparency then
			p.Transparency = opts.transparency
		end
		if opts.collide ~= nil then
			p.CanCollide = opts.collide
		end
		if opts.castShadow ~= nil then
			p.CastShadow = opts.castShadow
		end
	end
	p.Parent = parent
	return p
end

-- Metre -> stud (yükseklik: y=0 çim yüzeyi)
local function v3(x, y, z)
	return Vector3.new(x * S, y * S, z * S)
end

local function drawLine(parent, name, x1, z1, x2, z2)
	local cx, cz = (x1 + x2) / 2, (z1 + z2) / 2
	local dx, dz = math.abs(x2 - x1), math.abs(z2 - z1)
	local size = Vector3.new(math.max(dx, LINE) * S, 0.04, math.max(dz, LINE) * S)
	return makePart(
		parent,
		name,
		size,
		CFrame.new(v3(cx, LINE_Y / S, cz)),
		Color3.fromRGB(246, 250, 252),
		Enum.Material.SmoothPlastic,
		{ castShadow = false }
	)
end

-- Yay çizimi (orta yuvarlak / korner): küçük segmentlerden
local function drawArc(parent, name, cx, cz, radius, startAngle, endAngle, segments)
	segments = segments or 24
	for i = 1, segments do
		local a1 = startAngle + (endAngle - startAngle) * ((i - 1) / segments)
		local a2 = startAngle + (endAngle - startAngle) * (i / segments)
		local x1, z1 = cx + math.cos(a1) * radius, cz + math.sin(a1) * radius
		local x2, z2 = cx + math.cos(a2) * radius, cz + math.sin(a2) * radius
		local seg = drawLine(parent, name .. "_" .. tostring(i), x1, z1, x2, z2)
		local mid = Vector3.new((x1 + x2) / 2 * S, LINE_Y, (z1 + z2) / 2 * S)
		local len = math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2) * S
		local angle = atan2(z2 - z1, x2 - x1)
		seg.CFrame = CFrame.new(mid) * CFrame.Angles(0, -angle, 0)
		seg.Size = Vector3.new(math.max(len, LINE * S), 0.04, LINE * S)
	end
end

local function buildSurface(root, opts)
	local folder = Instance.new("Folder")
	folder.Name = "Surface"
	folder.Parent = root

	-- Yarım sahada çim x ∈ [0, halfLength]; tam sahada [-halfLength, halfLength]
	local x0 = opts.half and 0 or -P.halfLength
	local x1 = P.halfLength
	local width = x1 - x0
	local centerX = (x0 + x1) / 2

	local grass = makePart(
		folder,
		"Grass",
		Vector3.new(width * S, 2, P.width * S),
		CFrame.new(centerX * S, -0.98, 0), -- üst yüz y=0.02: varsayılan Baseplate ile z-fighting olmaz
		Color3.fromRGB(38, 104, 56),
		Enum.Material.Grass,
		{ collide = true }
	)
	grass.CastShadow = false

	local stripes = opts.half and 6 or 10
	for i = 0, stripes - 1 do
		local w = width / stripes
		local x = x0 + w * (i + 0.5)
		makePart(
			folder,
			"Stripe" .. tostring(i),
			Vector3.new(w * S, 0.02, P.width * S),
			CFrame.new(v3(x, 0.001, 0)),
			i % 2 == 0 and Color3.fromRGB(44, 116, 62) or Color3.fromRGB(40, 108, 58),
			Enum.Material.Grass,
			{ castShadow = false }
		)
	end

	return grass
end

local function buildLines(root, opts)
	local folder = Instance.new("Folder")
	folder.Name = "Lines"
	folder.Parent = root

	local HL, HW = P.halfLength, P.halfWidth
	local x0 = opts.half and 0 or -HL

	-- Yan çizgiler
	drawLine(folder, "TouchlineNorth", x0, -HW, HL, -HW)
	drawLine(folder, "TouchlineSouth", x0, HW, HL, HW)
	-- Kale çizgisi (hücum edilen kale)
	drawLine(folder, "GoalLineEast", HL, -HW, HL, HW)
	-- Orta çizgi / arka çizgi
	if opts.half then
		drawLine(folder, "HalfwayLine", 0, -HW, 0, HW)
	else
		drawLine(folder, "GoalLineWest", -HL, -HW, -HL, HW)
		drawLine(folder, "HalfwayLine", 0, -HW, 0, HW)
	end

	-- Orta yuvarlak: yarım sahada yalnızca saha içindeki yay
	if opts.half then
		drawArc(folder, "CenterCircle", 0, 0, P.centerCircleRadius, -math.pi / 2, math.pi / 2, 24)
	else
		drawArc(folder, "CenterCircle", 0, 0, P.centerCircleRadius, 0, math.pi * 2, 40)
	end
	makePart(
		folder,
		"CenterSpot",
		Vector3.new(0.24 * S, 0.05, 0.24 * S),
		CFrame.new(v3(0, LINE_Y / S, 0)),
		Color3.fromRGB(246, 250, 252),
		nil,
		{ shape = Enum.PartType.Cylinder, castShadow = false }
	)

	-- Ceza sahası / kale sahası / penaltı noktası
	local sides = opts.half and { 1 } or { -1, 1 }
	for _, side in ipairs(sides) do
		local gl = side * HL
		local paX = gl - side * P.penaltyAreaLength
		local gaX = gl - side * P.goalAreaLength

		drawLine(folder, "PenaltyAreaLine", paX, -P.penaltyAreaHalfWidth, paX, P.penaltyAreaHalfWidth)
		drawLine(folder, "PenaltyAreaSide", gl, -P.penaltyAreaHalfWidth, paX, -P.penaltyAreaHalfWidth)
		drawLine(folder, "PenaltyAreaSide", gl, P.penaltyAreaHalfWidth, paX, P.penaltyAreaHalfWidth)

		drawLine(folder, "GoalAreaLine", gaX, -P.goalAreaHalfWidth, gaX, P.goalAreaHalfWidth)
		drawLine(folder, "GoalAreaSide", gl, -P.goalAreaHalfWidth, gaX, -P.goalAreaHalfWidth)
		drawLine(folder, "GoalAreaSide", gl, P.goalAreaHalfWidth, gaX, P.goalAreaHalfWidth)

		makePart(
			folder,
			"PenaltySpot",
			Vector3.new(0.22 * S, 0.05, 0.22 * S),
			CFrame.new(v3(gl - side * P.penaltySpot, LINE_Y / S, 0)),
			Color3.fromRGB(246, 250, 252),
			nil,
			{ shape = Enum.PartType.Cylinder, castShadow = false }
		)
	end
end

local function buildGoal(parent, side)
	local frameColor = Color3.fromRGB(248, 250, 252)
	local postDia = P.postRadius * 2
	local barDia = P.crossbarRadius * 2
	local gl = side * P.halfLength
	local tag = side > 0 and "East" or "West"

	local goalFolder = Instance.new("Folder")
	goalFolder.Name = "Goal" .. tag
	goalFolder.Parent = parent

	-- Yan direkler (silindir ekseni X'tir; dikey yapmak için Z'de 90°)
	for _, sz in ipairs({ -1, 1 }) do
		makePart(
			goalFolder,
			"Post",
			Vector3.new(P.goalHeight * S, postDia * S, postDia * S),
			CFrame.new(v3(gl, P.goalHeight / 2, sz * P.goalHalfWidth)) * CFrame.Angles(0, 0, math.rad(90)),
			frameColor,
			Enum.Material.Metal,
			{ shape = Enum.PartType.Cylinder }
		)
	end

	-- Üst direk (ekseni Z'ye çevir)
	makePart(
		goalFolder,
		"Crossbar",
		Vector3.new(P.goalHalfWidth * 2 * S, barDia * S, barDia * S),
		CFrame.new(v3(gl, P.goalHeight, 0)) * CFrame.Angles(0, math.rad(90), 0),
		frameColor,
		Enum.Material.Metal,
		{ shape = Enum.PartType.Cylinder }
	)

	-- Ağ: arka, iki yan, üst
	local netColor = Color3.fromRGB(230, 238, 244)
	local netOpts = { transparency = 0.45, castShadow = false }
	local backX = gl + side * P.goalDepth

	local backNet = makePart(
		goalFolder,
		"NetBack",
		Vector3.new(0.05 * S, P.goalHeight * S, P.goalHalfWidth * 2 * S),
		CFrame.new(backX * S, (P.goalHeight / 2) * S, 0),
		netColor,
		Enum.Material.Fabric,
		netOpts
	)

	for _, sz in ipairs({ -1, 1 }) do
		makePart(
			goalFolder,
			"NetSide",
			Vector3.new(P.goalDepth * S, P.goalHeight * S, 0.05 * S),
			CFrame.new(((gl + backX) / 2) * S, (P.goalHeight / 2) * S, sz * P.goalHalfWidth * S),
			netColor,
			Enum.Material.Fabric,
			netOpts
		)
	end

	makePart(
		goalFolder,
		"NetTop",
		Vector3.new(P.goalDepth * S, 0.05 * S, P.goalHalfWidth * 2 * S),
		CFrame.new(((gl + backX) / 2) * S, P.goalHeight * S, 0),
		netColor,
		Enum.Material.Fabric,
		netOpts
	)

	return goalFolder, backNet, backX
end

local function buildBall()
	local ball = makePart(
		workspace,
		"MatchBall",
		Vector3.new(Config.BALL.radius * 2 * S, Config.BALL.radius * 2 * S, Config.BALL.radius * 2 * S),
		CFrame.new(0, Config.BALL.radius * S, 0),
		Color3.fromRGB(248, 250, 252),
		Enum.Material.SmoothPlastic,
		{ shape = Enum.PartType.Ball }
	)
	ball.CastShadow = true
	return ball
end

--[[ Kaleci görseli: basit blok gövde + kafa + iki kol.
	Sunucu her karede bu modeli kaleci AI'sinin konumuna taşır. ]]
local function buildKeeper(root, side)
	local K = Config.KEEPER
	local folder = Instance.new("Folder")
	folder.Name = "Goalkeeper"
	folder.Parent = root

	local kit = Color3.fromRGB(250, 214, 60)
	local skin = Color3.fromRGB(232, 190, 160)
	local x = side * (P.halfLength - K.lineOffset)

	local body = makePart(
		folder,
		"Body",
		Vector3.new(0.55 * S, 1.15 * S, 0.32 * S),
		CFrame.new(v3(x, 0.85, 0)),
		kit,
		Enum.Material.SmoothPlastic
	)
	local head = makePart(
		folder,
		"Head",
		Vector3.new(0.30 * S, 0.30 * S, 0.30 * S),
		CFrame.new(v3(x, 1.60, 0)),
		skin,
		Enum.Material.SmoothPlastic,
		{ shape = Enum.PartType.Ball }
	)
	local armL = makePart(
		folder,
		"ArmL",
		Vector3.new(0.12 * S, 0.70 * S, 0.12 * S),
		CFrame.new(v3(x, 1.10, -0.36)),
		kit,
		Enum.Material.SmoothPlastic
	)
	local armR = makePart(
		folder,
		"ArmR",
		Vector3.new(0.12 * S, 0.70 * S, 0.12 * S),
		CFrame.new(v3(x, 1.10, 0.36)),
		kit,
		Enum.Material.SmoothPlastic
	)

	return { folder = folder, body = body, head = head, armL = armL, armR = armR, x = x }
end

local function setupLighting()
	local Lighting = game:GetService("Lighting")
	pcall(function()
		Lighting.ClockTime = 15.5
		Lighting.Brightness = 2.3
		Lighting.Ambient = Color3.fromRGB(72, 82, 92)
		Lighting.OutdoorAmbient = Color3.fromRGB(126, 136, 146)
		Lighting.EnvironmentDiffuseScale = 0.45
		Lighting.EnvironmentSpecularScale = 0.3
		Lighting.GlobalShadows = true
		Lighting.ExposureCompensation = 0.1
	end)

	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atm = Instance.new("Atmosphere")
		atm.Density = 0.32
		atm.Haze = 1.1
		atm.Glare = 0.1
		atm.Color = Color3.fromRGB(199, 212, 224)
		atm.Parent = Lighting
	end
end

local function buildSpawn(root, x)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PitchSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(x * S, 0.5, 0)
	spawn.Color = Color3.fromRGB(60, 120, 200)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = root
	return spawn
end

--[[ Sahneyi kurar. opts = { half = true } -> yarım saha, tek kale (Adım 3).
	Dönüş: { root, ball, keeper, backNet, ballStart, half, goalSide } ]]
function SceneBuilder.build(opts)
	opts = opts or {}
	local half = opts.half ~= false
	local goalSide = opts.goalSide or 1

	local existing = workspace:FindFirstChild("FootballPitch")
	if existing then
		existing:Destroy()
	end
	local oldBall = workspace:FindFirstChild("MatchBall")
	if oldBall then
		oldBall:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "FootballPitch"
	root.Parent = workspace

	buildSurface(root, { half = half })

	buildLines(root, { half = half })

	local goalsFolder = Instance.new("Folder")
	goalsFolder.Name = "Goals"
	goalsFolder.Parent = root

	local backNet, backX
	local _, netPart, netX = buildGoal(goalsFolder, goalSide)
	backNet, backX = netPart, netX

	if not half then
		buildGoal(goalsFolder, -goalSide)
	end

	local ball = buildBall()
	local keeper = buildKeeper(root, goalSide)
	setupLighting()

	-- Doğma noktası: yarım sahada arka çizginin gerisinde
	local spawnX = half and 3 or 0
	buildSpawn(root, spawnX)

	local ballStart = half and Vector3.new((P.halfLength * 0.40) * S, Config.BALL.radius * S, 0)
		or Vector3.new(0, Config.BALL.radius * S, 0)
	ball.CFrame = CFrame.new(ballStart)

	return {
		root = root,
		ball = ball,
		keeper = keeper,
		backNet = backNet,
		backX = backX,
		ballStart = ballStart,
		half = half,
		goalSide = goalSide,
	}
end

-- Topu başlangıç noktasına alır
function SceneBuilder.resetBallPosition(positionStuds)
	local ball = workspace:FindFirstChild("MatchBall")
	if ball then
		ball.CFrame = CFrame.new(positionStuds or Vector3.new(0, Config.BALL.radius * S, 0))
	end
end

--[[ Kaleci modelini AI durumuna göre taşır (sunucu çağırır). ]]
function SceneBuilder.updateKeeperModel(keeperModel, keeperState, studsPerMeter)
	if not keeperModel or not keeperState then
		return
	end
	local s = studsPerMeter or S
	local pos = keeperState.pos
	local x, z = pos.x * s, pos.z * s
	local diving = keeperState.state == "dive"
	local lean = 0
	if diving then
		lean = keeperState.vel.z / Config.KEEPER.diveSpeed
		lean = math.max(-1, math.min(1, lean))
	end

	if keeperModel.body then
		keeperModel.body.CFrame = CFrame.new(x, 0.85 * s, z) * CFrame.Angles(0, 0, lean * 0.5)
	end
	if keeperModel.head then
		keeperModel.head.CFrame = CFrame.new(x, (1.60 - math.abs(lean) * 0.25) * s, z)
	end
	if keeperModel.armL then
		keeperModel.armL.CFrame = CFrame.new(x, 1.10 * s, z - 0.36 * s) * CFrame.Angles(lean * 0.9, 0, 0)
	end
	if keeperModel.armR then
		keeperModel.armR.CFrame = CFrame.new(x, 1.10 * s, z + 0.36 * s) * CFrame.Angles(-lean * 0.9, 0, 0)
	end
end

return SceneBuilder
]=] },
}

--[[
	KURULUM MANTIĞI (tek kurulum dosyasının gövdesi)

	Yukarıdaki SOURCES tablosunu okur, oyuna yazar, sahneyi kurar.
	Roblox Studio'nun Command Bar'ında çalıştırılmalıdır (Script.Source yazma
	yetkisi orada vardır).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")

local ROOTS = {
	shared = ReplicatedStorage,
	server = ServerScriptService,
	client = StarterPlayerScripts,
}

local ROOT_FOLDER_NAMES = {
	shared = "Shared",
	server = "Server",
	client = "Client",
}

local function ensureFolder(parent, name)
	if not parent then
		return nil
	end
	local existing = parent:FindFirstChild(name)
	if existing and not existing:IsA("Folder") then
		existing:Destroy()
		existing = nil
	end
	if not existing then
		existing = Instance.new("Folder")
		existing.Name = name
		existing.Parent = parent
	end
	return existing
end

local function ensureScript(parent, name, className)
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName ~= className then
		existing:Destroy()
		existing = nil
	end
	if not existing then
		existing = Instance.new(className)
		existing.Name = name
		existing.Parent = parent
	end
	return existing
end

local function splitPath(p)
	local parts = {}
	for part in string.gmatch(p, "[^/]+") do
		table.insert(parts, part)
	end
	return parts
end

-- 1) Scriptleri yaz ---------------------------------------------------------
local keys = {}
for key in pairs(SOURCES) do
	table.insert(keys, key)
end
table.sort(keys)

local written, sourceFailed = 0, 0

for _, key in ipairs(keys) do
	local entry = SOURCES[key]
	local rootName, rest = string.match(key, "^(%w+)/(.+)$")
	local root = rootName and ROOTS[rootName]

	if root and rest then
		local folderName = ROOT_FOLDER_NAMES[rootName]
		local parent = folderName and ensureFolder(root, folderName) or root

		local parts = splitPath(rest)
		for i = 1, #parts - 1 do
			parent = ensureFolder(parent, parts[i])
		end

		local name = parts[#parts]
		if parent and name then
			local inst = ensureScript(parent, name, entry.class)
			local ok = pcall(function()
				inst.Source = entry.source
			end)
			if ok then
				written = written + 1
			else
				sourceFailed = sourceFailed + 1
			end
		end
	else
		warn("[FootballSim] Taninmayan modul yolu: " .. tostring(key))
	end
end

-- 2) Sahneyi kur ------------------------------------------------------------
local sceneOk, sceneErr = pcall(function()
	local SceneBuilder = require(ReplicatedStorage.Shared.World.SceneBuilder)
	SceneBuilder.build()
end)

-- 3) Rapor ------------------------------------------------------------------
local msg = {}
table.insert(msg, "==================================================")
table.insert(msg, "  FootballSim kurulumu")
table.insert(msg, "==================================================")
table.insert(msg, string.format("  Scriptler : %d yazildi, %d basarisiz", written, sourceFailed))
table.insert(msg, "  Sahne     : " .. (sceneOk and "kuruldu (cim, cizgiler, kaleler, ag, top, isik)" or ("HATA - " .. tostring(sceneErr))))
table.insert(msg, "")
table.insert(msg, "  Simdi Play'e bas. SPACE ile sut cekebilirsin.")
table.insert(msg, "  Top fizigi: 240 Hz, kendi motorumuz (Roblox fizigi kullanilmaz).")
table.insert(msg, "==================================================")
print(table.concat(msg, "\n"))

if sourceFailed > 0 then
	warn("[FootballSim] " .. tostring(sourceFailed) .. " script yazilamadi. Command Bar yerine")
	warn("bir Script icinden calistirdiysaniz Source yazma yetkisi yoktur;")
	warn("Command Bar'da calistirin ya da Rojo kullanin (rojo serve).")
end
