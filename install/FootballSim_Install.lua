--[[
	FootballSim — TEK KURULUM DOSYASI (otomatik üretilir, elle düzenlemeyin).

	KULLANIM
	  1) Roblox Studio'da oyunu aç.
	  2) View > Command Bar (komut çubuğu) aç.
	  3) Bu dosyanın TAMAMINI kopyalayıp komut çubuğuna yapıştır, Enter.
	  4) Sahne kurulur, scriptler yerleşir. Play'e bas: SPACE ile şut çek.

	Yeniden üretmek için: npm run install:build
	Kaynak: src/ (13 modül)
]]

local SOURCES = {
	["client/BallView"] = { class = "LocalScript", source = [=[
--[[
	BallView — istemci görselleştirme (Adım 2).

	Sunucu topun gerçek konumunu ~ağ hızında gönderir (Roblox anchored parça
	replikasyonu). Bu script:

	  1) Sunucudan gelen topu lokal olarak gizler,
	  2) Kendi yumuşatılmış kopyasını çizer (60-144 FPS akıcılık),
	  3) İz (Trail) efekti ekler,
	  4) Yayın kamerasını topa doğru kaydırır,
	  5) SPACE ile şut isteği gönderir.

	Neden sunucu topunu gizliyoruz? Replikasyon 20-30 Hz gelir; 27 m/s'lik bir şut
	bu hızda 1.3 m sıçrayarak görünür. İstemci, hedefe üstel yaklaşma + hız tahmini
	ile aradaki hareketi doldurur. (Adım 7'de gerçek gecikme telafisi + prediction.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Yapılandırma (sunucudaki ile aynı olmalı; Config modülünde tutuluyor)
local Config
do
	local Shared = ReplicatedStorage:WaitForChild("Shared", 20)
	if Shared then
		local ok, mod = pcall(require, Shared:WaitForChild("Config", 10))
		if ok and mod then
			Config = mod
		end
	end
end
local S = Config and Config.STUDS_PER_METER or 3.5714
local R = Config and Config.BALL.radius or 0.11

local serverBall = Workspace:WaitForChild("MatchBall", 30)
if not serverBall then
	return
end
serverBall.LocalTransparencyModifier = 1

-- Lokal görsel top
local visual = serverBall:Clone()
visual.Name = "MatchBallVisual"
visual.Anchored = true
visual.CanCollide = false
visual.CanQuery = false
visual.LocalTransparencyModifier = 0
visual.Transparency = 0
visual.Parent = Workspace

-- İz efekti
local trail = Instance.new("Trail")
trail.Attachment0 = Instance.new("Attachment")
trail.Attachment1 = Instance.new("Attachment")
trail.Attachment0.Parent = visual
trail.Attachment1.Parent = visual
trail.Attachment1.Position = Vector3.new(0.05, 0, 0)
trail.Lifetime = 0.35
trail.MinLength = 0
trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
trail.Color = ColorSequence.new(Color3.fromRGB(180, 230, 255))
trail.Enabled = true
trail.Parent = visual

-- Kamera: yüksek yayın açısı, topa doğru yumuşak takip
if camera then
	camera.CameraType = Enum.CameraType.Scriptable
end

local renderPos = serverBall.Position
local lastTarget = serverBall.Position
local velocity = Vector3.zero
local camPos = Vector3.new(0, 320, 420)
local camLook = Vector3.zero
local camInit = false

local function onFrame(dt)
	local target = serverBall.Position

	-- Üstel yumuşatma + hız tahmini (replikasyon aralığını doldurur)
	local k = 1 - math.exp(-14 * dt)
	velocity = velocity:Lerp((target - lastTarget) / math.max(dt, 1e-3), 1 - math.exp(-6 * dt))
	lastTarget = target

	local predicted = target + velocity * 0.035
	renderPos = renderPos:Lerp(predicted, k)
	visual.CFrame = CFrame.new(renderPos)

	-- Kamera takibi
	if camera then
		local desiredPos = Vector3.new(renderPos.X * 0.22, 300, 400)
		local desiredLook = Vector3.new(renderPos.X * 0.55, renderPos.Y, renderPos.Z * 0.6)
		if not camInit then
			camPos = desiredPos
			camLook = desiredLook
			camInit = true
		else
			local ck = 1 - math.exp(-3.2 * dt)
			camPos = camPos:Lerp(desiredPos, ck)
			camLook = camLook:Lerp(desiredLook, ck)
		end
		camera.CFrame = CFrame.lookAt(camPos, camLook)
		camera.CameraType = Enum.CameraType.Scriptable
	end
end

RunService.RenderStepped:Connect(onFrame)

-- SPACE: şut isteği
local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
local kickRemote = remotes and remotes:WaitForChild("Kick", 10)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Space and kickRemote then
		kickRemote:FireServer()
	end
end)

-- Basit HUD
local gui = Instance.new("ScreenGui")
gui.Name = "FootballHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -24)
hint.Size = UDim2.new(0, 460, 0, 34)
hint.BackgroundColor3 = Color3.fromRGB(10, 16, 20)
hint.BackgroundTransparency = 0.25
hint.BorderSizePixel = 0
hint.TextColor3 = Color3.fromRGB(232, 240, 246)
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 15
hint.Text = "SPACE — şut çek   ·   top fiziği: 240 Hz, kendi motorumuz"
hint.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = hint
]=] },
	["server/SimLoop"] = { class = "Script", source = [=[
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

	-- Kale tespiti (top bu adımda kale çizgisini geçtiyse)
	local side = Pitch.goalCrossed(prev, self.ball.pos, self.cfg.BALL.radius)
	if side then
		self.lastGoal = { side = side, tick = self.ticks + 1, pos = self.ball.pos }
		-- Ağ topu tutar: kale çizgisini geçen top durur (Adım 5'te santra gelecek)
		self.ball.vel = Vec3.new(0, 0, -self.ball.vel.z * 0.1)
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
	SceneBuilder — Roblox sahnesini kodla kurar (Adım 2).

	Hiçbir şeyi elle yerleştirmeye gerek yok: çim, çizgiler, kaleler, direkler, ağ,
	top, ışık ve doğma noktası burada üretilir. Tek kurulum dosyası da bunu çağırır.

	Tüm ölçüler metreden stud'a çevrilir (Config.STUDS_PER_METER):
	gerçek bir saha 105 m = 375 stud uzunluğundadır, yani Roblox karakteri (~6 stud)
	gerçek ölçekte kalır. "Dev saha" hissi oluşmaz.

	Önemli: top dışındaki hiçbir parça fizik motoruna bırakılmaz; hepsi Anchored.
]]

local Config = require(script.Parent.Parent.Config)

local SceneBuilder = {}

-- Lua 5.3: math.atan(y, x) | Luau: math.atan2(y, x)
local atan2 = math.atan2 or math.atan

local S = Config.STUDS_PER_METER
local P = Config.PITCH
local LINE = 0.12 -- çizgi kalınlığı (metre)
local LINE_Y = 0.03 -- çim üstünden yükseklik (stud)

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

-- Metre koordinatını stud'a çevirir (yükseklik: y=0 çim yüzeyi)
local function v3(x, y, z)
	return Vector3.new(x * S, y * S, z * S)
end

-- Eksen hizalı çizgi: iki uç nokta (metre) arasında
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

-- Yay çizimi (orta yuvarlak / korner yayları): küçük segmentlerden
local function drawArc(parent, name, cx, cz, radius, startAngle, endAngle, segments)
	segments = segments or 24
	for i = 1, segments do
		local a1 = startAngle + (endAngle - startAngle) * ((i - 1) / segments)
		local a2 = startAngle + (endAngle - startAngle) * (i / segments)
		local x1, z1 = cx + math.cos(a1) * radius, cz + math.sin(a1) * radius
		local x2, z2 = cx + math.cos(a2) * radius, cz + math.sin(a2) * radius
		local seg = drawLine(parent, name .. "_" .. tostring(i), x1, z1, x2, z2)
		-- Segmenti iki uç arasında döndür
		local mid = Vector3.new((x1 + x2) / 2 * S, LINE_Y, (z1 + z2) / 2 * S)
		local len = math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2) * S
		local angle = atan2(z2 - z1, x2 - x1)
		seg.CFrame = CFrame.new(mid) * CFrame.Angles(0, -angle, 0)
		seg.Size = Vector3.new(math.max(len, LINE * S), 0.04, LINE * S)
	end
end

local function buildSurface(root)
	local folder = Instance.new("Folder")
	folder.Name = "Surface"
	folder.Parent = root

	-- Çim: 105 x 68 m, üst yüzü y = 0
	local grass = makePart(
		folder,
		"Grass",
		Vector3.new(P.length * S, 2, P.width * S),
		CFrame.new(0, -1, 0),
		Color3.fromRGB(38, 104, 56),
		Enum.Material.Grass,
		{ collide = true }
	)
	grass.CastShadow = false

	-- Biçme şeritleri (görsel derinlik)
	local stripes = 10
	for i = 0, stripes - 1 do
		local w = P.length / stripes
		local x = -P.length / 2 + w * (i + 0.5)
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

local function buildLines(root)
	local folder = Instance.new("Folder")
	folder.Name = "Lines"
	folder.Parent = root

	local HL, HW = P.halfLength, P.halfWidth

	-- Dış çizgiler
	drawLine(folder, "TouchlineNorth", -HL, -HW, HL, -HW)
	drawLine(folder, "TouchlineSouth", -HL, HW, HL, HW)
	drawLine(folder, "GoalLineWest", -HL, -HW, -HL, HW)
	drawLine(folder, "GoalLineEast", HL, -HW, HL, HW)

	-- Orta çizgi + orta yuvarlak + santra noktası
	drawLine(folder, "HalfwayLine", 0, -HW, 0, HW)
	drawArc(folder, "CenterCircle", 0, 0, P.centerCircleRadius, 0, math.pi * 2, 40)
	makePart(
		folder,
		"CenterSpot",
		Vector3.new(0.24 * S, 0.05, 0.24 * S),
		CFrame.new(v3(0, LINE_Y / S, 0)),
		Color3.fromRGB(246, 250, 252),
		nil,
		{ shape = Enum.PartType.Cylinder, castShadow = false }
	)

	-- Ceza sahası, kale sahası, penaltı noktası (iki kale)
	for _, side in ipairs({ -1, 1 }) do
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

local function buildGoals(root)
	local folder = Instance.new("Folder")
	folder.Name = "Goals"
	folder.Parent = root

	local frameColor = Color3.fromRGB(248, 250, 252)
	local postDia = P.postRadius * 2
	local barDia = P.crossbarRadius * 2

	for _, side in ipairs({ -1, 1 }) do
		local gl = side * P.halfLength
		local tag = side > 0 and "East" or "West"
		local goalFolder = Instance.new("Folder")
		goalFolder.Name = "Goal" .. tag
		goalFolder.Parent = folder

		-- Yan direkler: silindir ekseni X'tir; dikey yapmak için Z ekseninde 90° döndür
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

		-- Üst direk: ekseni Z'ye çevir
		makePart(
			goalFolder,
			"Crossbar",
			Vector3.new(P.goalHalfWidth * 2 * S, barDia * S, barDia * S),
			CFrame.new(v3(gl, P.goalHeight, 0)) * CFrame.Angles(0, math.rad(90), 0),
			frameColor,
			Enum.Material.Metal,
			{ shape = Enum.PartType.Cylinder }
		)

		-- Ağ: arka, iki yan, üst (yarı saydam)
		local netColor = Color3.fromRGB(230, 238, 244)
		local netOpts = { transparency = 0.45, castShadow = false }
		local depthX = gl + side * P.goalDepth

		makePart(
			goalFolder,
			"NetBack",
			Vector3.new(0.05 * S, P.goalHeight * S, P.goalHalfWidth * 2 * S),
			CFrame.new((depthX) * S, (P.goalHeight / 2) * S, 0),
			netColor,
			Enum.Material.Fabric,
			netOpts
		)
		for _, sz in ipairs({ -1, 1 }) do
			makePart(
				goalFolder,
				"NetSide",
				Vector3.new(P.goalDepth * S, P.goalHeight * S, 0.05 * S),
				CFrame.new(((gl + depthX) / 2) * S, (P.goalHeight / 2) * S, sz * P.goalHalfWidth * S),
				netColor,
				Enum.Material.Fabric,
				netOpts
			)
		end
		makePart(
			goalFolder,
			"NetTop",
			Vector3.new(P.goalDepth * S, 0.05 * S, P.goalHalfWidth * 2 * S),
			CFrame.new(((gl + depthX) / 2) * S, P.goalHeight * S, 0),
			netColor,
			Enum.Material.Fabric,
			netOpts
		)
	end
end

-- Top Workspace köküne konur: sunucu ve istemci onu Workspace.MatchBall olarak arar.
local function buildBall(root)
	local ball = makePart(
		root,
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

local function setupLighting()
	local Lighting = game:GetService("Lighting")
	local ok = pcall(function()
		Lighting.ClockTime = 15.5
		Lighting.Brightness = 2.3
		Lighting.Ambient = Color3.fromRGB(72, 82, 92)
		Lighting.OutdoorAmbient = Color3.fromRGB(126, 136, 146)
		Lighting.EnvironmentDiffuseScale = 0.45
		Lighting.EnvironmentSpecularScale = 0.3
		Lighting.GlobalShadows = true
		Lighting.ExposureCompensation = 0.1
	end)

	if ok and not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atm = Instance.new("Atmosphere")
		atm.Density = 0.32
		atm.Haze = 1.1
		atm.Glare = 0.1
		atm.Color = Color3.fromRGB(199, 212, 224)
		atm.Parent = Lighting
	end
end

local function buildSpawn(root)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PitchSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(0, 0.5, -(P.halfWidth + 12) * S)
	spawn.Color = Color3.fromRGB(60, 120, 200)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = root
	return spawn
end

--[[ Sahneyi kurar. Var olan FootballPitch klasörünü silip yeniden oluşturur
	(idempotent). Dönüş: { root = Folder, ball = BasePart } ]]
function SceneBuilder.build()
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

	buildSurface(root)
	buildLines(root)
	buildGoals(root)
	local ball = buildBall(workspace) -- kök altında değil, Workspace.MatchBall
	setupLighting()
	buildSpawn(root)

	-- Doğma noktasından düşen oyuncular çimin içine girmesin: zemin y=0.
	return { root = root, ball = ball }
end

-- Topu merkeze alır (gol sonrası / demo sıfırlama)
function SceneBuilder.resetBallPosition()
	local ball = workspace:FindFirstChild("MatchBall")
	if ball then
		ball.CFrame = CFrame.new(0, Config.BALL.radius * S, 0)
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
