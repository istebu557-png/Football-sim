--[[
	Adım 1 doğrulama testleri.

	Amaç: "gerçekçi" iddiasını SAYIYLA doğrulamak. Her test, gerçek futboldan
	bilinen bir fiziksel büyüklükle karşılaştırma yapar (düşme süresi, sekme
	yüksekliği, terminal hız, falso sapması, sprint süresi...).
]]

local Config = __load("shared/Config")
local Vec3 = __load("shared/Core/Vec3")
local Rng = __load("shared/Core/Rng")
local Aero = __load("shared/Core/Aero")
local Ball = __load("shared/Physics/Ball")
local Pitch = __load("shared/Physics/Pitch")
local Locomotion = __load("shared/Player/Locomotion")
local Sim = __load("shared/Sim")
local Ballistics = __load("shared/Core/Ballistics")
local Net = __load("shared/Physics/Net")
local Body = __load("shared/Physics/Body")
local BallControl = __load("shared/Player/BallControl")
local Keeper = __load("shared/Player/Keeper")
local Rig = __load("shared/Anim/Rig")
local Pose = __load("shared/Anim/Pose")
local Ease = __load("shared/Anim/Ease")
local KickAnim = __load("shared/Anim/KickAnim")
local KeeperAnim = __load("shared/Anim/KeeperAnim")
local WalkCycle = __load("shared/Anim/WalkCycle")
local PlayerPose = __load("shared/Anim/PlayerPose")
local Striker = __load("shared/Player/Striker")

local passed, failed = 0, 0
local failures = {}

local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
		print("  [OK]   " .. name)
	else
		failed = failed + 1
		failures[#failures + 1] = name
		print("  [FAIL] " .. name)
		print("         " .. tostring(err))
	end
end

local function check(cond, msg)
	if not cond then
		error(msg or "kontrol basarisiz", 2)
	end
end

local function jointComponents(character, jointName)
	local motor = character and character:FindFirstChild(jointName)
	if not motor then
		return nil
	end
	return { motor.Transform:GetComponents() }
end

local function jointsMoved(a, b)
	if not a or not b then
		return -1
	end
	local moved = 0
	for i = 1, 12 do
		if math.abs(a[i] - b[i]) > 1e-9 then
			moved = moved + 1
		end
	end
	return moved
end

local function near(actual, expected, tol, label)
	if math.abs(actual - expected) > tol then
		error(
			string.format(
				"%s: beklenen %s +- %s, gelen %s",
				tostring(label),
				tostring(expected),
				tostring(tol),
				tostring(actual)
			),
			2
		)
	end
end

local function between(actual, lo, hi, label)
	if actual < lo or actual > hi then
		error(
			string.format(
				"%s: [%s, %s] araliginda beklenirdi, gelen %s",
				tostring(label),
				tostring(lo),
				tostring(hi),
				tostring(actual)
			),
			2
		)
	end
end

local function newBall(pos, vel, spin)
	local b = Ball.new(Config, pos)
	b:setState(pos, vel or Vec3.new(0, 0, 0), spin or Vec3.new(0, 0, 0))
	return b
end

local function stepUntil(ball, predicate, maxSeconds)
	local dt = Config.FIXED_DT
	local t = 0
	local maxSteps = math.floor(maxSeconds / dt)
	for _ = 1, maxSteps do
		ball:step(dt)
		t = t + dt
		if predicate(ball) then
			return t, true
		end
	end
	return t, false
end

print("\n== 0. Kaynak sozdizimi ==")

test("tum Luau dosyalari gecerli sozdizimine sahip", function()
	local bad = {}
	for path, src in pairs(SOURCES) do
		local chunk, err = load(src, "@" .. path)
		if not chunk then
			bad[#bad + 1] = tostring(path) .. ": " .. tostring(err)
		end
	end
	check(#bad == 0, "sozdizimi hatasi:\n  " .. table.concat(bad, "\n  "))
end)

test("tek kurulum dosyasi gecerli Lua ve tum modulleri iceriyor", function()
	local chunk, err = load(INSTALLER_SRC, "@FootballSim_Install")
	check(chunk ~= nil, "kurulum dosyasi sozdizimi hatali: " .. tostring(err))
	local missing = {}
	for path in pairs(SOURCES) do
		if not INSTALLER_SRC:find(path, 1, true) then
			missing[#missing + 1] = path
		end
	end
	check(#missing == 0, "kurulumda eksik modul: " .. table.concat(missing, ", "))
end)

print("\n== 1. Vektor matematigi ==")

test("3-4-5 ucgeni: |(3,4,0)| = 5", function()
	near(Vec3.length(Vec3.new(3, 4, 0)), 5, 1e-12, "uzunluk")
end)

test("birim vektor ve sifir vektor", function()
	local u = Vec3.unit(Vec3.new(0, 7, 0))
	near(u.y, 1, 1e-12, "unit.y")
	local z = Vec3.unit(Vec3.new(0, 0, 0))
	check(z.x == 0 and z.y == 0 and z.z == 0, "sifir vektorun birimi sifir olmali")
end)

test("capraz carpim sag el kurali: x cross y = z", function()
	local c = Vec3.cross(Vec3.new(1, 0, 0), Vec3.new(0, 1, 0))
	near(c.z, 1, 1e-12, "cross.z")
	near(c.x, 0, 1e-12, "cross.x")
end)

test("dik vektorler arasi aci 90 derece", function()
	near(Vec3.angleBetween(Vec3.new(1, 0, 0), Vec3.new(0, 0, 1)), math.pi / 2, 1e-9, "aci")
end)

test("yaw/fromYaw tersinirligi", function()
	for _, a in ipairs({ 0, 0.7, -2.1, 3.0 }) do
		near(Vec3.yaw(Vec3.fromYaw(a)), a, 1e-9, "yaw")
	end
end)

print("\n== 2. Deterministik rastgelelik ==")

test("ayni tohum ayni diziyi uretir", function()
	local a = Rng.new(1337)
	local b = Rng.new(1337)
	for i = 1, 200 do
		check(a:next() == b:next(), "dizi " .. tostring(i) .. ". elemaninda ayristi")
	end
end)

test("farkli tohum farkli dizi", function()
	local a = Rng.new(1):next()
	local b = Rng.new(2):next()
	check(a ~= b, "farkli tohumlar ayni degeri uretti")
end)

test("degerler [0,1) araliginda ve ortalama ~0.5", function()
	local r = Rng.new(99)
	local sum = 0
	local n = 5000
	for _ = 1, n do
		local v = r:next()
		check(v >= 0 and v < 1, "aralik disi deger: " .. tostring(v))
		sum = sum + v
	end
	near(sum / n, 0.5, 0.03, "ortalama")
end)

test("int sinirlari ve normal dagilim", function()
	local r = Rng.new(5)
	for _ = 1, 500 do
		local v = r:int(3, 7)
		check(v >= 3 and v <= 7, "int araligi")
	end
	local sum = 0
	local n = 2000
	for _ = 1, n do
		sum = sum + r:normal(0, 1)
	end
	near(sum / n, 0, 0.08, "normal ortalama")
end)

print("\n== 3. Aerodinamik ==")

test("terminal hiz teorisi ~26.9 m/s", function()
	local vt = Aero.terminalSpeed(Config)
	between(vt, 25, 29, "teorik terminal hiz")
end)

test("800 m'den dusen top terminal hiza yaklasir", function()
	local b = newBall(Vec3.new(0, 800, 0))
	local _, ok = stepUntil(b, function(ball)
		return ball.pos.y < 400
	end, 60)
	check(ok, "top 400 m'ye inemedi (60 s)")
	-- 400 m'de hiz terminal hiza cok yaklasmis olmali
	between(Vec3.length(b.vel), 25, 29, "olculen hiz")
end)

test("30 m/s'te hava direnci ~12.7 m/s2 yavaslatir", function()
	local b = newBall(Vec3.new(0, 200, 0), Vec3.new(30, 0, 0))
	local v0 = Vec3.length(b.vel)
	for _ = 1, 6 do -- 6 * 1/240 = 0.025 s
		b:step(Config.FIXED_DT)
	end
	local drop = (v0 - Vec3.length(b.vel)) / 0.025
	between(drop, 11.5, 14.0, "olculen yavaslama (m/s2)")
end)

test("drag crisis: Cd yavasta buyuk, hizlida kucuk", function()
	local slow = Aero.dragCoefficientFor(4, Config)
	local fast = Aero.dragCoefficientFor(35, Config)
	check(slow > 0.40, "yavas Cd 0.40'tan buyuk olmali, gelen " .. tostring(slow))
	check(fast < 0.27, "hizli Cd 0.27'den kucuk olmali, gelen " .. tostring(fast))
	check(slow - fast > 0.12, "drag crisis farki en az 0.12 olmali")
end)

test("falso: 24 m/s, 60 rad/s spin -> 1 s'de 1.5-5 m yana sapma", function()
	local start = Vec3.new(0, 100, 0)
	local b = newBall(start, Vec3.new(24, 0, 0), Vec3.new(0, 60, 0))
	for _ = 1, 240 do
		b:step(Config.FIXED_DT)
	end
	local drift = b.pos.z - start.z
	check(drift < -1.5 and drift > -5.0, "beklenen -z yonunde 1.5-5 m sapma, gelen " .. tostring(drift))
end)

test("spinsiz top yana sapmaz", function()
	local b = newBall(Vec3.new(0, 100, 0), Vec3.new(24, 0, 0))
	for _ = 1, 240 do
		b:step(Config.FIXED_DT)
	end
	near(b.pos.z, 0, 1e-9, "spinsiz yan sapma")
end)

print("\n== 3b. Balistik (nisan cozumu) ==")

test("20 m hedefe 20 m/s: ideal cozum, drag nedeniyle ~%15 kisa duser", function()
	local from = Vec3.new(0, 0, 0)
	local to = Vec3.new(20, 0, 0)
	local v = Ballistics.solveLaunch(from, to, 20, Config.GRAVITY)
	check(v ~= nil, "cozum bulunamadi")
	check(v.y > 0, "firlatma acisi yukari olmali")
	local b = newBall(from, v)
	local _, landed = stepUntil(b, function(ball)
		return ball.contacts > 0
	end, 5)
	check(landed, "top yere inmedi")
	-- Hava direnci hesaba katilmadigi icin top 1.5-4 m kisa duser; bu, AI'nin
	-- neden drag-farkinda bir nisan modeli kullanmasi gerektigini gosterir.
	between(b.pos.x, 14.5, 18.5, "inis noktasi")
end)

test("asirtma yorungesi duz yorungeden daha yuksek", function()
	local from = Vec3.new(0, 0, 0)
	local to = Vec3.new(20, 0, 0)
	local flat = Ballistics.solveLaunch(from, to, 20, Config.GRAVITY, false)
	local lob = Ballistics.solveLaunch(from, to, 20, Config.GRAVITY, true)
	check(lob.y > flat.y, "lob daha yuksek acili olmali")
end)

test("menzil disi hedef icin cozum yok", function()
	check(Ballistics.solveLaunch(Vec3.new(0, 0, 0), Vec3.new(100, 0, 0), 10, Config.GRAVITY) == nil,
		"10 m/s ile 100 m ulasilamaz")
end)

print("\n== 4. Top-zemin fizigi ==")

test("2 m'den dusme suresi ~0.64 s", function()
	local b = newBall(Vec3.new(0, 2 + Config.BALL.radius, 0))
	local t, hit = stepUntil(b, function(ball)
		return ball.contacts > 0
	end, 3)
	check(hit, "top zemine inmedi")
	between(t, 0.62, 0.66, "dusme suresi")
end)

test("2 m'den dusen top ~1.10 m sekеr (e=0.74)", function()
	local b = newBall(Vec3.new(0, 2 + Config.BALL.radius, 0))
	local _, hit = stepUntil(b, function(ball)
		return ball.contacts > 0
	end, 3)
	check(hit, "ilk temas yok")
	local apex = 0
	for _ = 1, 240 do
		b:step(Config.FIXED_DT)
		if b.pos.y > apex then
			apex = b.pos.y
		end
	end
	between(apex, 1.02, 1.22, "sektikten sonraki tepe")
end)

test("sekmeler kisalir ve top durur (jitter yok)", function()
	local b = newBall(Vec3.new(0, 3 + Config.BALL.radius, 0))
	for _ = 1, 240 * 6 do
		b:step(Config.FIXED_DT)
	end
	check(b.contacts >= 2, "birden fazla sekme olmali, gelen " .. tostring(b.contacts))
	near(b.pos.y, Config.BALL.radius, 1e-9, "durusta yukseklik")
	near(Vec3.length(b.vel), 0, 1e-9, "durusta hiz")
end)

test("5 m/s ile yuvarlanan top ~21 m sonra durur", function()
	local b = newBall(Vec3.new(0, Config.BALL.radius, 0), Vec3.new(5, 0, 0))
	local _, stopped = stepUntil(b, function(ball)
		return Vec3.length(ball.vel) < 1e-9
	end, 60)
	check(stopped, "top 60 s'de durmadi")
	between(b.pos.x, 17, 24, "yuvarlanma mesafesi (m)")
	near(b.pos.y, Config.BALL.radius, 1e-12, "yerde kalan yukseklik")
end)

test("yuvarlanirken spin kaymadan yuvarlanma kosulunu saglar", function()
	local b = newBall(Vec3.new(0, Config.BALL.radius, 0), Vec3.new(4, 0, 0))
	for _ = 1, 240 do
		b:step(Config.FIXED_DT)
	end
	local r = Config.BALL.radius
	-- kayma = v + w x (0,-r,0) ~ 0  => w_z = -v_x/r, w_x = v_z/r
	near(b.spin.z, -b.vel.x / r, 1e-6, "spin.z")
	near(b.spin.x, b.vel.z / r, 1e-6, "spin.x")
end)

test("topspin sekmede topu ileri hizlandirir, backspin yavaslatir", function()
	-- Havadaki Magnus etkisini dislamak icin top tam zeminde, dikey hizla baslatilir.
	local r = Config.BALL.radius
	local function afterBounce(spinZ)
		local b = newBall(Vec3.new(0, r + 1e-4, 0), Vec3.new(3, -3, 0), Vec3.new(0, 0, spinZ))
		local _, hit = stepUntil(b, function(ball)
			return ball.contacts > 0
		end, 1)
		check(hit, "temas yok")
		return b.vel.x, b.spin.z
	end
	local topX, topSpin = afterBounce(-60)
	local backX, backSpin = afterBounce(60)
	check(topX > backX + 0.2, "topspin ileri hizlandirmali: top=" .. tostring(topX) .. " back=" .. tostring(backX))
	check(topSpin > -60, "topspinin spini surtunmeyle azalmali")
	check(backSpin < 60, "backspinin spini surtunmeyle azalmali")
end)

test("asiri degerlerde bile sayilar sonlu kalir (NaN yok)", function()
	local b = newBall(Vec3.new(0, 3, 0), Vec3.new(60, 12, 8), Vec3.new(300, 280, 260))
	for _ = 1, 240 * 5 do
		b:step(Config.FIXED_DT)
	end
	check(b:isFinite(), "top durumu NaN/sonsuz oldu")
end)

test("sekme yuksekligi adim boyutundan bagimsiz (60 Hz ~ 240 Hz)", function()
	local function apexWith(dt)
		local b = newBall(Vec3.new(0, 2 + Config.BALL.radius, 0))
		local t = 0
		while b.contacts == 0 and t < 3 do
			b:step(dt)
			t = t + dt
		end
		local apex = 0
		for _ = 1, math.floor(1.5 / dt) do
			b:step(dt)
			if b.pos.y > apex then
				apex = b.pos.y
			end
		end
		return apex
	end
	local a1 = apexWith(1 / 60)
	local a2 = apexWith(1 / 240)
	near(a1, a2, 0.02, "60 Hz ile 240 Hz sekme yuksekligi farki")
end)

print("\n== 5. Saha geometrisi ==")

test("cizgi disi tespiti top yaricapini hesaba katar", function()
	local r = Config.BALL.radius
	check(not Pitch.isOutOfPlay(Vec3.new(52.5, r, 0), r), "cizgi ustundeki top disarida olmamali")
	check(Pitch.isOutOfPlay(Vec3.new(52.5 + r + 0.01, r, 0), r), "tamami disarida olan top tac olmali")
	check(Pitch.isOutOfPlay(Vec3.new(0, r, 34.2), r), "yan cizgi disi")
end)

test("kale agzi / ust direk / disari ayrimi", function()
	local r = Config.BALL.radius
	local plane = 52.5 + r
	check(Pitch.goalCrossed(Vec3.new(plane - 0.5, 0.5, 0), Vec3.new(plane + 0.5, 0.6, 0), r) == "home", "duz sut gol olmali")
	check(Pitch.goalCrossed(Vec3.new(plane - 0.5, 0.5, 4.2), Vec3.new(plane + 0.5, 0.5, 4.2), r) == nil, "disari giden sut gol olmamali")
	check(Pitch.goalCrossed(Vec3.new(plane - 0.5, 3.0, 0), Vec3.new(plane + 0.5, 3.1, 0), r) == nil, "ust direk ustu gol olmamali")
	check(Pitch.goalCrossed(Vec3.new(plane - 0.5, 0.5, -1), Vec3.new(plane + 0.5, 0.5, -1), r) == "home", "sol caprazdan gol")
end)

test("penalti simulasyonu gol olarak kaydedilir", function()
	local sim = Sim.new({ seed = 1 })
	local ball = sim.ball
	ball:setState(Vec3.new(41.5, Config.BALL.radius, 0), Vec3.new(22, 3.2, 0), Vec3.new(0, 0, 0))
	sim:advance(2)
	check(sim.lastGoal ~= nil, "gol tespit edilemedi")
	check(sim.lastGoal.side == "home", "gol ev sahibinin kalesine mi sayildi? " .. tostring(sim.lastGoal and sim.lastGoal.side))
	between(sim.lastGoal.tick, 100, 160, "gol tick'i (0.42-0.67 s)")
end)

print("\n== 5b. Direk ve ust direk carpismasi ==")

test("direge carpan sut gol sayilmaz, geri doner", function()
	local sim = Sim.new({ seed = 1 })
	local r = Config.BALL.radius
	sim.ball:setState(Vec3.new(49.5, r, 3.66), Vec3.new(22, 0, 0), Vec3.new(0, 0, 0))
	sim:advance(1.5)
	check(sim.lastGoal == nil, "direge carpan top gol sayildi")
	check(sim.ball.postHits >= 1, "carpisma algilanmadi")
	check(sim.ball.pos.x < 52.5, "top diregin icinden gecti: x=" .. tostring(sim.ball.pos.x))
end)

test("ust direge carpan top gol olmaz", function()
	local sim = Sim.new({ seed = 1 })
	local r = Config.BALL.radius
	local P = Config.PITCH
	sim.ball:setState(Vec3.new(51.0, P.goalHeight, 0), Vec3.new(20, 0, 0), Vec3.new(0, 0, 0))
	sim:advance(1)
	check(sim.lastGoal == nil, "ust direge carpan top gol sayildi")
	check(sim.ball.postHits >= 1, "ust direk carpismasi algilanmadi")
end)

test("kale ortasina giden sut gol olur (direk karismaz)", function()
	local sim = Sim.new({ seed = 1 })
	sim.ball:setState(Vec3.new(41.5, Config.BALL.radius, 0), Vec3.new(22, 3.2, 0), Vec3.new(0, 0, 0))
	sim:advance(1.2)
	check(sim.lastGoal ~= nil and sim.lastGoal.side == "home", "gol tespit edilemedi")
	check(sim.ball.postHits == 0, "gereksiz direk carpismasi: " .. tostring(sim.ball.postHits))
end)

test("carpismadan sonra top direge gomulmez", function()
	local sim = Sim.new({ seed = 1 })
	local r = Config.BALL.radius
	sim.ball:setState(Vec3.new(49.0, 1.0, 3.66), Vec3.new(18, 0, 0), Vec3.new(0, 0, 0))
	sim:advance(0.6)
	local P = Config.PITCH
	local dx = sim.ball.pos.x - P.halfLength
	local dz = sim.ball.pos.z - P.goalHalfWidth
	local dist = math.sqrt(dx * dx + dz * dz)
	check(dist >= r + P.postRadius - 1e-3, "top diregin icine girdi, mesafe=" .. tostring(dist))
end)

print("\n== 5c. Oyuncu-top iliskisi ==")

test("kosan oyuncu topu onunde tutar (top surme)", function()
	local r = Config.BALL.radius
	local ball = Ball.new(Config, Vec3.new(10.8, r, 0))
	ball:setState(Vec3.new(10.8, r, 0), Vec3.new(0, 0, 0), Vec3.new(0, 0, 0))
	local bc = BallControl.new(Config)
	local player = { pos = Vec3.new(10, 0, 0), vel = Vec3.new(4, 0, 0), facing = 0, speed = 4 }

	local dt = 1 / 60
	local t = 0
	local maxDist, minDist = 0, 99
	for _ = 1, 120 do
		player.pos = Vec3.add(player.pos, Vec3.scale(player.vel, dt))
		bc:update(ball, player, t)
		ball:step(dt)
		local d = Vec3.distanceHorizontal(ball.pos, player.pos)
		if d > maxDist then maxDist = d end
		if d < minDist then minDist = d end
		t = t + dt
	end

	check(ball.pos.x > player.pos.x, "top oyuncunun gerisinde kaldi")
	between(minDist, 0.2, 1.6, "en yakin mesafe")
	between(maxDist, 0.5, 2.6, "en uzak mesafe")
	check(ball:speed() > 2.5, "top oyuncuyla birlikte ilerlemedi: " .. tostring(ball:speed()))
end)

test("dokunus sayisi gercek ritimde (~3/sn)", function()
	local r = Config.BALL.radius
	local ball = Ball.new(Config, Vec3.new(10.8, r, 0))
	ball:setState(Vec3.new(10.8, r, 0), Vec3.new(0, 0, 0), Vec3.new(0, 0, 0))
	local bc = BallControl.new(Config)
	local player = { pos = Vec3.new(10, 0, 0), vel = Vec3.new(5, 0, 0), facing = 0, speed = 5 }

	local dt = 1 / 60
	for i = 1, 180 do
		player.pos = Vec3.add(player.pos, Vec3.scale(player.vel, dt))
		bc:update(ball, player, i * dt)
		ball:step(dt)
	end
	between(bc.touches, 4, 11, "3 saniyedeki dokunus sayisi")
end)

test("sprint cezasi: hizli kosarken top kontrolden kacar", function()
	local r = Config.BALL.radius
	local function maxGap(speed)
		local ball = Ball.new(Config, Vec3.new(10.8, r, 0))
		ball:setState(Vec3.new(10.8, r, 0), Vec3.new(0, 0, 0), Vec3.new(0, 0, 0))
		local bc = BallControl.new(Config)
		local player = { pos = Vec3.new(10, 0, 0), vel = Vec3.new(speed, 0, 0), facing = 0, speed = speed }
		local dt = 1 / 60
		local peak = 0
		for i = 1, 180 do
			player.pos = Vec3.add(player.pos, Vec3.scale(player.vel, dt))
			bc:update(ball, player, i * dt)
			ball:step(dt)
			local d = Vec3.distanceHorizontal(ball.pos, player.pos)
			if d > peak then peak = d end
		end
		return peak
	end
	local slow = maxGap(4)
	local fast = maxGap(7.6)
	check(fast > slow + 0.25, "sprintte top daha fazla kacmali: yavas=" .. tostring(slow) .. " hizli=" .. tostring(fast))
end)

test("ilk dokunus (trap) hizli gelen topu yumusatir", function()
	local r = Config.BALL.radius
	local ball = Ball.new(Config, Vec3.new(10.9, r, 0))
	ball:setState(Vec3.new(10.9, r, 0), Vec3.new(-12, 0, 0), Vec3.new(0, 0, 0))
	local bc = BallControl.new(Config)
	local player = { pos = Vec3.new(10, 0, 0), vel = Vec3.new(0, 0, 0), facing = 0, speed = 0 }
	local event = bc:update(ball, player, 1.0)
	check(event == "trap", "trap tetiklenmedi: " .. tostring(event))
	check(ball:speed() < 5, "top yeterince yavaslamadi: " .. tostring(ball:speed()))
end)

test("govde: top oyuncunun icinden gecmez", function()
	local r = Config.BALL.radius
	local ball = Ball.new(Config, Vec3.new(10.0, 0.5, 0))
	ball:setState(Vec3.new(10.0, 0.5, 0), Vec3.new(-8, 0, 0), Vec3.new(0, 0, 0))
	local body = { pos = Vec3.new(10, 0, 0), vel = Vec3.new(0, 0, 0), radius = 0.42, height = 1.8, restitution = 0.4 }
	local hit = Body.collide(ball, body)
	check(hit, "carpisma algilanmadi")
	check(ball.vel.x > 0, "top geri donmedi: vx=" .. tostring(ball.vel.x))
	local dist = Body.reachDistance(ball, body)
	check(dist >= r + 0.42 - 1e-3, "top govdenin icine girdi: " .. tostring(dist))
end)

test("govde: kosan oyuncu topa hiz katar", function()
	local ball = Ball.new(Config, Vec3.new(10.5, 0.11, 0))
	ball:setState(Vec3.new(10.5, 0.11, 0), Vec3.new(0, 0, 0), Vec3.new(0, 0, 0))
	local body = { pos = Vec3.new(10, 0, 0), vel = Vec3.new(5, 0, 0), radius = 0.42, height = 1.8, restitution = 0.4 }
	Body.collide(ball, body)
	check(ball.vel.x > 3.5, "top oyuncunun hizini almadi: " .. tostring(ball.vel.x))
end)

test("sut mesafesi ve guc-hiz eslemesi", function()
	local r = Config.BALL.radius
	local ball = Ball.new(Config, Vec3.new(11.0, r, 0))
	ball:setState(Vec3.new(11.0, r, 0), Vec3.new(0, 0, 0), Vec3.new(0, 0, 0))
	local bc = BallControl.new(Config)
	local player = { pos = Vec3.new(10, 0, 0), vel = Vec3.new(0, 0, 0), facing = 0, speed = 0 }
	check(bc:canKick(ball, player), "1 m mesafede sut atilabilmeli")
	player.pos = Vec3.new(5, 0, 0)
	check(not bc:canKick(ball, player), "6 m mesafede sut atilamamali")
	-- SÜRÜŞ SAHİPLİĞİ: top sürerken dokunuş topu öne iter; katı menzil (kickReach)
	-- bu yüzden sürüş hâlinde hep aşılıyordu ("topu sürdüğüm için şut çekemiyorum").
	local BC = Config.BALL_CONTROL
	ball:setState(Vec3.new(11.0, r, 0), Vec3.new(0, 0, 0), Vec3.new(0, 0, 0))
	player.pos = Vec3.new(11.0 - 2.6, 0, 0) -- kickReach dışı, possessionReach içi
	check(not bc:canKick(ball, player), "now verilmezse katı kural geçerli (2.6 m > kickReach)")
	bc:kick(ball, player, Vec3.new(1, 0, 0), Vec3.new(0, 0, 0), 10.0) -- son dokunuş anı
	check(bc:canKick(ball, player, 10.2),
		"yeni dokunulan top 2.6 m öndeyken şut çıkmalı (sürüş sahipliği)")
	check(not bc:canKick(ball, player, 10.0 + BC.possessionTime + 0.05),
		"sahiplik süresi geçince şut çıkmamalı")
	player.pos = Vec3.new(11.0 - (BC.possessionReach + 0.6), 0, 0)
	check(not bc:canKick(ball, player, 10.1), "sahiplik menzilinin dışında şut çıkmamalı")
	player.pos = Vec3.new(10.2, 0, 0)
	ball.pos = Vec3.withY(ball.pos, BC.kickHeight + 0.4)
	check(not bc:canKick(ball, player, 10.1), "yüksek top sahiplikle vurulmamalı")
	ball:setState(Vec3.new(11.0, r, 0), Vec3.new(0, 0, 0), Vec3.new(0, 0, 0))
	near(bc:shotGap(ball, { pos = Vec3.new(8.0, 0, 0) }), 3.0, 1e-9, "shotGap yatay mesafeyi verir")
	check(BC.possessionReach > BC.kickReach, "sahiplik bandı katı menzilden geniş olmalı")
	check(BC.shotBufferReach > BC.possessionReach, "tampon menzili sahiplikten geniş olmalı")

	near(bc:speedForCharge(0), Config.BALL_CONTROL.minKickSpeed, 1e-9, "min guc")
	near(bc:speedForCharge(1), Config.BALL_CONTROL.maxKickSpeed, 1e-9, "max guc")
end)

print("\n== 5d. File (ag) iliskisi ==")

test("kaleye giren sut fileye takilir: durur, ag esner", function()
	local sim = Sim.new({ seed = 1 })
	local net = Net.new(Config, 1)
	sim.nets[1] = net
	local r = Config.BALL.radius

	local velocity = Ballistics.solveLaunch(Vec3.new(41.5, r, 0), Vec3.new(52.5, 1.0, 0), 22, Config.GRAVITY)
	sim.ball:setState(Vec3.new(41.5, r, 0), velocity, Vec3.new(0, 0, 0))

	local maxSag = 0
	local maxX = -100
	for _ = 1, 240 * 3 do
		sim:tick()
		maxSag = math.max(maxSag, net.sag)
		maxX = math.max(maxX, sim.ball.pos.x)
	end

	check(sim.lastGoal ~= nil, "gol tespit edilmedi")
	check(net.contacts >= 1, "aga temas olmadi")
	check(maxSag > 0.02, "ag esnemedi: " .. tostring(maxSag))
	check(net.sag < maxSag * 0.5, "ag toparlanmadi: " .. tostring(net.sag))
	check(sim.ball:speed() < 1.5, "top agda durmadi: " .. tostring(sim.ball:speed()))

	local P = Config.PITCH
	check(maxX <= P.halfLength + P.goalDepth + 0.01, "top agin arkasina gecti: " .. tostring(maxX))
	check(sim.ball.pos.x > P.halfLength, "top kale cizgisinin gerisinde: " .. tostring(sim.ball.pos.x))
end)

test("ag enerjiyi yutar (top hizi ~%95 duser)", function()
	local sim = Sim.new({ seed = 2 })
	local net = Net.new(Config, 1)
	sim.nets[1] = net
	local r = Config.BALL.radius
	local velocity = Ballistics.solveLaunch(Vec3.new(41.5, r, 0), Vec3.new(52.5, 0.8, 0), 26, Config.GRAVITY)
	sim.ball:setState(Vec3.new(41.5, r, 0), velocity, Vec3.new(0, 0, 0))
	local startSpeed = Vec3.length(velocity)
	sim:advance(2.5)
	check(sim.ball:speed() < startSpeed * 0.12, "top yeterince yavaslamadi: " .. tostring(sim.ball:speed()) .. "/" .. tostring(startSpeed))
end)

test("yan ag topu iceride tutar", function()
	local sim = Sim.new({ seed = 3 })
	local net = Net.new(Config, 1)
	sim.nets[1] = net
	local r = Config.BALL.radius
	-- Direge yakin giren sut: top kalenin icinde yan aga carpar
	local velocity = Ballistics.solveLaunch(Vec3.new(48, r, 1.5), Vec3.new(52.5, 1.2, 3.4), 18, Config.GRAVITY)
	sim.ball:setState(Vec3.new(48, r, 1.5), velocity, Vec3.new(0, 0, 0))
	sim:advance(3)

	check(sim.lastGoal ~= nil, "sut gol olmadi (senaryo kurulumu)")
	check(math.abs(sim.ball.pos.z) <= Config.PITCH.goalHalfWidth, "top yan agdan cikti: z=" .. tostring(sim.ball.pos.z))
end)

print("\n== 5e. Kaleci AI ==")

test("kaleci topun geldigi yone hareket eder", function()
	local keeper = Keeper.new(Config, 1)
	local ball = Ball.new(Config, Vec3.new(40, 0.5, 2.0))
	ball:setState(Vec3.new(40, 0.5, 2.0), Vec3.new(18, 1, 1.5), Vec3.new(0, 0, 0))
	local startZ = keeper.pos.z
	for _ = 1, 90 do
		keeper:step(ball, 1 / 60)
		ball:step(1 / 60)
	end
	check(keeper.pos.z > startZ + 0.2, "kaleci dogru yone gitmedi: " .. tostring(keeper.pos.z))
	between(keeper.pos.z, -Config.KEEPER.reachZ, Config.KEEPER.reachZ, "kaleci konumu")
end)

test("kaleci direklerin disina cikmaz", function()
	local keeper = Keeper.new(Config, 1)
	local ball = Ball.new(Config, Vec3.new(40, 0.5, 0))
	ball:setState(Vec3.new(40, 0.5, 8), Vec3.new(20, 0, 6), Vec3.new(0, 0, 0))
	for _ = 1, 120 do
		keeper:step(ball, 1 / 60)
	end
	check(math.abs(keeper.pos.z) <= Config.KEEPER.reachZ + 1e-6, "kaleci diregin disina cikti: " .. tostring(keeper.pos.z))
end)

test("kaleci govdesi sut engeller (kurtaris)", function()
	local sim = Sim.new({ seed = 9 })
	local r = Config.BALL.radius
	local keeper = Keeper.new(Config, 1)

	-- Kalecinin duracagi yere (z=0) dogru duz sut, govde sim'e verilir
	local velocity = Ballistics.solveLaunch(Vec3.new(44, r, 0), Vec3.new(52.5, 1.0, 0), 20, Config.GRAVITY)
	sim.ball:setState(Vec3.new(44, r, 0), velocity, Vec3.new(0, 0, 0))

	local hits = 0
	for _ = 1, 240 * 2 do
		local body = keeper:step(sim.ball, Config.FIXED_DT)
		sim.bodies[1] = body
		sim:tick()
		hits = body.hits or 0
	end

	check(hits >= 1, "kaleci topa temas etmedi")
	check(sim.lastGoal == nil, "kaleci varken gol oldu")
end)

print("\n== 6. Determinizm ve sabit adim ==")

test("ayni tohum + ayni girdi = bit-bit ayni sonuc", function()
	local function run()
		local sim = Sim.new({ seed = 42 })
		sim.ball:setState(Vec3.new(0, 0.11, 0), Vec3.new(18, 6, 3), Vec3.new(0, 40, 0))
		sim:advanceTicks(1200)
		return sim.ball
	end
	local a, b = run(), run()
	check(a.pos.x == b.pos.x and a.pos.y == b.pos.y and a.pos.z == b.pos.z, "konum ayristi")
	check(a.vel.x == b.vel.x and a.vel.y == b.vel.y and a.vel.z == b.vel.z, "hiz ayristi")
	check(a.spin.x == b.spin.x and a.spin.z == b.spin.z, "spin ayristi")
end)

test("tick gruplamasi sonucu degistirmez", function()
	local function run(grouped)
		local sim = Sim.new({ seed = 7 })
		sim.ball:setState(Vec3.new(0, 0.11, 0), Vec3.new(20, 5, -4), Vec3.new(0, 30, 0))
		if grouped then
			for _ = 1, 12 do
				sim:advanceTicks(100)
			end
		else
			sim:advanceTicks(1200)
		end
		return sim.ball.pos
	end
	local a, b = run(false), run(true)
	check(a.x == b.x and a.y == b.y and a.z == b.z, "gruplama sonucu degistirdi")
end)

test("kare hizi sonucu degistirmez (60 FPS vs 240 FPS, <= 0.2 m)", function()
	local function run(fps, frames)
		local sim = Sim.new({ seed = 3 })
		sim.ball:setState(Vec3.new(0, 0.11, 0), Vec3.new(20, 6, 0), Vec3.new(0, 0, 0))
		for _ = 1, frames do
			sim:update(1 / fps)
		end
		return sim
	end
	local a = run(60, 180)
	local b = run(240, 720)
	local d = Vec3.distance(a.ball.pos, b.ball.pos)
	check(d <= 0.2, "kare hizina bagli sapma cok buyuk: " .. tostring(d))
	check(math.abs(a.ticks - b.ticks) <= 1, "tick sayilari farkli: " .. tostring(a.ticks) .. " vs " .. tostring(b.ticks))
end)

test("spiral of death korumasi: 5 s'lik kare tek karede islenmez", function()
	local sim = Sim.new({ seed = 1 })
	local steps = sim:update(5.0)
	check(steps <= Config.MAX_SUBSTEPS, "cok fazla tick islendi: " .. tostring(steps))
	check(steps * Config.FIXED_DT <= Config.MAX_FRAME_DT + 1e-9, "islenen sure sinirli olmali")
end)

print("\n== 7. Oyuncu hareketi ==")

test("0-27 km/h hizlanma ~1.2-1.8 s", function()
	local p = Locomotion.new(Config, Vec3.new(0, 0, 0))
	local target = Config.PLAYER.maxSpeed * 0.95
	local t = 0
	while p:speed() < target and t < 5 do
		p:step(Vec3.new(1, 0, 0), Config.FIXED_DT, false)
		t = t + Config.FIXED_DT
	end
	between(t, 1.0, 2.0, "hizlanma suresi")
end)

test("hiz tavanini asmaz", function()
	local p = Locomotion.new(Config, Vec3.new(0, 0, 0))
	local peak = 0
	for _ = 1, 240 * 10 do
		p:step(Vec3.new(1, 0, 0), Config.FIXED_DT, true)
		if p:speed() > peak then
			peak = p:speed()
		end
	end
	check(peak <= Config.PLAYER.maxSpeed + 0.35, "tavan asildi: " .. tostring(peak))
end)

test("30 m sprint 4.5-6.5 s (yorulmayla birlikte)", function()
	local p = Locomotion.new(Config, Vec3.new(0, 0, 0))
	local t = 0
	while p.pos.x < 30 and t < 12 do
		p:step(Vec3.new(1, 0, 0), Config.FIXED_DT, true)
		t = t + Config.FIXED_DT
	end
	check(p.pos.x >= 30, "30 m'ye ulasilamadi")
	between(t, 4.3, 6.5, "sprint suresi")
end)

test("sprint sonrasi durma < 1 s", function()
	local p = Locomotion.new(Config, Vec3.new(0, 0, 0))
	for _ = 1, 240 * 3 do
		p:step(Vec3.new(1, 0, 0), Config.FIXED_DT, true)
	end
	local t = 0
	while p:speed() > 0.3 and t < 3 do
		p:step(Vec3.new(0, 0, 0), Config.FIXED_DT, false)
		t = t + Config.FIXED_DT
	end
	between(t, 0.2, 1.2, "durma suresi")
end)

test("yorgunluk: uzun sprintte stamina duser, dinlenince geri gelir", function()
	local p = Locomotion.new(Config, Vec3.new(0, 0, 0))
	for _ = 1, 240 * 20 do
		p:step(Vec3.new(1, 0, 0), Config.FIXED_DT, true)
	end
	local afterSprint = p.stamina
	check(afterSprint < 0.9, "stamina dusmedi: " .. tostring(afterSprint))
	for _ = 1, 240 * 10 do
		p:step(Vec3.new(0, 0, 0), Config.FIXED_DT, false)
	end
	check(p.stamina > afterSprint + 0.2, "stamina toparlanmadi: " .. tostring(p.stamina))
end)

test("gövde donusu sinirli (ani 180 derece donus yok)", function()
	local p = Locomotion.new(Config, Vec3.new(0, 0, 0), 0)
	for _ = 1, 120 do
		p:step(Vec3.new(1, 0, 0), Config.FIXED_DT, false)
	end
	local before = p.facing
	p:step(Vec3.new(-1, 0, 0), Config.FIXED_DT, false)
	local delta = math.abs(Locomotion.wrapAngle(p.facing - before))
	check(delta < 0.2, "tek adimda asiri donus: " .. tostring(delta))
end)

test("timeToReach tahmini gercekle uyumlu (%20 tolerans)", function()
	local p = Locomotion.new(Config, Vec3.new(0, 0, 0))
	local target = Vec3.new(20, 0, 0)
	local predicted = p:timeToReach(target)
	local t = 0
	while p.pos.x < 20 and t < 15 do
		p:step(Vec3.new(1, 0, 0), Config.FIXED_DT, true)
		t = t + Config.FIXED_DT
	end
	near(t, predicted, predicted * 0.2, "tahmin vs gercek")
end)

print("\n== 8. Tek kurulum dosyasi (sahte Roblox ortaminda) ==")

local installMock = nil

test("kurulum dosyasi hatasiz calisiyor", function()
	installMock = RobloxMock.install()

	local captured = {}
	local realPrint = print
	print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring(select(i, ...))
		end
		captured[#captured + 1] = table.concat(parts, " ")
	end

	local ok, err = pcall(function()
		local chunk = assert(load(INSTALLER_SRC, "@FootballSim_Install"))
		chunk()
	end)

	print = realPrint
	check(ok, "kurulum hata verdi: " .. tostring(err))
	check(#captured > 0, "kurulum rapor uretmedi")
	check(table.concat(captured, "\n"):find("FootballSim kurulumu", 1, true) ~= nil, "rapor basligi yok")
end)

test("script agaci dogru kuruldu (shared / server / client)", function()
	check(installMock ~= nil, "kurulum calismadi")
	local rs = installMock.replicatedStorage
	local shared = rs:FindFirstChild("Shared")
	check(shared ~= nil, "ReplicatedStorage.Shared yok")

	local config = shared:FindFirstChild("Config")
	check(config ~= nil and config.ClassName == "ModuleScript", "Config ModuleScript degil")
	check(config.Source ~= "", "Config kaynagi bos")

	local core = shared:FindFirstChild("Core")
	check(core ~= nil and core:FindFirstChild("Vec3") ~= nil, "Core.Vec3 yok")
	local physics = shared:FindFirstChild("Physics")
	check(physics ~= nil and physics:FindFirstChild("Ball") ~= nil, "Physics.Ball yok")
	local world = shared:FindFirstChild("World")
	check(world ~= nil and world:FindFirstChild("SceneBuilder") ~= nil, "World.SceneBuilder yok")

	local server = installMock.serverScriptService:FindFirstChild("Server")
	check(server ~= nil and server:FindFirstChild("SimLoop") ~= nil, "Sunucu SimLoop yok")
	check(server:FindFirstChild("SimLoop").ClassName == "Script", "SimLoop Script degil")

	local client = installMock.starterPlayerScripts:FindFirstChild("Client")
	check(client ~= nil and client:FindFirstChild("BallView") ~= nil, "Istemci BallView yok")
	check(client:FindFirstChild("BallView").ClassName == "LocalScript", "BallView LocalScript degil")
end)

test("sahne kuruldu: yarim saha, 1 kale, direkler, ag, kaleci, top", function()
	local ws = installMock.workspace
	local pitch = ws:FindFirstChild("FootballPitch")
	check(pitch ~= nil, "FootballPitch klasoru yok")

	local surface = pitch:FindFirstChild("Surface")
	check(surface ~= nil, "cim katmani yok")
	local grass = surface:FindFirstChild("Grass")
	check(grass ~= nil, "cim yok")
	-- Yarim saha: 52.5 m * 3.5714 = 187.5 stud
	local expectedWidth = 52.5 * 3.5714
	check(math.abs(grass.Size.X - expectedWidth) < 1.0,
		"cim yarim saha degil: " .. tostring(grass.Size.X) .. " (beklenen " .. tostring(expectedWidth) .. ")")

	local lines = pitch:FindFirstChild("Lines")
	check(lines ~= nil, "cizgiler yok")
	check(#lines:GetChildren() > 20, "cizgi sayisi cok az: " .. tostring(#lines:GetChildren()))

	local goals = pitch:FindFirstChild("Goals")
	check(goals ~= nil, "kaleler yok")
	check(#goals:GetChildren() == 1, "yarim sahada tek kale beklenirdi, gelen " .. tostring(#goals:GetChildren()))

	local goal = goals:FindFirstChild("GoalEast")
	check(goal ~= nil, "GoalEast yok")
	-- İki direk artik AYIRT EDILEBILIR ada sahip (PostNorth / PostSouth): ayni
	-- Name'i paylasan iki kardes FindFirstChild'i belirsizlestiriyordu.
	local posts = 0
	for _, child in ipairs(goal:GetChildren()) do
		if child.Name == "PostNorth" or child.Name == "PostSouth" then
			posts = posts + 1
		end
	end
	check(posts == 2, "iki direk beklenirdi, gelen " .. tostring(posts))
	check(goal:FindFirstChild("PostNorth") ~= nil, "PostNorth yok")
	check(goal:FindFirstChild("PostSouth") ~= nil, "PostSouth yok")
	local netSides = 0
	for _, child in ipairs(goal:GetChildren()) do
		if child.Name == "NetSideNorth" or child.Name == "NetSideSouth" then
			netSides = netSides + 1
		end
	end
	check(netSides == 2, "iki yan ag beklenirdi, gelen " .. tostring(netSides))
	check(goal:FindFirstChild("Crossbar") ~= nil, "ust direk yok")
	check(goal:FindFirstChild("NetBack") ~= nil, "arka ag yok")
	check(goal:FindFirstChild("NetTop") ~= nil, "ust ag yok")

	local keeper = pitch:FindFirstChild("Goalkeeper")
	check(keeper ~= nil, "kaleci modeli yok")
	local keeperRig = keeper:FindFirstChild("Rig")
	check(keeperRig ~= nil, "kaleci iskeleti (Rig) yok")
	check(keeperRig:FindFirstChild("Head") ~= nil and keeperRig:FindFirstChild("Torso") ~= nil, "kaleci parcalari eksik")
	check(keeperRig:FindFirstChild("UpperArmL") ~= nil and keeperRig:FindFirstChild("ForearmR") ~= nil, "kaleci kollari yok")
	check(keeperRig:FindFirstChild("ThighL") ~= nil and keeperRig:FindFirstChild("ShinR") ~= nil, "kaleci bacaklari yok")
	check(keeperRig:FindFirstChild("GloveL") ~= nil and keeperRig:FindFirstChild("GloveR") ~= nil, "kaleci eldivenleri yok")
	check(#keeperRig:GetChildren() == 15, "iskelet 15 parca olmali (13 kemik + 2 eldiven), gelen " .. tostring(#keeperRig:GetChildren()))

	-- Yeni varsayilan: sutu OYUNCU atar, NPC kapali -> sahada manken olmamali
	local striker = pitch:FindFirstChild("Striker")
	check(striker == nil,
		"varsayilanda sutcu NPC sahada olmamali (sutu oynayan oyuncu atar); Striker klasoru bulundu")

	local ball = ws:FindFirstChild("MatchBall")
	check(ball ~= nil, "top yok")
	check(ball.Shape == "PartType.Ball", "top sekli yanlis: " .. tostring(ball.Shape))
	check(ball.CFrame.pos.X > 0, "top yarim saha icinde baslamiyor")
end)

test("sutcu NPC yalnizca demo kipinde sahaya kurulur (varsayilan: sutu oyuncu atar)", function()
	local mock = RobloxMock.install()
	local ok, err = pcall(function()
		local chunk = assert(load(INSTALLER_SRC, "@FootballSim_Install"))
		chunk()
	end)
	check(ok, "kurulum calismadi: " .. tostring(err))

	local cfg = require(mock.replicatedStorage.Shared.Config)
	check(cfg.ANIM.strikerEnabled == false,
		"varsayilan strikerEnabled false olmali; aksi halde NPC oyuncudan rol calar")
	local sb = require(mock.replicatedStorage.Shared.World.SceneBuilder)

	cfg.ANIM.strikerEnabled = true
	sb.build({})
	local pitch = mock.workspace:FindFirstChild("FootballPitch")
	local striker = pitch and pitch:FindFirstChild("Striker")
	check(striker ~= nil, "strikerEnabled=true iken Striker kurulmadi")
	check(striker:FindFirstChild("Rig") ~= nil, "sutcu iskeleti yok")

	cfg.ANIM.strikerEnabled = false
	sb.build({})
	pitch = mock.workspace:FindFirstChild("FootballPitch")
	check(pitch:FindFirstChild("Striker") == nil, "kapatinca Striker sahneden cikmali")
end)

test("kurulum tekrar calistirilinca cogaltmiyor (idempotent)", function()
	local ws = installMock.workspace
	local pitch = ws:FindFirstChild("FootballPitch")
	local goals = pitch:FindFirstChild("Goals")
	local before = #goals:GetChildren()
	local lineCountBefore = #pitch:FindFirstChild("Lines"):GetChildren()

	local realPrint = print
	print = function() end
	local ok = pcall(function()
		local chunk = assert(load(INSTALLER_SRC, "@FootballSim_Install"))
		chunk()
	end)
	print = realPrint
	check(ok, "ikinci kurulum hata verdi")

	local pitchAfter = ws:FindFirstChild("FootballPitch")
	check(#pitchAfter:GetChildren() > 0, "sahne silindi")
	check(#pitchAfter:FindFirstChild("Goals"):GetChildren() == before, "kale klasorleri cogaldi")
	check(#pitchAfter:FindFirstChild("Lines"):GetChildren() == lineCountBefore, "cizgiler cogaldi")
end)

-- Bir instance ağacında aynı adı paylaşan kardeşleri bulur. Roblox'ta ad tekrarı
-- yasaldir ama FindFirstChild'ı belirsizleştirir ve Studio ağacını okunmaz yapar.
local function duplicateSiblings(root)
	local duplicates = {}
	local visited = 0
	local function walk(parent, path)
		local seen = {}
		for _, child in ipairs(parent:GetChildren()) do
			visited = visited + 1
			local childPath = path .. "/" .. child.Name
			if seen[child.Name] then
				duplicates[#duplicates + 1] = childPath
			end
			seen[child.Name] = true
			walk(child, childPath)
		end
	end
	walk(root, root.Name or "root")
	return duplicates, visited
end

test("sahne agacinda cift kardes adi yok (FindFirstChild belirsiz degil)", function()
	local mock = RobloxMock.install()
	local ok, err = pcall(function()
		local chunk = assert(load(INSTALLER_SRC, "@FootballSim_Install"))
		chunk()
	end)
	check(ok, "kurulum calismadi: " .. tostring(err))

	local pitch = mock.workspace:FindFirstChild("FootballPitch")
	check(pitch ~= nil, "workspace.FootballPitch kurulmadi")

	-- Yürüyüş gerçekten tüm ağacı gezdi mi? (yarım saha: yüzey + ~24 çizgi + yay
	-- segmentleri + kale + 2 prosedürel iskelet + top ≈ 96 instance)
	local duplicates, visited = duplicateSiblings(mock.workspace)
	check(visited > 60, "sahne agaci beklenenden kucuk: " .. tostring(visited) .. " instance")
	check(#duplicates == 0,
		"ayni adi paylasan kardesler (FindFirstChild belirsiz): " .. table.concat(duplicates, ", "))

	-- Somut örnek: ceza sahasının iki kenarı artık ayırt edilebilir
	local lines = pitch:FindFirstChild("Lines")
	check(lines ~= nil, "Lines klasoru yok")
	local north = lines:FindFirstChild("PenaltyAreaSideEastNorth")
	local south = lines:FindFirstChild("PenaltyAreaSideEastSouth")
	check(north ~= nil, "PenaltyAreaSideEastNorth yok")
	check(south ~= nil, "PenaltyAreaSideEastSouth yok")
	check(north ~= south, "kuzey ve guney ceza sahasi kenari ayni parca")
	local goal = pitch:FindFirstChild("Goals"):FindFirstChild("GoalEast")
	check(goal:FindFirstChild("PostNorth") ~= goal:FindFirstChild("PostSouth"), "iki direk ayni parca")

	-- Tam saha: iki kale + iki tarafın çizgileri → ad çakışması riski en yüksek kip
	local okFull, errFull = pcall(function()
		local sb = require(mock.replicatedStorage.Shared.World.SceneBuilder)
		sb.build({ half = false })
	end)
	check(okFull, "tam saha kurulamadi: " .. tostring(errFull))
	local fullPitch = mock.workspace:FindFirstChild("FootballPitch")
	check(fullPitch ~= nil, "tam saha FootballPitch yok")
	local goals = fullPitch:FindFirstChild("Goals")
	check(goals and #goals:GetChildren() == 2,
		"tam sahada iki kale beklenirdi, gelen " .. tostring(goals and #goals:GetChildren()))
	local dupFull, visitedFull = duplicateSiblings(mock.workspace)
	check(visitedFull > visited, "tam saha agaci yarim sahadan kucuk: " .. tostring(visitedFull))
	check(#dupFull == 0,
		"tam sahada ayni adi paylasan kardesler: " .. table.concat(dupFull, ", "))
end)

-- Doğma noktası topa UZAKSA oyuncu ilk SPACE'te hiçbir şey olmaz ve bunu
-- "şut çekemiyorum" diye yaşar: sunucu menzil kapısı (kickReach) sessizce
-- reddeder. Bu test sahnenin kendisini bağlar: spawn, topun vuruş menzili
-- içinde olmalı. (Eskiden 11.5 m gerideydi.)
--[[ Kurulu sahnede doğma noktası ile top arasındaki yatay mesafe (metre).
     Dönüş: mesafe, menzil (kickReach), PitchSpawn, MatchBall ]]
local function spawnToBallMeters(mockEnv)
	local cfg = require(mockEnv.replicatedStorage.Shared.Config)
	local pitch = mockEnv.workspace:FindFirstChild("FootballPitch")
	local spawn = pitch and pitch:FindFirstChild("PitchSpawn")
	local ball = mockEnv.workspace:FindFirstChild("MatchBall")
	if not spawn or not ball then
		return nil, cfg.BALL_CONTROL.kickReach, spawn, ball
	end
	local dx = spawn.Position.X - ball.Position.X
	local dz = spawn.Position.Z - ball.Position.Z
	local distM = math.sqrt(dx * dx + dz * dz) / cfg.STUDS_PER_METER
	return distM, cfg.BALL_CONTROL.kickReach, spawn, ball
end

local function freshInstalledScene(opts)
	local mockEnv = RobloxMock.install()
	local ok, err = pcall(function()
		local chunk = assert(load(INSTALLER_SRC, "@FootballSim_Install"))
		chunk()
	end)
	check(ok, "kurulum calismadi: " .. tostring(err))
	if opts and opts.half == false then
		local sb = require(mockEnv.replicatedStorage.Shared.World.SceneBuilder)
		sb.build({ half = false })
	end
	return mockEnv
end

test("dogma noktasi topun vurus menzili icinde (ilk SPACE bos gecmemeli)", function()
	local mockEnv = freshInstalledScene({})
	local distM, reach, spawn, ball = spawnToBallMeters(mockEnv)
	check(spawn ~= nil, "yarim sahada PitchSpawn yok")
	check(ball ~= nil, "sahnede MatchBall yok")
	check(distM ~= nil, "spawn-top mesafesi olculemedi")
	check(distM <= reach, string.format(
		"dogma noktasi toptan %.2f m geride, vurus menzili %.2f m: oyuncu ilk SPACE'te sut atamaz (sessiz red)",
		distM, reach))
	check(distM >= 0.35, string.format(
		"dogma noktasi topun icinde (%.2f m): karakter dogar dogmaz topa carpip onu surer", distM))
	-- Menzil kapısı gerçekten bu mesafede açık mı? (geometri ile kural aynı şeyi mi söylüyor)
	local SPM = Config.STUDS_PER_METER
	local bx, bz = ball.Position.X / SPM, ball.Position.Z / SPM
	local sx, sz = spawn.Position.X / SPM, spawn.Position.Z / SPM
	local simBall = Ball.new(Config, Vec3.new(bx, Config.BALL.radius, bz))
	simBall:setState(Vec3.new(bx, Config.BALL.radius, bz), Vec3.new(0, 0, 0), Vec3.new(0, 0, 0))
	local bc = BallControl.new(Config)
	local spawner = { pos = Vec3.new(sx, 0, sz), vel = Vec3.new(0, 0, 0), facing = 0, speed = 0 }
	check(bc:canKick(simBall, spawner), string.format(
		"dogma noktasindaki oyuncu icin canKick false (%.2f m): menzil kapisi hala kapali", distM))
end)

test("tam sahada da dogma noktasi menzil icinde", function()
	local mockEnv = freshInstalledScene({ half = false })
	local distM, reach, spawn = spawnToBallMeters(mockEnv)
	check(spawn ~= nil, "tam sahada PitchSpawn yok")
	check(distM ~= nil, "tam sahada spawn-top mesafesi olculemedi")
	check(distM <= reach, string.format(
		"tam sahada dogma noktasi toptan %.2f m uzak (menzil %.2f m)", distM, reach))
end)

test("kaleci dalisi topun gittigi yana yatar (ters yonelmez)", function()
	-- Dogu kalesi (side=+1): kaleci -X'e bakar, saga uzanmasi dünya -Z demektir.
	-- Top dünya +Z tarafina gidiyorsa kaleci SOLUNA (yerel -dz) uzanmali ve
	-- ellerinin dünya z'si POZITIF olmali.
	local keeper = Keeper.new(Config, 1)
	local ball = newBall(Vec3.new(35, 1.0, 0.6), Vec3.new(18, 0, 2.4))
	local dt = Config.FIXED_DT
	for _ = 1, math.floor(0.6 / dt) do
		keeper:step(ball, dt)
		ball:step(dt)
	end
	check(keeper.state == "dive", "dalis beklenirdi, gelen " .. tostring(keeper.state))
	local target = keeper.diveTarget
	check(target ~= nil, "diveTarget kilitlenmedi")
	check(target.dz < 0,
		"yerel dz isareti yanlis: " .. string.format("%.2f", target.dz) .. " (top +Z tarafinda, kaleci sağı -Z)")

	-- Pozu kalecinin dünya yerlesimiyle çöz: eller topun tarafina uzanmali
	local anim = KeeperAnim.new({ dz = target.dz, height = target.height, speed = target.speed })
	local solved = Rig.solve(anim:sample(0.45).pose)
	local yaw = math.atan(0, -1) -- keeperYaw(1)
	local origin = Vec3.new(keeper.pos.x, 0, keeper.pos.z)
	local handR = Rig.toWorld(solved.pos.handR, origin, yaw, 1)
	local handL = Rig.toWorld(solved.pos.handL, origin, yaw, 1)
	local handsZ = (handR.z + handL.z) / 2
	check(handsZ > 0.35,
		"eller topun tersine uzandi: ellerZ=" .. string.format("%.2f", handsZ) .. " m (top +Z tarafinda)")
	local rootW = Rig.toWorld(solved.pos.root, origin, yaw, 1)
	check(rootW.z > 0.15,
		"gövde topun tersine yatti: rootZ=" .. string.format("%.2f", rootW.z))
end)

test("kaleci dalis yönü bati kalesinde de dogru (side=-1 aynasi)", function()
	-- Bati kalesi: kaleci +X'e bakar, sağı dünya +Z'si. Top dünya +Z'ye gidiyorsa
	-- yerel dz POZITIF, ellerin dünya z'si yine pozitif olmali.
	local keeper = Keeper.new(Config, -1)
	local ball = newBall(Vec3.new(-35, 1.0, 0.6), Vec3.new(-18, 0, 2.4))
	local dt = Config.FIXED_DT
	for _ = 1, math.floor(0.6 / dt) do
		keeper:step(ball, dt)
		ball:step(dt)
	end
	check(keeper.state == "dive", "dalis beklenirdi, gelen " .. tostring(keeper.state))
	local target = keeper.diveTarget
	check(target ~= nil, "diveTarget kilitlenmedi")
	check(target.dz > 0,
		"yerel dz isareti yanlis (bati): " .. string.format("%.2f", target.dz))
	local anim = KeeperAnim.new({ dz = target.dz, height = target.height, speed = target.speed })
	local solved = Rig.solve(anim:sample(0.45).pose)
	local yaw = math.atan(0, 1) -- keeperYaw(-1)
	local origin = Vec3.new(keeper.pos.x, 0, keeper.pos.z)
	local handR = Rig.toWorld(solved.pos.handR, origin, yaw, 1)
	local handL = Rig.toWorld(solved.pos.handL, origin, yaw, 1)
	local handsZ = (handR.z + handL.z) / 2
	check(handsZ > 0.35,
		"bati kalesinde eller ters yana: ellerZ=" .. string.format("%.2f", handsZ))
end)

test("stadyum cevresi kuruluyor: tribun, pano, flama, isik kulesi, gokyuzu", function()
	local mock = RobloxMock.install()
	local ok, err = pcall(function()
		local chunk = assert(load(INSTALLER_SRC, "@FootballSim_Install"))
		chunk()
	end)
	check(ok, "kurulum calismadi: " .. tostring(err))

	local pitch = mock.workspace:FindFirstChild("FootballPitch")
	check(pitch ~= nil, "FootballPitch yok")
	local surround = pitch:FindFirstChild("Surround")
	check(surround ~= nil, "Surround klasoru yok (saha disi bosluk)")

	local function count(prefix)
		local n = 0
		for _, child in ipairs(surround:GetChildren()) do
			if child.Name:sub(1, #prefix) == prefix then
				n = n + 1
			end
		end
		return n
	end

	check(surround:FindFirstChild("Apron") ~= nil, "apron yok: saha disi gri bosluk gorunur")
	check(count("StandNorth") >= 5, "kuzey tribunu eksik: " .. tostring(count("StandNorth")))
	check(count("StandSouth") >= 5, "guney tribunu eksik: " .. tostring(count("StandSouth")))
	check(count("StandEast") >= 5, "kale arkasi tribunu eksik: " .. tostring(count("StandEast")))
	check(count("AdBoard") >= 28, "reklam panolari eksik: " .. tostring(count("AdBoard")))
	check(count("FlagPole") == 4, "kose flamasi diregi 4 olmali: " .. tostring(count("FlagPole")))
	local flags = 0
	for _, child in ipairs(surround:GetChildren()) do
		-- "FlagNW" say, "FlagPoleNW" sayma (on-ek cakismasi)
		if child.Name:sub(1, 4) == "Flag" and child.Name:sub(5, 8) ~= "Pole" then
			flags = flags + 1
		end
	end
	check(flags == 4, "kose flamasi 4 olmali: " .. tostring(flags))
	check(count("LightPole") == 4, "isik kulesi 4 olmali: " .. tostring(count("LightPole")))
	check(count("LightHead") == 4, "isik kafasi 4 olmali: " .. tostring(count("LightHead")))

	-- Ceza yayi ("D") Lines klasorunde olmali
	local lines = pitch:FindFirstChild("Lines")
	local arc = 0
	for _, child in ipairs(lines:GetChildren()) do
		if child.Name:sub(1, 10) == "PenaltyArc" then
			arc = arc + 1
		end
	end
	check(arc >= 10, "ceza yayi segmentleri eksik: " .. tostring(arc))

	-- Sunum katmani: gokyuzu + altin saat + efektler
	local Lighting = game:GetService("Lighting")
	check(Lighting:FindFirstChildOfClass("Sky") ~= nil, "Sky yok: ufuk gri stüdyo boslugu kalir")
	check(Lighting:FindFirstChildOfClass("SunRaysEffect") ~= nil, "SunRaysEffect yok")
	check(Lighting:FindFirstChildOfClass("BloomEffect") ~= nil, "BloomEffect yok")
	check(Lighting:FindFirstChildOfClass("ColorCorrectionEffect") ~= nil, "ColorCorrectionEffect yok")
	check(Lighting.ClockTime >= 16 and Lighting.ClockTime <= 17.5,
		"altin saat disinda isik: ClockTime=" .. tostring(Lighting.ClockTime))

	-- Kaleci turuncu formayla ayirt edilmeli
	local keeperRig = pitch:FindFirstChild("Goalkeeper"):FindFirstChild("Rig")
	local torso = keeperRig:FindFirstChild("Torso")
	check(torso ~= nil and torso.Color ~= nil, "kaleci govdesi yok")
	check(torso.Color.R > 0.8 and torso.Color.G > 0.4 and torso.Color.B < 0.3,
		"kaleci formasi turuncu degil (sahada secilmiyor)")
end)

print("\n== 9. Prosedurel animasyon (kod ile, asset yok) ==")

-- Yardımcı: poz uygulanmis iskelet
local function solve(pose)
	return Rig.solve(pose or Pose.new())
end

test("iskelet: durus pozunda ayaklar yerde, bas 1.56 m", function()
	local r = solve()
	near(r.pos.ankleL.y, 0.06, 0.01, "sol ayak bilegi")
	near(r.pos.ankleR.y, 0.06, 0.01, "sag ayak bilegi")
	near(r.pos.toeL.y, 0.0, 0.02, "sol ayak ucu yerde")
	near(r.pos.head.y, 1.56, 0.02, "bas yuksekligi")
	near(r.pos.handL.y, 0.84, 0.03, "el yuksekligi (kol asagi)")
end)

test("iskelet: kemik uzunluklari pozdan bagimsiz sabit", function()
	local function lengths(pose)
		local r = solve(pose)
		return {
			thigh = Vec3.distance(r.pos.hipR, r.pos.kneeR),
			shin = Vec3.distance(r.pos.kneeR, r.pos.ankleR),
			arm = Vec3.distance(r.pos.shoulderR, r.pos.handR),
		}
	end
	local base = lengths(Pose.new())
	local bent = lengths({ hipR = Pose.joint(-1.1, 0.3, 0), kneeR = Pose.joint(1.4, 0, 0), spine = Pose.joint(0.4, 0.2, 0) })
	near(bent.thigh, base.thigh, 1e-9, "ust bacak")
	near(bent.shin, base.shin, 1e-9, "alt bacak")
	near(bent.arm, base.arm, 1e-9, "kol")
	between(base.thigh, 0.44, 0.46, "ust bacak uzunlugu")
end)

test("iskelet: kalca one donunce ayak one gider", function()
	local forward = solve({ hipR = Pose.joint(-0.9, 0, 0) })
	local back = solve({ hipR = Pose.joint(0.9, 0, 0) })
	check(forward.pos.toeR.z > 0.35, "one savurmada ayak one gitmedi: " .. tostring(forward.pos.toeR.z))
	check(back.pos.toeR.z < -0.35, "geri savurmada ayak geriye gitmedi: " .. tostring(back.pos.toeR.z))
end)

test("sut animasyonu: temas zamani ve ayak one gelir", function()
	local kick = KickAnim.new({ ballHeight = 0.11, ballLateral = 0.1, charge = 0.8 })
	check(kick:sample(0.20).contact == false, "temastan once contact=true olmamali")
	check(kick:sample(0.25).contact == true, "temas sonrasi contact=true olmali")

	local atContact = solve(kick:sample(0.24).pose)
	local kickingFoot = atContact.pos["toe" .. kick.foot]
	local supportFoot = atContact.pos["toe" .. kick.otherFoot]
	check(kickingFoot.z > supportFoot.z + 0.25, "vuran ayak destek ayagindan onde degil")
	check(kickingFoot.z > 0.30, "vuran ayak topa dogru one gitmedi: " .. tostring(kickingFoot.z))
end)

test("sut animasyonu: top yukseldikce ayak yukselir (vole)", function()
	local low = KickAnim.new({ ballHeight = 0.11, ballLateral = 0 })
	local high = KickAnim.new({ ballHeight = 1.9, ballLateral = 0 })
	local lowFoot = solve(low:sample(0.24).pose).pos["toe" .. low.foot]
	local highFoot = solve(high:sample(0.24).pose).pos["toe" .. high.foot]
	check(highFoot.y > lowFoot.y + 0.25,
		"yuksek topa ayak daha yukari cikmali: alcak=" .. tostring(lowFoot.y) .. " yuksek=" .. tostring(highFoot.y))
	-- Yuksek topta govde geriye yatar
	check(high:sample(0.24).pose.spine.x > low:sample(0.24).pose.spine.x, "vole'de govde geriye yatmali")
end)

test("sut animasyonu: guc arttikca takip yuksekligi artar", function()
	local soft = KickAnim.new({ ballHeight = 0.11, charge = 0.15 })
	local hard = KickAnim.new({ ballHeight = 0.11, charge = 1.0 })
	local softFoot = solve(soft:sample(0.40).pose).pos["toe" .. soft.foot]
	local hardFoot = solve(hard:sample(0.40).pose).pos["toe" .. hard.foot]
	check(hardFoot.y > softFoot.y + 0.05,
		"guc arttikca bacak daha yukari savrulmali: yumusak=" .. tostring(softFoot.y) .. " sert=" .. tostring(hardFoot.y))
end)

test("sut animasyonu: topun yanina gore ayak secilir", function()
	check(KickAnim.new({ ballLateral = 0.4 }).foot == "R", "sag taraftaki top sag ayakla vurulmali")
	check(KickAnim.new({ ballLateral = -0.4 }).foot == "L", "sol taraftaki top sol ayakla vurulmali")
end)

test("sut animasyonu: hareket sonunda dinlenme pozuna doner", function()
	local kick = KickAnim.new({ ballHeight = 0.11, charge = 0.9 })
	local endPose = kick:sample(kick:duration())
	local r = solve(endPose)
	near(r.pos.toeR.y, 0.0, 0.03, "sut sonrasi ayak yerde")
	near(r.pos.toeL.y, 0.0, 0.03, "sut sonrasi diger ayak yerde")
end)

test("kaleci: topun yuksekligine gore hareket tipi secer", function()
	check(KeeperAnim.new({ dz = 0.1, height = 0.5 }).kind == "block", "orta top -> blok")
	check(KeeperAnim.new({ dz = 1.2, height = 0.4 }).kind == "dive", "yana alcak top -> dalis")
	check(KeeperAnim.new({ dz = 0.2, height = 1.9 }).kind == "jump", "yuksek orta top -> ziplama")
	check(KeeperAnim.new({ dz = 1.4, height = 1.8 }).kind == "jumpDive", "yana yuksek top -> ziplamali dalis")
end)

test("kaleci: dalis yonu topun yonune uyar ve uzanir", function()
	local right = KeeperAnim.new({ dz = 1.2, height = 0.5 })
	local left = KeeperAnim.new({ dz = -1.2, height = 0.5 })
	local rp = right:sample(0.40).pose
	local lp = left:sample(0.40).pose
	check(rp.rootOffset.x > 0.5, "saga dalis +x yonunde olmali: " .. tostring(rp.rootOffset.x))
	check(lp.rootOffset.x < -0.5, "sola dalis -x yonunde olmali: " .. tostring(lp.rootOffset.x))
	check(rp.rootOffset.y < 0, "alcak dalista govde alcak olmali")

	local r = solve(rp)
	local l = solve(lp)
	-- Kollar topa dogru uzanir: sag dalişta sag el sagda
	check(r.pos.handR.x > r.pos.shoulderR.x + 0.25, "sag dalista kol uzanmadi")
	check(l.pos.handL.x < l.pos.shoulderL.x - 0.25, "sol dalista kol uzanmadi")
end)

test("kaleci: yuksek topta ziplar (govde yukselir)", function()
	local jump = KeeperAnim.new({ dz = 0.2, height = 1.9 })
	local pose = jump:sample(0.40).pose
	check(pose.rootOffset.y > 0.3, "ziplamada govde yukselmedi: " .. tostring(pose.rootOffset.y))
	local r = solve(pose)
	check(r.pos.handR.y > 1.9, "ziplamada eller yukari uzanmali: " .. tostring(r.pos.handR.y))
end)

test("kaleci: hareket sonunda toparlanir (govde eski yerinde)", function()
	local dive = KeeperAnim.new({ dz = 1.2, height = 0.5 })
	local pose = dive:sample(0.95).pose
	check(math.abs(pose.rootOffset.x) < 0.02, "dalistan sonra yanal ofset kalmamali")
	check(math.abs(pose.rootOffset.y) < 0.02, "dalistan sonra dikey ofset kalmamali")
end)

test("kaleci: uzanma mesafesi topun uzakligiyla artar", function()
	local near_ = KeeperAnim.new({ dz = 0.6, height = 0.4 })
	local far = KeeperAnim.new({ dz = 1.15, height = 0.4 })
	check(far.reach > near_.reach, "uzak topa daha cok uzanmali")
end)

test("kosu dongusu: bacaklar ve kollar karsilikli salinir", function()
	local p = WalkCycle.sample(6.0, 0.25, 0)
	check(p.hipL.x * p.hipR.x < 0, "bacaklar zit yonde olmali")
	check(p.shoulderL.x * p.shoulderR.x < 0, "kollar zit yonde olmali")
	local p2 = WalkCycle.sample(6.0, 0.75, 0)
	check(p.hipL.x * p2.hipL.x < 0, "yarim dongude bacak yon degistirmeli")
end)

test("kosu dongusu: hiz artinca adim buyur, durunca sifirlanir", function()
	local slow = WalkCycle.sample(2.0, 0.25, 0)
	local fast = WalkCycle.sample(7.0, 0.25, 0)
	check(math.abs(fast.hipL.x) > math.abs(slow.hipL.x), "hizli kosuda adim buyumeli")
	local idle = WalkCycle.sample(0.0, 0.25, 1.0)
	check(idle.hipL == nil or math.abs(idle.hipL.x) < 1e-9, "dururken bacak salinimi olmamali")
end)

-- Kullanıcı şikayeti: "oyuncu animasyonları çalışmıyor". Sebebi iki taneydi:
-- (1) şut hiç tetiklenmiyordu (bkz. menzil testleri), (2) karakter yalnızca şut
-- beklerken pozlanıyordu; yürürken/dururken kimse poz yazmıyordu. PlayerPose bu
-- boşluğu kapatır ve zamanı adım fazına çevirir (ayaklar yerde kaymaz).
test("PlayerPose: yuruyus fazini mesafeden uretir, tam adimda faz sifirlanir", function()
	near(PlayerPose.phaseAt(0, 5.0), 0, 1e-12, "t=0 faz 0")
	near(PlayerPose.phaseAt(WalkCycle.STRIDE / 5.0, 5.0), 0, 1e-9,
		"bir tam adim atilinca faz yeniden 0 olmali")
	near(PlayerPose.phaseAt(0.5 * WalkCycle.STRIDE / 5.0, 5.0), 0.5, 1e-9, "yarim adimda faz 0.5")
	check(PlayerPose.phaseAt(-3, 5.0) >= 0 and PlayerPose.phaseAt(-3, 5.0) < 1,
		"negatif zamanda faz 0..1 araliginda kalmali")
	check(PlayerPose.phaseAt(1.7, 0) == 0, "dururken faz ilerlememeli")
end)

test("PlayerPose: hiz artinca adim buyur, dururken atletik durusa duser", function()
	near(PlayerPose.strideAmp(0), 0, 1e-12, "dururken genlik 0")
	near(PlayerPose.strideAmp(PlayerPose.FULL_STRIDE_SPEED), 1, 1e-12, "tam hizda genlik 1")
	check(PlayerPose.strideAmp(99) == 1, "genlik 1'in ustune cikmamali")
	check(PlayerPose.strideAmp(-4) == PlayerPose.strideAmp(4), "geri geri kosmak genligi degistirmemeli")

	local slow = PlayerPose.walk(0.4, 2.0)
	local fast = PlayerPose.walk(0.4, 7.0)
	check(slow ~= nil and fast ~= nil, "walk poz uretmedi")
	check(math.abs(fast.hipL.x) > math.abs(slow.hipL.x),
		"hizli kosuda kalca salinimi buyumeli")

	local stand = PlayerPose.walk(0.4, 0)
	check(stand.hipL == nil or math.abs(stand.hipL.x) < 1e-9,
		"dururken bacak salinimi olmamali")
	-- Duruş heykel gibi olmasın: dizler kırık, gövde alçalmış, nefes alıyor
	check(stand.kneeL ~= nil and stand.kneeL.x > 0.15,
		"durusta dizler kirik degil (heykel gibi): " .. tostring(stand.kneeL and stand.kneeL.x))
	check(stand.rootOffset.y < -0.02,
		"durusta govde alçalmali: " .. tostring(stand.rootOffset.y))
	local breathA = PlayerPose.ready(0.0, 0)
	local breathB = PlayerPose.ready(1.0, 0)
	check(math.abs(breathA.rootOffset.y - breathB.rootOffset.y) > 1e-6,
		"durus zamanla degismiyor: nefes animasyonu yok")
	-- ready(hızlı) -> yürüyüşe düşmeli (çağıran tarafın hızı kıyaslaması gerekmez)
	check(PlayerPose.ready(0.4, 7.0).hipL ~= nil and math.abs(PlayerPose.ready(0.4, 7.0).hipL.x) > 1e-9,
		"ready hizli hareketi yuruyuse devretmedi")
end)

test("PlayerPose pozlari R15 karakterine uygulanabiliyor (animasyon gercekten yaziliyor)", function()
	local mockEnv = RobloxMock.install() -- global Instance/CFrame/Workspace'ü kurar
	local joints = { "Waist", "Neck", "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee",
		"RightAnkle", "LeftShoulder", "LeftElbow", "RightShoulder", "RightElbow" }
	local model = Instance.new("Model")
	model.Name = "R15Tester"
	model.Parent = mockEnv.workspace
	for _, name in ipairs(joints) do
		local motor = Instance.new("Motor6D")
		motor.Name = name
		motor.Transform = CFrame.new()
		motor.Parent = model
	end
	local HP = __load("shared/Anim/HumanoidPose")
	check(HP.supported(model), "R15 karakter desteklenmiyor sayildi")

	local leftHip = model:FindFirstChild("LeftHip")
	check(HP.apply(model, PlayerPose.walk(0.10, 6.0)), "apply false döndü")
	local first = { leftHip.Transform:GetComponents() }
	HP.apply(model, PlayerPose.walk(0.35, 6.0))
	local second = { leftHip.Transform:GetComponents() }
	check(#first == 12 and #second == 12, "Motor6D.Transform yazilmadi (GetComponents 12 deger vermedi)")
	local moved = 0
	for i = 1, 12 do
		if math.abs(first[i] - second[i]) > 1e-9 then
			moved = moved + 1
		end
	end
	check(moved > 0, "iki farkli karede kalca pozu ayni: animasyon ilerlemiyor")
	-- Üçüncü kare de farklı olmalı: tek seferlik bir sıçrama değil, döngü.
	HP.apply(model, PlayerPose.walk(0.60, 6.0))
	local third = { leftHip.Transform:GetComponents() }
	local moved2 = 0
	for i = 1, 12 do
		if math.abs(third[i] - second[i]) > 1e-9 then
			moved2 = moved2 + 1
		end
	end
	check(moved2 > 0, "ucuncu karede kalca pozu degismedi: dongu donmuyor")

	HP.clear(model)
	local cleared = model:FindFirstChild("LeftKnee").Transform
	check(cleared ~= nil, "clear sonrasi Transform okunamiyor")
end)

-- Studio'daki avatar R15 olmak zorunda değil: R6'da eklem adları farklıdır
-- ("Left Hip", "Neck" ...) ve bel/diz/dirsek yoktur. Eski kod R6'da SESSİZCE
-- hiçbir şey yapmıyordu -> "animasyonlar çalışmıyor" şikayetinin bir nedeni daha.
test("HumanoidPose R6 karakterde de calisiyor (avatar R15 degilse de animasyon var)", function()
	local mockEnv = RobloxMock.install()
	local HP = __load("shared/Anim/HumanoidPose")
	local identity = { 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }
	local function movedFrom(comps)
		if not comps then
			return -1
		end
		local moved = 0
		for i = 1, 12 do
			if math.abs(comps[i] - identity[i]) > 1e-9 then
				moved = moved + 1
			end
		end
		return moved
	end

	local r6 = Instance.new("Model")
	r6.Name = "R6Tester"
	r6.Parent = mockEnv.workspace
	for _, name in ipairs({ "Neck", "Left Shoulder", "Right Shoulder", "Left Hip", "Right Hip" }) do
		local motor = Instance.new("Motor6D")
		motor.Name = name
		motor.Transform = CFrame.new()
		motor.Parent = r6
	end
	check(HP.supported(r6), "R6 eklem adlari taninmadi: R6 avatarlarda animasyon hic calismaz")
	check(HP.apply(r6, PlayerPose.walk(0.25, 5.5)), "R6 apply false dondu")
	check(movedFrom({ r6:FindFirstChild("Right Hip").Transform:GetComponents() }) > 0,
		"R6 kalca eklemi yazilmadi")
	check(movedFrom({ r6:FindFirstChild("Left Shoulder").Transform:GetComponents() }) > 0,
		"R6 omuz eklemi yazilmadi")

	-- Regresyon: R15 hâlâ tam çözünürlükte çalışıyor (12 eklem)
	local r15 = Instance.new("Model")
	r15.Name = "R15Tester2"
	r15.Parent = mockEnv.workspace
	for _, name in ipairs({ "Waist", "Neck", "LeftHip", "LeftKnee", "LeftAnkle", "RightHip",
		"RightKnee", "RightAnkle", "LeftShoulder", "LeftElbow", "RightShoulder", "RightElbow" }) do
		local motor = Instance.new("Motor6D")
		motor.Name = name
		motor.Transform = CFrame.new()
		motor.Parent = r15
	end
	check(HP.supported(r15), "R15 desteklenmiyor sayildi (regresyon)")
	HP.apply(r15, PlayerPose.walk(0.25, 5.5))
	check(movedFrom({ r15:FindFirstChild("LeftKnee").Transform:GetComponents() }) > 0,
		"R15 diz eklemi yazilmadi (R6 yoluna dusmus olabilir)")

	-- Eklemi hiç olmayan model desteklenmemeli (sessizce false)
	local empty = Instance.new("Model")
	empty.Name = "NoJoints"
	empty.Parent = mockEnv.workspace
	check(not HP.supported(empty), "eklemi olmayan model destekleniyor sayildi")
end)

test("kaleci bosta heykel degil: nefes + salinim animasyonu var", function()
	local a = KeeperAnim.idle(0.0)
	local b = KeeperAnim.idle(1.3)
	local c = KeeperAnim.idle(2.6)
	check(a ~= nil and a.rootOffset ~= nil, "idle poz uretmedi")
	check(a.root ~= nil and a.spine ~= nil and a.hipL ~= nil, "idle poz eklem icermiyor")
	check(math.abs(a.rootOffset.y - b.rootOffset.y) > 1e-9, "nefes animasyonu yok (y sabit)")
	check(math.abs(a.rootOffset.x - b.rootOffset.x) > 1e-9, "agirlik salinimi yok (x sabit)")
	check(math.abs(b.rootOffset.x - c.rootOffset.x) > 1e-12, "salinim devam etmiyor")
	-- İki farklı zamanda üretilen pozlar birebir aynı olmamalı
	local sameAll = true
	for _, key in ipairs({ "x", "y", "z" }) do
		if math.abs(a.rootOffset[key] - b.rootOffset[key]) > 1e-12 then
			sameAll = false
		end
	end
	check(not sameAll, "idle poz zamandan bagimsiz: kaleci donmus gorunur")
	-- Dalış animasyonundan ayrışmalı (idle = hazır, dalış = yana uzanma)
	local dive = KeeperAnim.new({ dz = 1.2, height = 0.5 }):sample(0.45).pose
	check(math.abs(dive.spine.y - a.spine.y) > 1e-6 or math.abs(dive.rootOffset.x - a.rootOffset.x) > 1e-6,
		"idle ile dalis pozu ayirt edilemiyor")
end)

test("poz karisimi: blend uclarda dogru sonuc verir", function()
	local a = { hipR = Pose.joint(1, 0, 0) }
	local b = { hipR = Pose.joint(-1, 0.4, 0) }
	near(Pose.blend(a, b, 0).hipR.x, 1, 1e-9, "blend 0")
	near(Pose.blend(a, b, 1).hipR.x, -1, 1e-9, "blend 1")
	near(Pose.blend(a, b, 0.5).hipR.x, 0, 1e-9, "blend 0.5")
end)

test("animasyon deterministik: ayni girdi ayni pozu verir", function()
	local function sampleAll()
		local k = KickAnim.new({ ballHeight = 0.8, ballLateral = -0.3, charge = 0.6 })
		local out = {}
		for i = 0, 20 do
			local pose = k:sample(i * 0.031).pose
			out[#out + 1] = string.format("%.6f", pose.spine.x + pose.hipL.x + pose.kneeR.x)
		end
		return table.concat(out, ",")
	end
	check(sampleAll() == sampleAll(), "ayni girdi farkli poz uretti")
end)

test("sutcu: temas aninda sut cikar, oncesinde degil", function()
	local sim2 = Sim.new({ seed = 7 })
	sim2.ball:setState(Vec3.new(20, 0.11, 0.9), Vec3.new(0, 0, 0), Vec3.new(0, 0, 0))
	local striker = Striker.new(Config, { side = 1, pos = Vec3.new(19.85, 0, 0.9) })

	striker:step(1 / 60, sim2.ball) -- top ayak mesafesinde -> savurma baslar
	check(striker:isKicking(), "yakin topta sut baslamadi")

	local contactAt = nil
	for i = 1, 120 do
		local ev = striker:step(1 / 60, sim2.ball)
		if ev and ev.type == "shoot" then
			contactAt = i / 60
			break
		end
	end
	check(contactAt ~= nil, "sut olayi hic gelmedi")
	near(contactAt, KickAnim.CONTACT_TIME, 0.02, "temas zamani")
	check(contactAt > 0.18, "top savurma tamamlanmadan ayrildi")
end)

test("sutcu: uzaktaki topa yurur, mesafe kapaniyor", function()
	local sim2 = Sim.new({ seed = 7 })
	sim2.ball:setState(Vec3.new(24, 0.11, 2.0), Vec3.new(0, 0, 0), Vec3.new(0, 0, 0))
	local striker = Striker.new(Config, { side = 1, pos = Vec3.new(18, 0, 0) })

	local function dist()
		local dx = sim2.ball.pos.x - striker.pos.x
		local dz = sim2.ball.pos.z - striker.pos.z
		return math.sqrt(dx * dx + dz * dz)
	end

	local startDist = dist()
	local shotEarly = false
	for _ = 1, 60 do
		local ev = striker:step(1 / 60, sim2.ball)
		if ev then
			shotEarly = true
		end
	end
	check(not shotEarly, "sutcu ayak mesafesine gelmeden sut cekti")
	check(dist() < startDist - 3, "sutcu topa yaklasmadi: " .. string.format("%.2f -> %.2f", startDist, dist()))
end)

test("sutcu: ardisik sutlarda hedef degisir (kalecinin isi zorlasir)", function()
	local sim2 = Sim.new({ seed = 7 })
	local striker = Striker.new(Config, { side = 1, pos = Vec3.new(20, 0, 0) })

	local targets = {}
	for round = 1, 3 do
		sim2.ball:setState(Vec3.new(20, 0.11, 0.3), Vec3.new(0, 0, 0), Vec3.new(0, 0, 0))
		striker.pos = Vec3.new(19.8, 0, 0.3)
		striker.kick = nil
		striker.kickT = 0
		striker.cooldown = 0
		striker:step(1 / 60, sim2.ball)
		check(striker:isKicking(), "sut baslamadi (tur " .. round .. ")")
		targets[round] = { y = striker.target.y, z = striker.target.z }
		-- animasyonu bitir
		for _ = 1, 60 do
			striker:step(1 / 60, sim2.ball)
		end
	end
	local dz = math.abs(targets[1].z - targets[2].z)
	check(dz > 2.0, "ardisik sutlar ayni koseye gitti: " .. string.format("%.2f", dz))
	check(math.abs(targets[1].y - targets[2].y) > 0.6, "ardisik sutlar ayni yukseklige gitti")
end)

print("\n== 10. Sunucu dongusu + animasyon (sahte Roblox ortaminda) ==")

-- SimLoop'u mock icinde calistir, Heartbeat'i elle sur, animasyonu olc
local liveMock = nil
local live = nil

test("sunucu dongusu kurulup 24 s boyunca hatasiz calisiyor", function()
	liveMock = RobloxMock.install()
	local installOk, installErr = pcall(function()
		local chunk = assert(load(INSTALLER_SRC, "@FootballSim_Install"))
		chunk()
	end)
	check(installOk, "kurulum calismadi: " .. tostring(installErr))

	-- Yeni varsayilan: NPC sutcu kapali (sutu oyuncu atar). Bu test NPC'nin
	-- yurume/sut animasyonunu da olctugu icin demo kipini BILEREK acar ve sahneyi
	-- SimLoop calismadan ONCE yeniden kurar (strikerModel acilista baglanir).
	local liveCfg = require(liveMock.replicatedStorage.Shared.Config)
	liveCfg.ANIM.strikerEnabled = true
	local liveSB = require(liveMock.replicatedStorage.Shared.World.SceneBuilder)
	liveSB.build({})

	local server = liveMock.serverScriptService:FindFirstChild("Server")
	check(server ~= nil, "Server klasoru yok")
	local simLoop = server:FindFirstChild("SimLoop")
	check(simLoop ~= nil and type(simLoop.Source) == "string", "SimLoop scripti yok")

	local ok, err = pcall(function()
		local chunk = assert(load(simLoop.Source, "@SimLoop"))
		chunk()
	end)
	check(ok, "SimLoop calismadi: " .. tostring(err))

	local ws = liveMock.workspace
	local ball = ws:FindFirstChild("MatchBall")
	local pitch = ws:FindFirstChild("FootballPitch")
	local keeperFolder = pitch and pitch:FindFirstChild("Goalkeeper")
	local strikerFolder = pitch and pitch:FindFirstChild("Striker")
	check(ball ~= nil and keeperFolder ~= nil and strikerFolder ~= nil, "mac nesneleri yok")
	local rig = keeperFolder:FindFirstChild("Rig")
	local strikerRig = strikerFolder:FindFirstChild("Rig")
	check(rig ~= nil and strikerRig ~= nil, "iskeletler yok")

	local gloveL = rig:FindFirstChild("GloveL")
	local torso = rig:FindFirstChild("Torso")
	local thigh = strikerRig:FindFirstChild("ThighL")
	check(gloveL and torso and thigh, "iskelet parcalari eksik")

	live = {
		ball = ball,
		rig = rig,
		strikerRig = strikerRig,
		maxBallSpeed = 0,
		maxGloveZ = 0,
		maxGloveY = -1e9,
		minTorsoY = 1e9,
		diveEvents = 0,
		wasDiving = false,
		strikerMoved = 0,
		frames = 0,
		thighStart = { x = thigh.CFrame.pos.X, y = thigh.CFrame.pos.Y, z = thigh.CFrame.pos.Z },
	}

	local dt = 1 / 60
	local prevX, prevZ = ball.CFrame.pos.X, ball.CFrame.pos.Z
	local glove = gloveL.CFrame.pos
	local totalFrames = math.floor(24 / dt)

	local stepOk, stepErr = pcall(function()
		for _ = 1, totalFrames do
			liveMock.stepHeartbeat(dt * 1.5, dt) -- tam 1 kare
			live.frames = live.frames + 1

			local bpos = ball.CFrame.pos
			local dx = bpos.X - prevX
			local dz = bpos.Z - prevZ
			local speed = math.sqrt(dx * dx + dz * dz) / dt / 3.5714
			if speed > live.maxBallSpeed then
				live.maxBallSpeed = speed
			end
			prevX, prevZ = bpos.X, bpos.Z

			-- Olcumler METRE cinsinden (mock CFrame stud tutar)
			local k = 1 / 3.5714
			local gp = gloveL.CFrame.pos
			local absZ = math.abs(gp.Z) * k -- kale cizgisi z = 0
			local gy = gp.Y * k
			if absZ > live.maxGloveZ then
				live.maxGloveZ = absZ
			end
			if gy > live.maxGloveY then
				live.maxGloveY = gy
			end
			if absZ > 1.0 and not live.wasDiving then
				live.diveEvents = live.diveEvents + 1
				live.wasDiving = true
			elseif absZ < 0.5 then
				live.wasDiving = false
			end
			local tp = torso.CFrame.pos
			if tp.Y * k < live.minTorsoY then
				live.minTorsoY = tp.Y * k
			end
			local th = thigh.CFrame.pos
			local d = (math.abs(th.X - live.thighStart.x) + math.abs(th.Y - live.thighStart.y) + math.abs(th.Z - live.thighStart.z)) * k
			if d > live.strikerMoved then
				live.strikerMoved = d
			end
		end
	end)
	check(stepOk, "Heartbeat dongusu hata verdi: " .. tostring(stepErr))
	check(live.frames == totalFrames, "dongu tamamlanmadi")
end)

test("sutcu maci kendi kendine oynuyor: top 18 m/s uzeri hizla sutlaniyor", function()
	check(live ~= nil, "mac calismadi")
	check(live.maxBallSpeed > 18,
		"sut hizi dusuk: " .. string.format("%.1f m/s", live.maxBallSpeed))
end)

test("sutcu iskeleti gercekten hareket ediyor (yurume + sut)", function()
	check(live.strikerMoved > 0.10,
		"sutcu iskeleti hic oynamadi: " .. string.format("%.3f", live.strikerMoved))
end)

test("kaleci animasyonu: yana dalis ve yuksek top icin farkli hareketler", function()
	check(live.maxGloveZ > 1.0,
		"kaleci yana uzandi mi? max |z| = " .. string.format("%.2f stud", live.maxGloveZ))
	check(live.maxGloveY > 1.85,
		"kaleci yuksek topa ziplamadi mi? max el y = " .. string.format("%.2f m", live.maxGloveY))
	check(live.diveEvents >= 1, "dalis olayi sayisi: " .. tostring(live.diveEvents))
end)

test("kaleci modeli dalista alcaliyor (govde yuksekligi degisiyor)", function()
	check(live.minTorsoY < 1.05,
		"govde hic alcalmadi: min y = " .. string.format("%.2f m", live.minTorsoY))
end)


print("\n== 11. İstemci (BallView) — sahte Roblox istemci ortamı ==")

--[[ Grup 11/12 neden var?
	Kurulum dosyası, SceneBuilder ve SimLoop zaten sahte Roblox ortamında
	çalıştırılıyordu; ama İSTEMCİ scripti (BallView) hiç çalıştırılmıyordu:
	342 satır kod yalnızca sözdizimi denetiminden geçiyordu. Bu yüzden
	"şut tuşu bırakılınca hiçbir şey olmuyor" gibi bir hata testte yakalanamazdı.
	Aşağıda istemci gerçek Roblox akışıyla çalıştırılıyor: karakter + kamera +
	UserInputService + RenderStepped + RemoteEvent döngüsü (FireServer ->
	OnServerEvent). ]]

local STUDS_PER_METER = 3.5714

-- Tam dünya: kurulum dosyası + SimLoop (sunucu) + BallView (istemci)
local function bootWorld(opts)
	opts = opts or {}
	local mock = RobloxMock.install()
	local logs = {}
	local realPrint = print
	print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring(select(i, ...))
		end
		logs[#logs + 1] = table.concat(parts, " ")
	end

	local okInstall, errInstall = pcall(function()
		local chunk = assert(load(INSTALLER_SRC, "@FootballSim_Install"))
		chunk()
	end)

	local server = mock.serverScriptService:FindFirstChild("Server")
	local simLoop = server and server:FindFirstChild("SimLoop")
	local okServer, errServer = false, "SimLoop bulunamadi"
	if simLoop then
		okServer, errServer = pcall(function()
			local chunk = assert(load(simLoop.Source, "@SimLoop"))
			chunk()
		end)
	end

	-- Şutçu NPC'yi kapat: oyuncunun kendi şutunu izole ölçmek için
	if opts.striker == false then
		local sharedConfig = require(mock.replicatedStorage.Shared.Config)
		sharedConfig.ANIM.strikerEnabled = false
	end

	-- Prosedürel pozlamayı kapat (Config.ANIM.poseHumanoid = false kaçış kapağı).
	-- BallView bu bayrağı YÜKLENİRKEN okuduğu için istemciden önce değişmeli.
	if opts.poseHumanoid == false then
		local sharedConfig = require(mock.replicatedStorage.Shared.Config)
		sharedConfig.ANIM.poseHumanoid = false
	end

	local okClient, errClient = true, nil
	if opts.client ~= false then
		local clientFolder = mock.starterPlayerScripts:FindFirstChild("Client")
		local ballView = clientFolder and clientFolder:FindFirstChild("BallView")
		if not ballView then
			okClient, errClient = false, "StarterPlayerScripts.Client.BallView yok"
		else
			okClient, errClient = pcall(function()
				local chunk = assert(load(ballView.Source, "@BallView"))
				chunk()
			end)
		end
	end

	print = realPrint

	local world = {
		mock = mock,
		logs = logs,
		installOk = okInstall,
		installErr = errInstall,
		serverOk = okServer,
		serverErr = errServer,
		clientOk = okClient,
		clientErr = errClient,
	}
	world.ball = mock.workspace:FindFirstChild("MatchBall")
	world.ballStart = world.ball and world.ball.Position
	world.hud = mock.localPlayer:FindFirstChild("PlayerGui")
		and mock.localPlayer:FindFirstChild("PlayerGui"):FindFirstChild("FootballHud")
	world.hrp = mock.localPlayer.Character:FindFirstChild("HumanoidRootPart")
	world.humanoid = mock.localPlayer.Character:FindFirstChild("Humanoid")
	world.camera = mock.camera
	world.remotes = mock.replicatedStorage:FindFirstChild("Remotes")
	world.kickRemote = world.remotes and world.remotes:FindFirstChild("Kick")
	world.resetRemote = world.remotes and world.remotes:FindFirstChild("ResetBall")
	world.stateRemote = world.remotes and world.remotes:FindFirstChild("MatchState")
	world.stepped = 0
	return world
end

-- Hem sunucu (Heartbeat) hem istemci (RenderStepped) karelerini birlikte sür.
local function stepWorld(world, seconds, dt)
	dt = dt or 1 / 60
	local frames = math.floor(seconds / dt)
	local errs = {}
	local ball = world.ball
	local prev = ball and ball.Position
	local maxSpeed, launches, prevSpeed, frameIndex = 0, 0, 0, 0
	for _ = 1, frames do
		frameIndex = frameIndex + 1
		local ok, err = pcall(function()
			world.mock.runService.Heartbeat:Fire(dt)
			world.mock.runService.RenderStepped:Fire(dt)
			-- Gerçek Roblox'ta Animator bu noktada (RenderStepped SONRASI,
			-- PreSimulation ÖNCESİ) eklem Transform'unu kendi pozlarıyla ezer.
			-- Prosedürel poz ancak PreSimulation içinde yazılırsa görünür kalır.
			-- Zamanlama testi bunu zorunlu kılar (mock.animatorOverwrite = true);
			-- diğer testlerde varsayılan animator davranışı taklit edilmez.
			local localChar = world.mock.localPlayer.Character
			if world.mock.animatorOverwrite and world.clientOk ~= false and localChar then
				for _, obj in ipairs(localChar:GetChildren()) do
					if obj:IsA("Motor6D") or obj:IsA("AnimationConstraint") then
						obj.Transform = CFrame.new()
					end
				end
			end
			world.mock.runService.PreSimulation:Fire(dt)
			world.mock.runService.Stepped:Fire(dt)
		end)
		if not ok then
			errs[#errs + 1] = tostring(err)
		end
		if ball then
			local cur = ball.Position
			local dx, dy, dz = cur.X - prev.X, cur.Y - prev.Y, cur.Z - prev.Z
			local speed = math.sqrt(dx * dx + dy * dy + dz * dz) / dt / STUDS_PER_METER
			-- Gol sonrasi sifirlama topu baslangica ISINLAR (tek karede ~30 m):
			-- bu fiziksel bir hiz degil, o kareyi olcumlere saymiyoruz.
			local teleport = speed > 60
			if not teleport then
				if speed > maxSpeed then
					maxSpeed = speed
				end
				-- Ilk karede "onceki hiz" bilinmiyor (pencere disinda ucu yor):
				-- launch sayaci ikinci kareden itibaren anlamlidir.
				if frameIndex > 1 and speed - prevSpeed > 3 then
					launches = launches + 1
				end
			end
			prevSpeed = teleport and 0 or speed
			prev = cur
		end
	end
	world.stepped = world.stepped + seconds
	return { frames = frames, errors = errs, maxSpeed = maxSpeed, launches = launches }
end

-- Oyuncuyu topun `behind` metre gerisine, kaleye bakar şekilde yerleştir.
local function placePlayerAtBall(world, behind)
	behind = behind or 0.8
	local bp = world.ball.Position
	local pos = Vector3.new(bp.X - behind * STUDS_PER_METER, bp.Y, bp.Z)
	world.hrp.CFrame = CFrame.lookAt(pos, pos + Vector3.new(10, 0, 0))
	world.hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	return pos
end

-- Topu bilinen bir duruma al: gol sonrasi 2.4 s'lik reset zamanlayicisini
-- bosalt, ResetBall remote'uyla baslangica isinla, kisa sure oturmasini bekle.
local function settleBall(world)
	stepWorld(world, 2.6)
	if world.resetRemote then
		world.resetRemote.OnServerEvent:Fire(nil)
	end
	local res = stepWorld(world, 0.4)
	return res
end

local function hintText(world)
	local label = world.hud and world.hud:FindFirstChild("Hint")
	return label and label.Text or nil
end

local function findRemoteCall(world, fromIndex, remoteName, direction)
	for i = math.max(1, fromIndex or 1), #world.mock.remoteLog do
		local entry = world.mock.remoteLog[i]
		if entry.name == remoteName and (not direction or entry.direction == direction) then
			return entry, i
		end
	end
	return nil
end

local clientWorld = nil

test("istemci scripti sahte Roblox ortaminda hatasiz calisiyor", function()
	clientWorld = bootWorld({ striker = false })
	check(clientWorld.installOk, "kurulum dosyasi hata verdi: " .. tostring(clientWorld.installErr))
	check(clientWorld.serverOk, "SimLoop hata verdi: " .. tostring(clientWorld.serverErr))
	check(clientWorld.clientOk, "BallView (istemci) hata verdi: " .. tostring(clientWorld.clientErr))
	check(clientWorld.ball ~= nil, "MatchBall yok")
	check(clientWorld.remotes ~= nil, "ReplicatedStorage.Remotes yok (istemci bunu bekliyor)")
	check(clientWorld.kickRemote ~= nil and clientWorld.resetRemote ~= nil and clientWorld.stateRemote ~= nil,
		"remote'lardan biri yok: Kick/ResetBall/MatchState")
end)

test("istemci HUD + top kopyasi + nisan isareti kuruyor, sunucu topunu gizliyor", function()
	check(clientWorld ~= nil and clientWorld.clientOk, "istemci calismadi")
	local mock = clientWorld.mock
	local hud = clientWorld.hud
	check(hud ~= nil, "PlayerGui.FootballHud yok")
	check(hud:FindFirstChild("Hint") ~= nil, "Hint etiketi yok")
	check(hud:FindFirstChild("ChargeBar") ~= nil, "ChargeBar yok")
	check(hud:FindFirstChild("Score") ~= nil, "Score etiketi yok")
	local bar = hud:FindFirstChild("ChargeBar")
	check(bar:FindFirstChild("ChargeFill") ~= nil, "ChargeFill yok")
	check(bar.Visible == false, "guc bari baslangicta gorunur olmamali")

	local serverBall = clientWorld.ball
	check(serverBall.LocalTransparencyModifier == 1,
		"sunucu topu lokal gizlenmedi (LocalTransparencyModifier=" ..
		tostring(serverBall.LocalTransparencyModifier) .. ")")

	local visual = mock.workspace:FindFirstChild("MatchBallVisual")
	check(visual ~= nil, "istemci top kopyasi (MatchBallVisual) yok")
	check(visual.Anchored == true, "kopya Anchored degil")
	check(visual.CanCollide == false, "kopya CanCollide=true (fizigi bozar)")
	check(visual.CanQuery == false, "kopya CanQuery=true (isınları bozar)")
	check(visual.LocalTransparencyModifier == 0, "kopya gorunmez kaldi")
	check(visual:FindFirstChildOfClass("Trail") ~= nil, "kopyada Trail yok")

	check(mock.workspace:FindFirstChild("AimMarker") ~= nil, "nisan isareti (AimMarker) yok")

	local ballCount = 0
	for _, child in ipairs(mock.workspace:GetChildren()) do
		if child.Name == "MatchBall" then
			ballCount = ballCount + 1
		end
	end
	check(ballCount == 1, "MatchBall cogaldi: " .. tostring(ballCount))
end)

-- Kullanıcı isteği: oyuncu 1. ŞAHIS olsun. Bu kipte kamerayı Roblox sürer
-- (Humanoid.CameraMode = LockFirstPerson başı kilitler, Head'i gizler); istemci
-- CFrame YAZMAMALI, yoksa Roblox ile yarışır ve görüntü titrer.
test("kamera varsayilan olarak 1. sahis: Roblox surer, istemci CFrame yazmaz", function()
	local res = stepWorld(clientWorld, 1.0)
	check(#res.errors == 0, "kare dongusu hata verdi: " .. table.concat(res.errors, " | "))
	check(clientWorld.humanoid ~= nil, "world.humanoid yok")
	check(clientWorld.humanoid.CameraMode == "CameraMode.LockFirstPerson",
		"1. sahis kilidi acilmadi (Humanoid.CameraMode): " .. tostring(clientWorld.humanoid.CameraMode))
	check(clientWorld.camera.CameraType == "CameraType.Custom",
		"1. sahista CameraType Custom olmali (kamerayi Roblox surer): " ..
		tostring(clientWorld.camera.CameraType))
	-- Nişan 1. şahısta karakterin baktığı yöndür ve yine kale düzlemine düşer
	local marker = clientWorld.mock.workspace:FindFirstChild("AimMarker")
	check(marker ~= nil, "workspace.AimMarker yok")
	local mp = marker.Position
	local goalPlane = 52.5 * STUDS_PER_METER
	check(math.abs(mp.X - goalPlane) < 0.5,
		"1. sahista nisan kale duzleminde degil: x=" .. string.format("%.1f", mp.X))
	check(math.abs(mp.Z) <= 3.3 * STUDS_PER_METER + 0.01, "nisan z siniri asildi")
	check(mp.Y >= 0.25 * STUDS_PER_METER - 0.01 and mp.Y <= 2.3 * STUDS_PER_METER + 0.01,
		"nisan y siniri asildi")
	check(marker.Transparency < 1, "1. sahista nisan yok sayildi (computeAim nil dondu)")
	-- HUD hangi kipte olduğumuzu söylemeli
	local text = hintText(clientWorld)
	check(text:find("1. şahıs", 1, true) ~= nil, "HUD kamera kipini gostermiyor: " .. tostring(text))

	-- 1. şahısta istemci kameraya DOKUNMAMALI: Roblox'un baş-kilitli kamerasını
	-- her karede ezmek görüntüyü titretir (ve ilk şahıs hissiyi bozar).
	clientWorld.camera.CFrame = CFrame.lookAt(Vector3.new(1234, 567, 89), Vector3.new(2000, 567, 89))
	stepWorld(clientWorld, 0.3)
	local kept = clientWorld.camera.CFrame.Position
	check(math.abs(kept.X - 1234) < 1e-6, string.format(
		"1. sahista istemci kamera CFrame'ini ezdi (x=%.1f, beklenen 1234): Roblox'un kamerasiyla yarisir",
		kept.X))
end)

-- Animasyonların "çalışmıyor" gibi görünmesinin bir nedeni de kameranın 30 stud
-- geride / 20 stud yukarıda olmasıydı: karakter ekranda birkaç piksel kalıyordu.
test("C ile 3. sahisa geciliyor: kamera omuz ustunde ve YAKIN (animasyon gorunur)", function()
	clientWorld.mock.pressKey("C")
	local res = stepWorld(clientWorld, 1.0)
	check(#res.errors == 0, "kare dongusu hata verdi: " .. table.concat(res.errors, " | "))
	check(clientWorld.camera.CameraType == "CameraType.Scriptable",
		"3. sahista CameraType Scriptable degil: " .. tostring(clientWorld.camera.CameraType))
	check(clientWorld.humanoid.CameraMode == "CameraMode.Classic",
		"3. sahista CameraMode Classic degil: " .. tostring(clientWorld.humanoid.CameraMode))
	local camPos = clientWorld.camera.CFrame.Position
	local hrpPos = clientWorld.hrp.Position
	check(camPos.X < hrpPos.X, "kamera karakterin onunde (x=" .. string.format("%.1f", camPos.X) .. ")")
	check(camPos.Y > hrpPos.Y, "kamera yukarida degil")
	check(clientWorld.camera.CFrame.LookVector.X > 0.2,
		"kamera kaleye (+x) bakmiyor: LookVector.X=" ..
		string.format("%.2f", clientWorld.camera.CFrame.LookVector.X))
	-- YAKINLIK: karakter ekranda görünür büyüklükte olmalı
	local dx, dy, dz = camPos.X - hrpPos.X, camPos.Y - hrpPos.Y, camPos.Z - hrpPos.Z
	local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
	check(dist < 14.0, string.format(
		"3. sahis kamerasi cok uzak: karakter %.1f stud otede (animasyonlar gorunmez, eski hata 36 stud)", dist))
	check(dist > 3.0, string.format("3. sahis kamerasi karakterin icinde: %.1f stud", dist))
	local text = hintText(clientWorld)
	check(text:find("3. şahıs", 1, true) ~= nil, "HUD 3. sahis kipini gostermiyor: " .. tostring(text))

	clientWorld.mock.pressKey("C") -- geri al
	stepWorld(clientWorld, 0.3)
	check(clientWorld.camera.CameraType == "CameraType.Custom",
		"C ikinci basinca 1. sahisa geri donmedi: " .. tostring(clientWorld.camera.CameraType))
	check(clientWorld.humanoid.CameraMode == "CameraMode.LockFirstPerson",
		"1. sahis kilidi geri gelmedi")
end)

-- Roblox'un varsayılan `Animate` LocalScript'i her karede Motor6D.Transform'a
-- kendi pozunu yazar; bizim prosedürel pozumuzu EZER. Studio'da "animasyonlar
-- çalışmıyor" görünmesinin asıl nedeni bu. Pozlama çalışıyorsa varsayılan
-- kapatılır; çalışmıyorsa AÇIK KALIR (karakter heykele dönmesin).
test("prosedurel poz calisirken varsayilan Animate kapatiliyor (yoksa pozu eziyor)", function()
	local w = bootWorld({ striker = false })
	check(w.installOk and w.serverOk and w.clientOk,
		"dunya kurulamadi: " .. tostring(w.installErr or w.serverErr or w.clientErr))
	local char = w.mock.localPlayer.Character
	local animate = char:FindFirstChild("Animate")
	check(animate ~= nil, "mock karakterde Animate LocalScript yok (test zemini hazir degil)")
	-- Not: BallView yüklenirken bindCharacter çalıştığı için başlangıç durumu
	-- zaten "kapalı"dır; ölçülen şey kareler boyunca kapalı KALMASI.

	local res = stepWorld(w, 0.3)
	check(#res.errors == 0, "kare dongusu hata verdi: " .. table.concat(res.errors, " | "))
	check(animate.Disabled == true,
		"prosedurel poz calisirken Animate kapatilmadi: Roblox kendi pozunu yazip bizimkini ezer (animasyon gorunmez)")

	-- Kapatmak yetmez: eklemler gerçekten yazılıyor olmalı
	local knee = char:FindFirstChild("LeftKnee")
	check(knee ~= nil, "LeftKnee eklemi yok")
	local identity = { 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }
	local comps = { knee.Transform:GetComponents() }
	local moved = 0
	for i = 1, 12 do
		if math.abs(comps[i] - identity[i]) > 1e-9 then
			moved = moved + 1
		end
	end
	check(moved > 0, "Animate kapatildi ama diz eklemi kimlikte kaldi: poz yazilmiyor")
end)

test("pozlanamayan karakterde varsayilan animasyon ACIK kaliyor (heykel olmasin)", function()
	local w = bootWorld({ striker = false })
	check(w.clientOk, "istemci calismadi: " .. tostring(w.clientErr))
	local original = w.mock.localPlayer.Character

	-- Eklemleri OLMAYAN bir karakter (ör. özel rig): pozlama çalışamaz
	local char = Instance.new("Model")
	char.Name = "NoJointsChar"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(0, 3, 0) -- mock'ta Position CFrame'den türer
	root.Parent = char
	local hum = Instance.new("Humanoid")
	hum.Parent = char
	local animate = Instance.new("LocalScript")
	animate.Name = "Animate"
	animate.Disabled = false
	animate.Parent = char
	char.Parent = w.mock.workspace

	w.mock.localPlayer.CharacterAdded:Fire(char)
	local res = stepWorld(w, 0.25)
	check(#res.errors == 0, "kare dongusu hata verdi: " .. table.concat(res.errors, " | "))
	check(animate.Disabled == false,
		"pozlanamayan karakterde Animate kapatildi -> karakter T-pozda heykel gibi kalir")

	-- Dünyayı bozmadan geri al
	w.mock.localPlayer.CharacterAdded:Fire(original)
	stepWorld(w, 0.2)
end)

test("poseHumanoid=false kacis kapagi: ne poz yazilir ne Animate kapatilir", function()
	local w = bootWorld({ striker = false, poseHumanoid = false })
	check(w.installOk and w.serverOk and w.clientOk,
		"dunya kurulamadi: " .. tostring(w.installErr or w.serverErr or w.clientErr))
	local char = w.mock.localPlayer.Character
	local animate = char:FindFirstChild("Animate")
	local res = stepWorld(w, 0.4)
	check(#res.errors == 0, "kare dongusu hata verdi: " .. table.concat(res.errors, " | "))
	check(animate.Disabled == false,
		"poseHumanoid=false iken Animate kapatildi: oyuncu Roblox animasyonundan da olur")
	local identity = { 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }
	local comps = { char:FindFirstChild("LeftKnee").Transform:GetComponents() }
	local moved = 0
	for i = 1, 12 do
		if math.abs(comps[i] - identity[i]) > 1e-9 then
			moved = moved + 1
		end
	end
	check(moved == 0, "poseHumanoid=false iken eklem yazilmaya devam ediyor (bayrak dinlenmiyor)")
end)

test("V izleme kipi kamerayi topun arkasina aliyor", function()
	local before = clientWorld.camera.CFrame.Position
	clientWorld.mock.pressKey("V")
	local res = stepWorld(clientWorld, 1.5)
	check(#res.errors == 0, "V sonrasi kare dongusu hata verdi: " .. table.concat(res.errors, " | "))
	local ballPos = clientWorld.ball.Position
	local camPos = clientWorld.camera.CFrame.Position
	-- spectator: desiredPos = top + (-26, 15, 7) stud
	local ex, ey, ez = ballPos.X - 26, ballPos.Y + 15, ballPos.Z + 7
	local err = math.sqrt((camPos.X - ex) ^ 2 + (camPos.Y - ey) ^ 2 + (camPos.Z - ez) ^ 2)
	check(err < 4.0, "izleme kipi kamerasi hedefte degil (hata " .. string.format("%.1f stud", err) .. ")")
	check(math.abs(camPos.X - before.X) > 1.0 or math.abs(camPos.Y - before.Y) > 1.0,
		"V kamera konumunu degistirmedi")
	clientWorld.mock.pressKey("V") -- geri al
	stepWorld(clientWorld, 0.2)
end)

test("T vurus turunu, F ayagi degistiriyor ve HUD metni guncelleniyor", function()
	local first = hintText(clientWorld)
	check(type(first) == "string" and #first > 10, "Hint metni yok")
	check(first:find("Plase", 1, true) ~= nil, "baslangic vurus turi Plase degil: " .. tostring(first))
	check(first:find("ayak: R", 1, true) ~= nil, "baslangic ayagi R degil: " .. tostring(first))

	clientWorld.mock.pressKey("T")
	local second = hintText(clientWorld)
	check(second ~= first, "T vurus turunu degistirmedi")
	check(second:find("Duz ayak", 1, true) ~= nil or second:find("Düz ayak", 1, true) ~= nil,
		"T sonrasi tur 'Duz ayak' olmadi: " .. tostring(second))

	clientWorld.mock.pressKey("F")
	local third = hintText(clientWorld)
	check(third:find("ayak: L", 1, true) ~= nil, "F ayagi L yapmadi: " .. tostring(third))

	clientWorld.mock.pressKey("T")
	clientWorld.mock.pressKey("F")
	local fourth = hintText(clientWorld)
	check(fourth:find("ayak: R", 1, true) ~= nil, "F ikinci kez ayagi R yapmadi: " .. tostring(fourth))
end)


test("SPACE basili tutunca guc bari doluyor", function()
	local bar = clientWorld.hud:FindFirstChild("ChargeBar")
	local fill = bar:FindFirstChild("ChargeFill")
	placePlayerAtBall(clientWorld, 0.8)
	stepWorld(clientWorld, 0.2)
	check(bar.Visible == false, "guc bari baslamadan gorunur")
	clientWorld.mock.pressKey("Space")
	check(bar.Visible == true, "SPACE basinca guc bari gorunur olmadi")
	local res = stepWorld(clientWorld, 0.45)
	check(#res.errors == 0, "guc dolarken hata: " .. table.concat(res.errors, " | "))
	local scale = fill.Size.X.Scale
	check(scale > 0.35 and scale < 0.70,
		"0.45 s'de guc ~0.5 olmaliydi, gelen " .. string.format("%.2f", scale))
	-- Nisan rengi degismeli (sari)
	local marker = clientWorld.mock.workspace:FindFirstChild("AimMarker")
	-- Color3 bilesenleri gercek Roblox'taki gibi 0..1: sararma (255,220,90) -> R~1, G~0.86
	check(marker.Color.G > 0.75 and marker.Color.R > 0.9, "nisan isareti sararmadi (charging gorunumu)")
end)

test("SPACE birakinca sut istegi sunucuya gidiyor (5 arguman, sinirli degerler)", function()
	local bar = clientWorld.hud:FindFirstChild("ChargeBar")
	local before = #clientWorld.mock.remoteLog
	clientWorld.mock.releaseKey("Space")
	local entry = findRemoteCall(clientWorld, before + 1, "Kick", "FireServer")
	check(entry ~= nil, "InputEnded bagli degil: birakinca Kick gonderilmedi (sut atilamaz!)")
	check(entry.argCount == 5,
		"Kick 5 arguman gostermeli (charge, aimZ, aimY, shotType, foot), gelen " .. tostring(entry.argCount))
	local charge, aimZ, aimY, shotType, foot = table.unpack(entry.args)
	check(type(charge) == "number" and charge >= 0 and charge <= 1,
		"charge [0,1] olmali: " .. tostring(charge))
	check(charge > 0.3, "guc barindan gelen charge dusuk: " .. tostring(charge))
	check(type(aimZ) == "number" and aimZ >= -3.35 and aimZ <= 3.35, "aimZ sinir disi: " .. tostring(aimZ))
	check(type(aimY) == "number" and aimY >= 0.2 and aimY <= 2.35, "aimY sinir disi: " .. tostring(aimY))
	check(type(shotType) == "string", "shotType string degil: " .. tostring(shotType))
	check(foot == "L" or foot == "R", "foot L/R degil: " .. tostring(foot))
	check(bar.Visible == false, "birakinca guc bari gizlenmedi")
	check(bar:FindFirstChild("ChargeFill").Size.X.Scale == 0, "guc bari sifirlanmadi")
end)

test("R topu sifirliyor (ResetBall remote)", function()
	-- Once topu hareket ettir: sut uctu, simdi sifirlama gerekli olmali
	local res0 = stepWorld(clientWorld, 0.6)
	check(#res0.errors == 0, "kare dongusu hata verdi: " .. table.concat(res0.errors, " | "))
	local before = #clientWorld.mock.remoteLog
	clientWorld.mock.pressKey("R")
	local entry = findRemoteCall(clientWorld, before + 1, "ResetBall", "FireServer")
	check(entry ~= nil, "R ResetBall gondermedi")
	local res = stepWorld(clientWorld, 0.3)
	check(#res.errors == 0, "reset sonrasi hata: " .. table.concat(res.errors, " | "))
	local d = clientWorld.ball.Position - clientWorld.ballStart
	local dist = math.sqrt(d.X * d.X + d.Y * d.Y + d.Z * d.Z)
	check(dist < 1.0, "top baslangica donmedi: " .. string.format("%.2f stud uzakta", dist))
end)

test("ziplama kapatildi (SPACE sut icin ayrilmis)", function()
	local enabled = clientWorld.humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
	check(enabled == false,
		"Humanoid Jumping durumu kapatilmamis: SPACE basinca karakter zirplayip sut bozulur")
end)

test("MatchState yayini istemcide skoru guncelliyor", function()
	local score = clientWorld.hud:FindFirstChild("Score")
	check(type(score.Text) == "string" and score.Text:find("GOL 0", 1, true) ~= nil,
		"baslangic skor metni yanlis: " .. tostring(score.Text))
	check(clientWorld.stateRemote ~= nil, "MatchState remote yok")
	clientWorld.stateRemote:FireAllClients({
		goals = 3,
		saves = 2,
		kicks = 1,
		shots = 4,
		sag = 0.21,
		event = "goal",
	})
	check(score.Text:find("GOL 3", 1, true) ~= nil, "gol sayisi guncellenmedi: " .. tostring(score.Text))
	check(score.Text:find("KURTARI", 1, true) ~= nil and score.Text:find("2", 1, true) ~= nil,
		"kurtaris sayisi guncellenmedi: " .. tostring(score.Text))
	check(score.Text:find("5", 1, true) ~= nil,
		"sut sayisi kicks+shots=5 olmali: " .. tostring(score.Text))
	check(score.TextColor3.G > score.TextColor3.R, "gol rengi degismedi (yesil olmali)")

	clientWorld.stateRemote:FireAllClients({ goals = 3, saves = 3, kicks = 1, shots = 4, event = "save" })
	check(score.Text:find("KURTARI", 1, true) ~= nil, "kurtaris yayini islenmedi")
	check(score.TextColor3.R > score.TextColor3.B, "kurtaris rengi degismedi (sari olmali)")

	-- Bozuk payload istemciyi cokertmemeli
	local ok = pcall(function()
		clientWorld.stateRemote:FireAllClients("bozuk")
		clientWorld.stateRemote:FireAllClients({})
	end)
	check(ok, "bozuk MatchState payload'i istemcide hata verdi")
	local okFrame = pcall(function()
		clientWorld.mock.runService.RenderStepped:Fire(1 / 60)
	end)
	check(okFrame, "bozuk payload sonrasi kare dongusu hata verdi")
end)

test("istemci 4 s boyunca sunucuyla birlikte hatasiz calisiyor", function()
	local res = stepWorld(clientWorld, 4.0)
	check(#res.errors == 0, "kare dongusu hata verdi: " .. table.concat(res.errors, " | "))
	check(res.frames == 240, "kare sayisi yanlis: " .. tostring(res.frames))
	check(clientWorld.stepped < 12,
		"grup 11 toplam adim surei 12 s'yi asmamali (bosta demo sutu tetiklenir): " ..
		string.format("%.1f s", clientWorld.stepped))
end)

print("\n== 12. Uctan uca: istemci -> sunucu -> top -> istemci ==")

-- Not: sunucudaki şut hızı sınırı `os.clock()` ile GERÇEK zamana bakar; test
-- kareleri ise gerçek zamanda milisaniyeler sürer. Bu yüzden "tekrar denenecek"
-- her senaryo AYRI bir oyuncu ile koşulur (lastKickAt oyuncu başınadır) ve bu
-- oyuncular `join = false` ile sunucunun oyuncu listesine eklenmez: böylece
-- ölçümler (top hızı, launch sayısı) başka gövdelerden etkilenmez.
--[[ Kare kare ilerlerken karakteri de yürütür (mock'ta HRP kendiliğinden
     hareket etmez; hız yalnızca bir özelliktir). Top sürme senaryosu için şart. ]]
local function runFramesMoving(world, hrp, seconds, speedMeters)
	local dt = 1 / 60
	local frames = math.max(1, math.floor(seconds / dt))
	local errs = {}
	for _ = 1, frames do
		local pos = hrp.Position
		hrp.CFrame = CFrame.lookAt(
			pos + Vector3.new(speedMeters * STUDS_PER_METER * dt, 0, 0),
			pos + Vector3.new(10, 0, 0))
		local r = stepWorld(world, dt)
		for _, e in ipairs(r.errors) do
			errs[#errs + 1] = e
		end
	end
	return errs
end

local function gapMeters(world, hrp)
	local bp = world.ball.Position
	local pp = hrp.Position
	local dx = bp.X - pp.X
	local dz = bp.Z - pp.Z
	return math.sqrt(dx * dx + dz * dz) / STUDS_PER_METER
end

--[[ MatchState yayınlarında belli bir olayı (ve varsa hint metnini) bulur. ]]
local function findStateEvent(world, eventName, fromIndex)
	for i = math.max(1, fromIndex or 1), #world.mock.remoteLog do
		local entry = world.mock.remoteLog[i]
		if entry.name == "MatchState" and type(entry.args[1]) == "table"
			and entry.args[1].event == eventName then
			return entry.args[1], i
		end
	end
	return nil
end

local function makeAttacker(world, name, behindMeters)
	local player = world.mock.makePlayer(name, Vector3.new(0, 3, 0), { join = false })
	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	local bp = world.ball.Position
	local back = (behindMeters or 0.8) * STUDS_PER_METER
	hrp.CFrame = CFrame.lookAt(
		Vector3.new(bp.X - back, bp.Y, bp.Z),
		Vector3.new(bp.X - back + 10, bp.Y, bp.Z)
	)
	hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	return player, hrp
end

-- Sunucu, top menzil dışındayken şutu SESSİZCE reddediyordu (kickRemote
-- handler'ında 4 farklı erken return, hiçbiri istemciye bir şey söylemiyor).
-- "şut çekemiyorum" şikayetinin asıl sebebi bu: oyuncu nedenini göremiyor.
-- Artık HUD aynı kapıyı okuyup mesafeyi ve ne yapması gerektiğini yazıyor.
test("top menzil disindayken HUD oyuncuya nedeni soyluyor (sessiz red yok)", function()
	-- Yerel oyuncunun karakterini toptan 9 m uzağa ışınla (menzil 2 m).
	-- BallView kendi karakterini (Players.LocalPlayer) ölçer, başkasını değil.
	local bp = clientWorld.ball.Position
	local farPos = Vector3.new(bp.X - 9 * STUDS_PER_METER, bp.Y, bp.Z)
	clientWorld.hrp.CFrame = CFrame.lookAt(farPos, farPos + Vector3.new(10, 0, 0))
	clientWorld.hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	local steps = stepWorld(clientWorld, 0.25)
	check(#steps.errors == 0, "kare dongusu hata verdi: " .. table.concat(steps.errors, " | "))
	local far = hintText(clientWorld)
	check(type(far) == "string", "Hint metni yok")
	check(far:find("TOPA YAKLA", 1, true) ~= nil,
		"menzil disinda uyari yok: " .. tostring(far))
	check(far:find("menzil", 1, true) ~= nil,
		"uyarida vurus menzili yazmiyor: " .. tostring(far))
	check(far:find("ayak: R", 1, true) ~= nil,
		"uyari vurus turu/ayak bilgisini sildi: " .. tostring(far))
	local farLabel = clientWorld.hud:FindFirstChild("Hint")
	check(farLabel.TextColor3 ~= nil, "Hint rengi okunamiyor")

	-- Topa yaklaşınca uyarı kaybolur, normal ipucu geri gelir
	placePlayerAtBall(clientWorld, 0.8)
	local back = stepWorld(clientWorld, 0.25)
	check(#back.errors == 0, "yaklasirken hata: " .. table.concat(back.errors, " | "))
	local near = hintText(clientWorld)
	check(near:find("TOPA YAKLA", 1, true) == nil,
		"menzile girince uyari kalkmadi: " .. tostring(near))
	check(near:find("SPACE", 1, true) ~= nil, "normal ipucu geri gelmedi: " .. tostring(near))
end)

-- "Oyuncu animasyonları çalışmıyor" şikayetinin uctan uca kanıtı: karakterin
-- R15 eklemleri gerçekten yazılıyor mu? (Mock karakter artık Motor6D içeriyor;
-- içermese bu test boşuna yeşil kalırdı.)
test("oyuncu animasyonu uctan uca: durusta, kosarken ve sута eklemler yaziliyor", function()
	local animWorld = bootWorld({ striker = false })
	check(animWorld.installOk and animWorld.serverOk and animWorld.clientOk,
		"dunya kurulamadi: " .. tostring(animWorld.installErr or animWorld.serverErr or animWorld.clientErr))
	local character = animWorld.hrp and animWorld.hrp.Parent
	check(character ~= nil, "karakter yok")
	check(character:FindFirstChild("LeftHip") ~= nil,
		"karakterde R15 LeftHip eklemi yok (mock Motor6D uretmiyor)")

	placePlayerAtBall(animWorld, 0.8)
	local warm = stepWorld(animWorld, 0.35)
	check(#warm.errors == 0, "isinma kareleri hata verdi: " .. table.concat(warm.errors, " | "))

	-- 1) Dururken: eklem kimlikte kalmamali (atletik bekleyiş + nefes)
	local standHip = jointComponents(character, "LeftHip")
	local standKnee = jointComponents(character, "LeftKnee")
	check(standHip ~= nil and standKnee ~= nil, "durusta eklem Transform okunamiyor")
	check(jointsMoved(standKnee, { 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }) > 0,
		"durusta diz kimlikte: karakter heykel gibi donmus")
	local laterKnee = jointComponents(character, "LeftKnee")
	stepWorld(animWorld, 0.6)
	laterKnee = jointComponents(character, "LeftKnee")
	check(jointsMoved(standKnee, laterKnee) > 0,
		"durusta poz zamanla degismiyor: nefes animasyonu yok")

	-- 2) Yürürken: koşu döngüsü ilerlemeli
	placePlayerAtBall(animWorld, 0.8)
	animWorld.hrp.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
	local walkStart = jointComponents(character, "LeftHip")
	stepWorld(animWorld, 0.30)
	local walkMid = jointComponents(character, "LeftHip")
	stepWorld(animWorld, 0.30)
	local walkEnd = jointComponents(character, "LeftHip")
	check(jointsMoved(walkStart, walkMid) > 0, "kosarken kalca pozu degismedi (adim 1)")
	check(jointsMoved(walkMid, walkEnd) > 0, "kosarken kalca pozu degismedi (adim 2)")
	animWorld.hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)

	-- 3) Şut sırasında: KickAnim pozu yazılmalı (bacak savrulur)
	local beforeKick = jointComponents(character, "RightHip")
	local kickFrames = stepWorld(animWorld, 0.2)
	check(#kickFrames.errors == 0, "sut oncesi karelerde hata: " .. table.concat(kickFrames.errors, " | "))
	animWorld.mock.pressKey("Space")
	stepWorld(animWorld, 0.95) -- CHARGE_TIME 0.9 s
	animWorld.mock.releaseKey("Space")
	local duringKick = jointComponents(character, "RightHip")
	local shotFrames = stepWorld(animWorld, 0.30)
	check(#shotFrames.errors == 0, "sut kareleri hata verdi: " .. table.concat(shotFrames.errors, " | "))
	check(shotFrames.launches >= 1,
		"menzil icindeki oyuncunun sutu topu firlatmadi (launches=" .. tostring(shotFrames.launches) .. ")")
	check(jointsMoved(beforeKick, duringKick) > 0,
		"sut sirasinda kalca eklemi yazilmadi: KickAnim pozu karaktere uygulanmiyor")

	-- 4) Vuruş bittikten sonra karakter donup kalmamali (yürüyüş pozu devralır)
	local afterShot = jointComponents(character, "RightHip")
	stepWorld(animWorld, 1.2)
	local settledPose = jointComponents(character, "RightHip")
	check(jointsMoved(afterShot, settledPose) > 0,
		"sut bittikten sonra karakter dondu: yuruyus/durus pozu devralmadi")
end)

-- GERÇEK ROBLOX KIRILMASI: Motor6D.Transform, Animator tarafından her karede
-- RenderStepped SONRASI / Stepped ÖNCESİ ezilir. Mock artık bu ezmeyi taklit
-- ediyor; poz yalnızca Stepped içinde yazılırsa görünür kalır. Ayrıca zaten
-- oynayan varsayılan AnimationTrack'ler script kapatılsa da yaşamaya devam
-- eder — onların da durdurulması gerekir.
test("istemci pozu Animator eziminden sonra yazilir, varsayilan track durdurulur", function()
	local animWorld = bootWorld({ striker = false })
	check(animWorld.installOk and animWorld.serverOk and animWorld.clientOk,
		"dunya kurulamadi: " .. tostring(animWorld.installErr or animWorld.serverErr or animWorld.clientErr))
	local character = animWorld.hrp and animWorld.hrp.Parent
	local animate = character and character:FindFirstChild("Animate")
	check(animate ~= nil and animate.Disabled == true, "varsayilan Animate kapatilmadi")

	-- İstemci bağlandıktan SONRA başlayan varsayilan kosma track'i
	local track = animWorld.mock.addPlayingTrack(character, "RunAnim")
	check(track ~= nil, "mock animasyon track'i uretilemedi")
	-- En kötü durum: Animator her karede Transform'u eziyor. Poz yalnızca
	-- Stepped'de yazılırsa görünür kalır; RenderStepped'de yazılırsa kaybolur.
	animWorld.mock.animatorOverwrite = true
	placePlayerAtBall(animWorld, 0.8)
	local res = stepWorld(animWorld, 0.5)
	check(#res.errors == 0, "kare dongusu hata verdi: " .. table.concat(res.errors, " | "))
	check(track.stopped == true, "oynayan varsayilan Animator track'i durdurulmadi")

	-- Mock her karede Transform'u identity yapıp SONRA Stepped'i çalıştırıyor:
	-- poz hâlâ okunabiliyorsa yazım doğru zamanda yapılıyor demektir.
	local knee = jointComponents(character, "LeftKnee")
	check(jointsMoved(knee, { 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }) > 0,
		"Stepped sonrasi diz pozunu Animator ezdi (oyuncu animasyonu görünmez)")

	-- Respawn/streaming sırasında sonradan gelen Animate de kapatılmalı.
	animate:Destroy()
	local lateAnimate = Instance.new("LocalScript")
	lateAnimate.Name = "Animate"
	lateAnimate.Parent = character
	local lateRes = stepWorld(animWorld, 0.1)
	check(#lateRes.errors == 0, "gec gelen Animate sonrasi hata: " .. table.concat(lateRes.errors, " | "))
	check(lateAnimate.Disabled == true, "sonradan gelen Animate kapatilmadi (pozu ezer)")
end)

-- İkinci gerçek kırılma: CharacterAdded anında Motor6D'ler henüz yok olabilir.
-- Tek seferlik supported() kontrolü bu durumda pozu hiç açmaz.
test("Motor6D'ler sonradan gelince de prosedurel poz aciliyor", function()
	local world = bootWorld({ striker = false, client = false })
	check(world.installOk and world.serverOk, "sunucu kurulamadi")
	local character = world.mock.localPlayer.Character
	local motors = {}
	for _, obj in ipairs(character:GetChildren()) do
		if obj:IsA("Motor6D") then
			motors[#motors + 1] = obj
		end
	end
	check(#motors >= 8, "mock R15 eklemleri bulunamadi")
	for _, motor in ipairs(motors) do
		motor.Parent = nil
	end

	local clientFolder = world.mock.starterPlayerScripts:FindFirstChild("Client")
	local ballView = clientFolder and clientFolder:FindFirstChild("BallView")
	check(ballView ~= nil, "BallView bulunamadi")
	local okClient, errClient = pcall(function()
		local chunk = assert(load(ballView.Source, "@BallViewLate"))
		chunk()
	end)
	check(okClient, "istemci yuklenemedi: " .. tostring(errClient))

	local animate = character:FindFirstChild("Animate")
	check(animate ~= nil and animate.Disabled ~= true,
		"motorlar yokken varsayilan animasyon kapatilmamali (karakter heykele donmesin)")

	for _, motor in ipairs(motors) do
		motor.Parent = character
	end
	local res = stepWorld(world, 0.5)
	check(#res.errors == 0, "motorlar gelince hata: " .. table.concat(res.errors, " | "))
	check(animate.Disabled == true, "motorlar gelince varsayilan Animate kapanmadi")
	local knee = jointComponents(character, "LeftKnee")
	check(jointsMoved(knee, { 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }) > 0,
		"gec gelen motorlara poz yazilmadi")
end)

-- ÜÇÜNCÜ gerçek kırılma: yeni R15 avatarlarda (StarterPlayer.AvatarJointUpgrade
-- varsayılan) eklemler Motor6D DEĞİL AnimationConstraint'tir. Eski IsA kontrolü
-- bu karakterde hiç eklem bulmuyor ve prosedürel poz sessizce atlanıyordu.
test("AvatarJointUpgrade: AnimationConstraint eklemlerine de poz yaziliyor", function()
	local world = bootWorld({ striker = false, client = false })
	check(world.installOk and world.serverOk, "sunucu kurulamadi")
	local character = world.mock.localPlayer.Character
	local swapped = world.mock.upgradeJoints(character)
	check(swapped >= 8, "Motor6D -> AnimationConstraint donusumu yapilmadi: " .. tostring(swapped))
	local hip = character:FindFirstChild("LeftHip")
	check(hip ~= nil and hip:IsA("AnimationConstraint"), "AnimationConstraint eklemi yok")

	local clientFolder = world.mock.starterPlayerScripts:FindFirstChild("Client")
	local ballView = clientFolder and clientFolder:FindFirstChild("BallView")
	check(ballView ~= nil, "BallView bulunamadi")
	local okClient, errClient = pcall(function()
		local chunk = assert(load(ballView.Source, "@BallViewAJU"))
		chunk()
	end)
	check(okClient, "istemci yuklenemedi: " .. tostring(errClient))

	local animate = character:FindFirstChild("Animate")
	check(animate ~= nil and animate.Disabled == true,
		"AnimationConstraint karakterde varsayilan Animate kapanmadi")
	local res = stepWorld(world, 0.5)
	check(#res.errors == 0, "kare dongusu hata verdi: " .. table.concat(res.errors, " | "))
	local knee = jointComponents(character, "LeftKnee")
	check(jointsMoved(knee, { 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }) > 0,
		"AnimationConstraint eklemlerine poz yazilmadi (oyuncu animasyonu calismiyor)")
end)

-- Aynı davranışın SUNUCU tarafı kanıtı: istemci script'i hiç çalışmazken
-- (yani başka bir oyuncunun/sunucunun gördüğü hâliyle) karakter yine
-- animasyonlu olmalı. Eskiden sunucu pozu yalnızca şut beklerken yazıyordu;
-- bu yüzden diğer oyuncular için karakter yürürken donmuş görünüyordu.
test("sunucu tek basina da oyuncuyu animasyonlu tutuyor (istemci kapali)", function()
	local serverOnly = bootWorld({ striker = false, client = false })
	check(serverOnly.installOk and serverOnly.serverOk,
		"dunya kurulamadi: " .. tostring(serverOnly.installErr or serverOnly.serverErr))

	-- Sunucunun poz yazdığı karakterler Players:GetPlayers() içindekilerdir;
	-- bu yüzden OYUNA KATILMIŞ bir oyuncu kullanılır (LocalTester katılmaz).
	local joined = serverOnly.mock.makePlayer("ServerViewer", Vector3.new(0, 3, 0))
	local character = joined.Character
	local hrp = character:FindFirstChild("HumanoidRootPart")
	check(hrp ~= nil, "katilan oyuncunun karakter koku yok")
	check(character:FindFirstChild("RightHip") ~= nil, "R15 RightHip eklemi yok")

	local bp = serverOnly.ball.Position
	local pos = Vector3.new(bp.X - 0.8 * STUDS_PER_METER, bp.Y, bp.Z)
	hrp.CFrame = CFrame.lookAt(pos, pos + Vector3.new(10, 0, 0))
	hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)

	local warm = stepWorld(serverOnly, 0.3)
	check(#warm.errors == 0, "isinma kareleri hata verdi: " .. table.concat(warm.errors, " | "))

	local stand = jointComponents(character, "RightHip")
	local standKnee = jointComponents(character, "RightKnee")
	check(stand ~= nil and standKnee ~= nil, "sunucu pozu okunamiyor")
	check(jointsMoved(standKnee, { 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }) > 0,
		"sunucu durusta pozu yazmiyor: karakter kimlikte (heykel)")

	hrp.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
	stepWorld(serverOnly, 0.30)
	local walkA = jointComponents(character, "RightHip")
	stepWorld(serverOnly, 0.30)
	local walkB = jointComponents(character, "RightHip")
	hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	check(jointsMoved(stand, walkA) > 0,
		"sunucu kosu pozunu yazmiyor (durus -> kosu degismedi)")
	check(jointsMoved(walkA, walkB) > 0,
		"sunucu kosu dongusunu ilerletmiyor (iki kare ayni)")
end)

-- KULLANICININ İKİNCİ ŞİKAYETİ: "topa yaklaştığımda topu sürdüğüm için şut
-- çekemiyorum". Sürüş dokunuşu topu oyuncunun önüne iter; mesafe katı menzili
-- (kickReach) geçtiği için şut isteği düşüyordu. İki çözüm birlikte test edilir:
-- sürüş sahipliği (az önce dokunulan topa vurulabilir) ve şut tamponu (istek
-- çöpe gitmez, oyuncu yetişince çıkar).
test("kosan oyuncu topu suruyor ve YINE de sut atabiliyor (surus sahipligi)", function()
	local w = bootWorld({ striker = false })
	check(w.installOk and w.serverOk and w.clientOk,
		"dunya kurulamadi: " .. tostring(w.installErr or w.serverErr or w.clientErr))
	local settled = settleBall(w)
	check(#settled.errors == 0, "top oturtulurken hata: " .. table.concat(settled.errors, " | "))

	local runner = w.mock.makePlayer("Dribbler", Vector3.new(0, 3, 0))
	local hrp = runner.Character:FindFirstChild("HumanoidRootPart")
	check(hrp ~= nil, "kosucunun karakter koku yok")
	local bp = w.ball.Position
	hrp.CFrame = CFrame.lookAt(
		Vector3.new(bp.X - 1.2 * STUDS_PER_METER, bp.Y, bp.Z),
		Vector3.new(bp.X + 10, bp.Y, bp.Z))
	local RUN_SPEED = 6.0
	hrp.AssemblyLinearVelocity = Vector3.new(RUN_SPEED * STUDS_PER_METER, 0, 0)

	-- Top sür: dokunuşlar topu öne iter (README: 5.5 m/s'de boşluk ~2.2 m).
	-- Boşluk katı menzili (kickReach) AŞAR AŞMAZ dur — sürüş modeli ileride
	-- değişirse test yine tam olarak aynı durumu (sürüş hâlinde şut) ölçsün.
	local runErrs = runFramesMoving(w, hrp, 0.4, RUN_SPEED)
	local gap = gapMeters(w, hrp)
	for _ = 1, 10 do
		if gap > Config.BALL_CONTROL.kickReach then
			break
		end
		for _, e in ipairs(runFramesMoving(w, hrp, 0.2, RUN_SPEED)) do
			runErrs[#runErrs + 1] = e
		end
		gap = gapMeters(w, hrp)
	end
	check(#runErrs == 0, "kosu kareleri hata verdi: " .. table.concat(runErrs, " | "))
	check(gap > Config.BALL_CONTROL.kickReach, string.format(
		"on kosul: surus topu kati menzilin (%.2f m) disina itmeli, olculen %.2f m — aksi halde test hicbir sey kanitlamaz",
		Config.BALL_CONTROL.kickReach, gap))
	check(gap <= Config.BALL_CONTROL.possessionReach, string.format(
		"on kosul: bosluk sahiplik bandini (%.2f m) asmamali, olculen %.2f m — aksi halde tampon yolu test edilir",
		Config.BALL_CONTROL.possessionReach, gap))

	-- Sürüş hâlinde şut: sahiplik yüzünden ÇIKMALI
	local mark = #w.mock.remoteLog
	w.kickRemote.OnServerEvent:Fire(runner, 1.0, 0.0, 1.0, "instep", "R")
	local res = stepWorld(w, 1.2)
	check(#res.errors == 0, "sut kareleri hata verdi: " .. table.concat(res.errors, " | "))
	check(res.launches >= 1, string.format(
		"top surerken sut cikmadi (bosluk %.2f m, launches=%d): surus sahipligi calismiyor",
		gap, res.launches))
	check(res.maxSpeed > 8, string.format(
		"surus sirasindaki sut topu hizlandirmadi: %.2f m/s", res.maxSpeed))
	check(findStateEvent(w, "shotRejected", mark) == nil,
		"surus sirasindaki sut reddedildi: " .. tostring((findStateEvent(w, "shotRejected", mark) or {}).hint))
end)

test("menzil disindaki sut istegi cope gitmiyor: tampona alinip oyuncu yetisince cikiyor", function()
	local w = bootWorld({ striker = false })
	check(w.installOk and w.serverOk, "dunya kurulamadi: " .. tostring(w.installErr or w.serverErr))
	local settled = settleBall(w)
	check(#settled.errors == 0, "top oturtulurken hata: " .. table.concat(settled.errors, " | "))

	local chaser = w.mock.makePlayer("Chaser", Vector3.new(0, 3, 0))
	local hrp = chaser.Character:FindFirstChild("HumanoidRootPart")
	local bp = w.ball.Position
	-- Sahiplik bandının dışında, tampon menzilinin içinde; topa HİÇ dokunmadı
	local farPos = Vector3.new(bp.X - 4.0 * STUDS_PER_METER, bp.Y, bp.Z)
	hrp.CFrame = CFrame.lookAt(farPos, farPos + Vector3.new(10, 0, 0))
	hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)

	local mark = #w.mock.remoteLog
	w.kickRemote.OnServerEvent:Fire(chaser, 0.8, 0.0, 1.0, "instep", "R")
	local first = stepWorld(w, 0.25)
	check(#first.errors == 0, "kareler hata verdi: " .. table.concat(first.errors, " | "))
	check(first.launches == 0,
		"4 m uzaktaki top aninda vuruldu: sahiplik/tampon kurali fazla gevsek")

	local bufferedEvent = findStateEvent(w, "shotBuffered", mark)
	check(bufferedEvent ~= nil, "tampona alinan sut oyuncuya bildirilmedi (sessiz bekleyis)")
	check(type(bufferedEvent.hint) == "string" and #bufferedEvent.hint > 8,
		"tampon bildirimi neden icermiyor: " .. tostring(bufferedEvent.hint))

	-- Oyuncu topa yetişir -> tampondaki şut kendiliğinden çıkmalı
	hrp.CFrame = CFrame.lookAt(
		Vector3.new(bp.X - 0.8 * STUDS_PER_METER, bp.Y, bp.Z),
		Vector3.new(bp.X + 10, bp.Y, bp.Z))
	local res = stepWorld(w, 1.2)
	check(#res.errors == 0, "sut kareleri hata verdi: " .. table.concat(res.errors, " | "))
	check(res.launches >= 1,
		"tampondaki sut oyuncu yetisince cikmadi (launches=" .. tostring(res.launches) .. ")")
	local fired = findStateEvent(w, "shotFired", mark)
	check(fired ~= nil, "tampondan cikan sut oyuncuya bildirilmedi")
	check(type(fired.hint) == "string" and #fired.hint > 4, "cikis bildirimi bos")
end)

test("tampon penceresi kapaninca sut dusuyor ve NEDENI bildiriliyor", function()
	local w = bootWorld({ striker = false })
	check(w.installOk and w.serverOk, "dunya kurulamadi: " .. tostring(w.installErr or w.serverErr))
	local settled = settleBall(w)
	check(#settled.errors == 0, "top oturtulurken hata: " .. table.concat(settled.errors, " | "))

	local late = w.mock.makePlayer("Late", Vector3.new(0, 3, 0))
	local hrp = late.Character:FindFirstChild("HumanoidRootPart")
	local bp = w.ball.Position
	local farPos = Vector3.new(bp.X - 4.0 * STUDS_PER_METER, bp.Y, bp.Z)
	hrp.CFrame = CFrame.lookAt(farPos, farPos + Vector3.new(10, 0, 0))
	hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)

	local mark = #w.mock.remoteLog
	w.kickRemote.OnServerEvent:Fire(late, 1.0, 0.0, 1.0, "instep", "R")
	check(findStateEvent(w, "shotBuffered", mark) ~= nil, "istek tampona alinmadi")

	-- Oyuncu yerinde sayar: pencere (shotBufferTime) kapanmalı
	local res = stepWorld(w, Config.BALL_CONTROL.shotBufferTime + 0.5)
	check(#res.errors == 0, "kareler hata verdi: " .. table.concat(res.errors, " | "))
	check(res.launches == 0, "pencere kapandiktan sonra sut cikti (tampon sonsuz)")
	local expired = findStateEvent(w, "shotExpired", mark)
	check(expired ~= nil, "pencerenin kapandigi oyuncuya soylenmedi (sessiz dusus)")
	check(type(expired.hint) == "string" and #expired.hint > 8,
		"pencere bildirimi neden icermiyor: " .. tostring(expired.hint))

	-- Tampon menzilinin de dışındaki istek doğrudan reddedilir (bekletilmez)
	local mark2 = #w.mock.remoteLog
	local bp2 = w.ball.Position
	hrp.CFrame = CFrame.lookAt(
		Vector3.new(bp2.X - 14.0 * STUDS_PER_METER, bp2.Y, bp2.Z),
		Vector3.new(bp2.X + 10, bp2.Y, bp2.Z))
	stepWorld(w, Config.BALL_CONTROL.shotBufferTime + 0.6) -- hiz siniri penceresi bosalsin
	w.kickRemote.OnServerEvent:Fire(late, 1.0, 0.0, 1.0, "instep", "R")
	local res2 = stepWorld(w, 0.4)
	check(res2.launches == 0, "14 m uzaktaki top vuruldu (otorite gevşedi)")
	local rejected = findStateEvent(w, "shotRejected", mark2)
	check(rejected ~= nil, "tampon menzili disindaki istek icin neden gonderilmedi")
	check(type(rejected.hint) == "string" and rejected.hint:find("menzil", 1, true) ~= nil,
		"ret nedeni mesafe/menzil icermiyor: " .. tostring(rejected.hint))
end)

test("sunucunun ret nedeni istemcide HUD'a yaziliyor (ekrana cikmayan red yok)", function()
	-- clientWorld: yerel oyuncuyu tampon menzilinin dışına ışınla (9 m)
	local bp = clientWorld.ball.Position
	local farPos = Vector3.new(bp.X - 9 * STUDS_PER_METER, bp.Y, bp.Z)
	clientWorld.hrp.CFrame = CFrame.lookAt(farPos, farPos + Vector3.new(10, 0, 0))
	clientWorld.hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	stepWorld(clientWorld, 2.6) -- önceki testin ipucu penceresi kapansın

	local mark = #clientWorld.mock.remoteLog
	clientWorld.mock.pressKey("Space")
	stepWorld(clientWorld, 0.95)
	clientWorld.mock.releaseKey("Space")
	stepWorld(clientWorld, 0.3)

	local rejected = findStateEvent(clientWorld, "shotRejected", mark)
	check(rejected ~= nil, "sunucu menzil disindaki istek icin neden gondermedi")
	check(type(rejected.hint) == "string" and #rejected.hint > 8,
		"gonderilen neden bos: " .. tostring(rejected.hint))
	local text = hintText(clientWorld)
	check(type(text) == "string" and text:find(rejected.hint, 1, true) ~= nil,
		"sunucunun nedeni HUD'a yazilmadi. HUD: " .. tostring(text) .. " | sunucu: " .. tostring(rejected.hint))
end)

test("surus bandinda istemci yanlis uyari vermiyor (sahiplikle sut cikar)", function()
	stepWorld(clientWorld, 2.6) -- sunucu ipucu penceresi kapansın
	local bp = clientWorld.ball.Position
	-- Katı menzilin dışında ama sahiplik bandının içinde: sunucu şutu kabul eder,
	-- istemci "TOPA YAKLAŞ" diye bağırmamalı (dar eşik kullanıldığının kanıtı).
	local midPos = Vector3.new(bp.X - 2.5 * STUDS_PER_METER, bp.Y, bp.Z)
	clientWorld.hrp.CFrame = CFrame.lookAt(midPos, midPos + Vector3.new(10, 0, 0))
	clientWorld.hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	local steps = stepWorld(clientWorld, 0.3)
	check(#steps.errors == 0, "kareler hata verdi: " .. table.concat(steps.errors, " | "))
	local text = hintText(clientWorld)
	check(text:find("TOPA YAKLA", 1, true) == nil,
		"surus bandinda gereksiz uyari: " .. tostring(text))
	check(text:find("SPACE", 1, true) ~= nil, "normal ipucu kayboldu: " .. tostring(text))
	-- Katı menzilin içindeyse HUD oyuncuya hazır olduğunu söyler
	placePlayerAtBall(clientWorld, 0.8)
	stepWorld(clientWorld, 0.3)
	local ready = hintText(clientWorld)
	check(ready:find("HAZIR", 1, true) ~= nil, "menzil icinde 'ŞUT HAZIR' gostergesi yok: " .. tostring(ready))
end)

local e2e = nil

test("istemcinin sutu sunucuda topu gercekten firlatiyor", function()
	e2e = bootWorld({ striker = false })
	check(e2e.installOk and e2e.serverOk and e2e.clientOk,
		"dunya kurulamadi: " .. tostring(e2e.installErr or e2e.serverErr or e2e.clientErr))
	placePlayerAtBall(e2e, 0.8)
	local warm = stepWorld(e2e, 0.3)
	check(#warm.errors == 0, "isinma kareleri hata verdi: " .. table.concat(warm.errors, " | "))

	local startPos = e2e.ball.Position
	e2e.mock.pressKey("Space")
	local charge = stepWorld(e2e, 1.0) -- CHARGE_TIME = 0.9 s -> tam guc
	check(#charge.errors == 0, "guc toplarken hata: " .. table.concat(charge.errors, " | "))
	e2e.mock.releaseKey("Space")

	-- Temas ani 0.24 s sonra: top o anda ayrilir
	local res = stepWorld(e2e, 1.2)
	check(#res.errors == 0, "sut sirasinda hata: " .. table.concat(res.errors, " | "))
	check(res.launches >= 1, "top firlatilmadi (launch sayisi " .. tostring(res.launches) .. ")")
	check(res.maxSpeed > 25,
		"tam guc sut ~31 m/s olmali, olculen " .. string.format("%.1f m/s", res.maxSpeed))
	check(res.maxSpeed <= 32.5,
		"hiz tavani asildi (maxKickSpeed=31): " .. string.format("%.1f m/s", res.maxSpeed))
	local moved = e2e.ball.Position - startPos
	local travelled = math.sqrt(moved.X * moved.X + moved.Y * moved.Y + moved.Z * moved.Z) / STUDS_PER_METER
	check(travelled > 10, "top yeterince ilerlemedi: " .. string.format("%.1f m", travelled))
end)

test("hiz siniri: ayni anda iki sut istegi tek sut uretir", function()
	local settled = settleBall(e2e)
	check(#settled.errors == 0, "top sifirlanirken hata: " .. table.concat(settled.errors, " | "))
	local attacker = makeAttacker(e2e, "Spammer", 0.8)
	e2e.kickRemote.OnServerEvent:Fire(attacker, 1.0, 0.5, 1.0, "instep", "R")
	e2e.kickRemote.OnServerEvent:Fire(attacker, 1.0, -0.5, 1.5, "drive", "L") -- spam
	local res = stepWorld(e2e, 1.0)
	check(#res.errors == 0, "kare dongusu hata verdi: " .. table.concat(res.errors, " | "))
	check(res.launches == 1,
		"iki istek tek sut uretmeliydi (0.35 s siniri + pending kilidi), olculen launch " ..
		tostring(res.launches))
	check(res.maxSpeed > 25, "sut yine de gerceklesmedi: " .. string.format("%.1f m/s", res.maxSpeed))
end)

test("uzaktaki oyuncunun sut istegi reddediliyor (sunucu otoritesi)", function()
	local settled = settleBall(e2e)
	check(#settled.errors == 0, "top sifirlanirken hata: " .. table.concat(settled.errors, " | "))
	local attacker = makeAttacker(e2e, "FarAway", 20) -- kickReach = 2.00 m: 20 m hala cok uzak
	local before = e2e.ball.Position
	e2e.kickRemote.OnServerEvent:Fire(attacker, 1.0, 0.0, 1.0, "instep", "R")
	local res = stepWorld(e2e, 1.0)
	check(#res.errors == 0, "kare dongusu hata verdi: " .. table.concat(res.errors, " | "))
	check(res.launches == 0,
		"20 m uzaktaki oyuncu sut atabildi! launch=" .. tostring(res.launches) ..
		" maxSpeed=" .. string.format("%.1f m/s", res.maxSpeed))
	check(res.maxSpeed < 2,
		"duran top hareket etti: " .. string.format("%.2f m/s", res.maxSpeed))
	local moved = e2e.ball.Position - before
	local travelled = math.sqrt(moved.X * moved.X + moved.Y * moved.Y + moved.Z * moved.Z) / STUDS_PER_METER
	check(travelled < 1.0, "top beklemedik sekilde yer degistirdi: " .. string.format("%.2f m", travelled))
end)

test("top havadayken sut istegi reddediliyor (yukseklik kapisi)", function()
	-- Topu bilinen bir yere al (R ile ayni yol: ResetBall remote)
	local settle = settleBall(e2e)
	check(#settle.errors == 0, "reset sonrasi hata: " .. table.concat(settle.errors, " | "))
	local groundHeight = e2e.ball.Position.Y / STUDS_PER_METER
	check(groundHeight < 0.5, "reset sonrasi top yerde degil: " .. string.format("%.2f m", groundHeight))

	-- Once topu havaya gonder
	local kicker = makeAttacker(e2e, "Launcher", 0.8)
	e2e.kickRemote.OnServerEvent:Fire(kicker, 1.0, 0.0, 2.2, "instep", "R")
	local height, frames = 0, 0
	while frames < 40 do
		stepWorld(e2e, 1 / 60)
		frames = frames + 1
		height = e2e.ball.Position.Y / STUDS_PER_METER
		if height > 1.3 then
			break
		end
	end
	check(height > 1.3, "top test icin yeterince yukselmedi: " .. string.format("%.2f m", height))

	-- Simdi topun altindaki oyuncu sut istesin: kickHeight = 1.0 m -> reddedilmeli
	local attacker = makeAttacker(e2e, "UnderBall", 0.8)
	e2e.kickRemote.OnServerEvent:Fire(attacker, 1.0, 0.0, 1.0, "instep", "R")
	local res = stepWorld(e2e, 0.6)
	check(#res.errors == 0, "kare dongusu hata verdi: " .. table.concat(res.errors, " | "))
	check(res.launches == 0,
		"havada (y=" .. string.format("%.2f m", height) .. ") topa sut islenmemeliydi, launch=" ..
		tostring(res.launches))
end)

test("guvenilmez istemci girdisi sunucuyu cokertmiyor (beyaz liste)", function()
	-- Her deneme AYRI oyuncu (rate limit golgelemesin) ve top her denemede
	-- baslangicta, YERDE: boylece handler gercekten dogrulama koduna ulasir
	-- (canKick/dist kapilari erken return yapmaz).
	local badInputs = {
		{ 99, -500, 99, "labels", {} }, -- shotType = Config.SHOT tablosunun anahtari
		{ "0.8", "1.2", "0.9", "types", 5 }, -- foot sayi -> "hip5" concatenation
		{ nil, nil, nil, nil, nil }, -- hic arguman yok
		{ {}, { hack = true }, function() end, "place", "X" }, -- tablo/fonksiyon
		{ math.huge, -math.huge, math.huge, "drive", "R" }, -- sonsuz
		{ 0 / 0, 0 / 0, 0 / 0, "outside", "L" }, -- NaN
	}
	check(e2e.kickRemote ~= nil, "Kick remote yok")
	for index, args in ipairs(badInputs) do
		local settled = settleBall(e2e)
		check(#settled.errors == 0, "deneme #" .. tostring(index) .. " oncesi hata: " ..
			table.concat(settled.errors, " | "))
		local attacker = makeAttacker(e2e, "Attacker" .. tostring(index), 0.8)
		local ok, err = pcall(function()
			e2e.kickRemote.OnServerEvent:Fire(attacker, table.unpack(args))
		end)
		check(ok, "sunucu handler #" .. tostring(index) .. " hata verdi: " .. tostring(err))
		local res = stepWorld(e2e, 0.8)
		check(#res.errors == 0,
			"kotu girdi #" .. tostring(index) .. " sonrasi dongu hata verdi: " ..
			table.concat(res.errors, " | "))
		check(res.maxSpeed <= 32.5,
			"girdi #" .. tostring(index) .. " hiz tavanini asti: " ..
			string.format("%.1f m/s", res.maxSpeed))
		local px, py, pz = e2e.ball.Position.X, e2e.ball.Position.Y, e2e.ball.Position.Z
		check(px == px and py == py and pz == pz,
			"girdi #" .. tostring(index) .. " top konumunu NaN yapti")
		check(math.abs(px) < 1e4 and math.abs(py) < 1e4 and math.abs(pz) < 1e4,
			"girdi #" .. tostring(index) .. " topu patlatti: " .. tostring(px))
	end
end)

test("NaN/sonsuz girdi varsayilana duser, sut sessizce yutulmaz", function()
	-- Beklenen davranis: sonlu olmayan sayi -> varsayilan (charge 0.5 -> 22 m/s).
	-- Eger sunucu yalnizca "velocity sonlu mu" diye bakarsa sut hic atilmaz ve
	-- oyuncu bosuna tuşa basmis olur; bu yuzden launch sayisi da olculuyor.
	local settled = settleBall(e2e)
	check(#settled.errors == 0, "sifirlama hatasi: " .. table.concat(settled.errors, " | "))
	local attacker = makeAttacker(e2e, "NaNPlayer", 0.8)
	local ok, err = pcall(function()
		e2e.kickRemote.OnServerEvent:Fire(attacker, 0 / 0, 0 / 0, 0 / 0, "instep", "R")
	end)
	check(ok, "NaN girdisi handler'i patlatti: " .. tostring(err))
	local res = stepWorld(e2e, 1.0)
	check(#res.errors == 0, "NaN sonrasi dongu hata verdi: " .. table.concat(res.errors, " | "))
	check(res.launches == 1,
		"NaN girdisi varsayilan gucle sut uretmeliydi, launch=" .. tostring(res.launches))
	check(res.maxSpeed > 18 and res.maxSpeed < 25,
		"varsayilan charge=0.5 -> ~22 m/s beklenirdi, olculen " ..
		string.format("%.1f m/s", res.maxSpeed))
	local px = e2e.ball.Position.X
	check(px == px and math.abs(px) < 1e4, "top konumu bozuldu: " .. tostring(px))
end)

test("gecersiz vurus turi ve ayak beyaz listeye duser (sut yine atilir)", function()
	-- shotType="labels" Config.SHOT icinde GERCEK bir anahtar; beyaz liste olmazsa
	-- sp.power = nil -> aritmetik hatasi. foot={} ise "hip" .. {} -> concatenate hatasi.
	local settled = settleBall(e2e)
	check(#settled.errors == 0, "sifirlama hatasi: " .. table.concat(settled.errors, " | "))
	local attacker = makeAttacker(e2e, "CheatType", 0.8)
	local ok, err = pcall(function()
		e2e.kickRemote.OnServerEvent:Fire(attacker, 1.0, 0.0, 1.0, "labels", {})
	end)
	check(ok, "gecersiz shotType/foot handler'i patlatti: " .. tostring(err))
	local res = stepWorld(e2e, 1.0)
	check(#res.errors == 0, "kare dongusu hata verdi: " .. table.concat(res.errors, " | "))
	check(res.launches == 1, "gecersiz tur yine de varsayilanla sut uretmeliydi, launch=" ..
		tostring(res.launches))
	check(res.maxSpeed > 25 and res.maxSpeed <= 32.5,
		"tam guc sut ~31 m/s olmali, olculen " .. string.format("%.1f m/s", res.maxSpeed))
end)

test("remote sozlesmesi: sunucudaki her remote istemcide var, tersi de", function()
	local serverSrc = SOURCES["server/SimLoop"]
	local clientSrc = SOURCES["client/BallView"]
	check(type(serverSrc) == "string", "SimLoop kaynagi yok")
	check(type(clientSrc) == "string", "BallView kaynagi yok")

	local created = {}
	local createdCount = 0
	for name in serverSrc:gmatch('ensureRemote%("([^"]+)"%)') do
		if not created[name] then
			createdCount = createdCount + 1
		end
		created[name] = true
	end
	check(createdCount >= 3, "sunucuda en az 3 remote beklenirdi, bulunan " .. tostring(createdCount))

	local usedCount = 0
	for name in clientSrc:gmatch('remotes:WaitForChild%("([^"]+)"') do
		usedCount = usedCount + 1
		check(created[name] == true,
			"istemci '" .. name .. "' remote'unu bekliyor ama sunucu olusturmuyor")
	end
	check(usedCount >= 3, "istemcide remote kullanimi bulunamadi")

	for name in pairs(created) do
		check(clientSrc:find('"' .. name .. '"', 1, true) ~= nil,
			"sunucu '" .. name .. "' remote'unu olusturuyor ama istemci hic kullanmiyor")
	end
end)

test("sunucu gol/kurtaris olaylarini MatchState ile yayinliyor", function()
	check(liveMock ~= nil, "canli mac (grup 10) calismadi")
	local broadcasts = 0
	local lastPayload = nil
	for _, entry in ipairs(liveMock.remoteLog) do
		if entry.name == "MatchState" and entry.direction == "FireAllClients" then
			broadcasts = broadcasts + 1
			lastPayload = entry.args[1]
		end
	end
	check(broadcasts >= 2, "yeterli MatchState yayini yok: " .. tostring(broadcasts))
	check(type(lastPayload) == "table", "MatchState payload tablo degil")
	for _, key in ipairs({ "goals", "saves", "kicks", "shots", "sag", "event" }) do
		check(lastPayload[key] ~= nil, "payload alani eksik: " .. key)
	end
	check(type(lastPayload.goals) == "number" and lastPayload.goals >= 1,
		"24 s'lik macta gol yayinlanmadi: " .. tostring(lastPayload.goals))
end)

test("istemci ve sunucu ayni Config degerlerini kullaniyor (tek kaynak)", function()
	local sharedConfig = require(clientWorld.mock.replicatedStorage.Shared.Config)
	check(sharedConfig.STUDS_PER_METER == Config.STUDS_PER_METER, "STUDS_PER_METER farkli")
	check(sharedConfig.BALL_CONTROL.chargeTime == Config.BALL_CONTROL.chargeTime, "chargeTime farkli")
	check(sharedConfig.PITCH.halfLength == Config.PITCH.halfLength, "halfLength farkli")
	check(sharedConfig.BALL_CONTROL.maxKickSpeed == Config.BALL_CONTROL.maxKickSpeed, "maxKickSpeed farkli")
	local types = sharedConfig.SHOT.types
	check(#types == #Config.SHOT.types, "vurus turi sayisi farkli")
	for i, name in ipairs(types) do
		check(name == Config.SHOT.types[i], "vurus turi sirasi farkli: " .. tostring(name))
	end
end)

print("")
print("==============================================")
print("\n== 13. Girdi dogrulama: Validate (birim) ==")

local Validate = __load("shared/Core/Validate")

test("Validate.number: NaN/inf/nil/tablo/sayisal-olmayan -> yedek deger", function()
	local nan = 0 / 0
	check(Validate.number(nan, 0.5) == 0.5, "NaN yedege dusmedi")
	check(Validate.number(math.huge, 0.5) == 0.5, "+inf yedege dusmedi")
	check(Validate.number(-math.huge, 0.5) == 0.5, "-inf yedege dusmedi")
	check(Validate.number(nil, 0.5) == 0.5, "nil yedege dusmedi")
	check(Validate.number({}, 0.5) == 0.5, "tablo yedege dusmedi")
	check(Validate.number("abc", 0.5) == 0.5, "sayisal olmayan string yedege dusmedi")
	check(Validate.number(0.25, 0.5) == 0.25, "gecerli sayi degisti")
	check(Validate.number("0.75", 0.5) == 0.75, "sayisal string kabul edilmedi")
	check(Validate.number(0, 0.5) == 0, "sifir yedege dustu (0 gecersiz sayildi)")
end)

test("Validate.clamp: once sonluluk, sonra kisitlama", function()
	local nan = 0 / 0
	-- Kritik ayrinti: saf math.max/min zinciri NaN'i SINIRA cevirir (math.min(1, NaN)
	-- karsilastirmasi false -> 1). Yani istemci NaN gondererek "tam guc" alabilir.
	-- Validate.clamp once sonlulugu denetledigi icin NaN yedek degere duser.
	check(Validate.clamp(nan, 0, 1, 0.5) == 0.5, "NaN sinira degil yedek degere dusmeli")
	check(Validate.clamp(5, 0, 1, 0.5) == 1, "ust sinira kisitlanmadi")
	check(Validate.clamp(-5, 0, 1, 0.5) == 0, "alt sinira kisitlanmadi")
	check(Validate.clamp(0.3, 0, 1, 0.5) == 0.3, "araliktaki deger bozuldu")
	check(Validate.clamp(nil, -3.3, 3.3, 0) == 0, "nil -> yedek")
	check(Validate.clamp(math.huge, 0.2, 2.3, 1.0) == 1.0, "inf -> yedek degere dusmedi")
end)

test("Validate.vec3: yalniz sonlu ve TAM {x,y,z} gecer", function()
	local nan = 0 / 0
	check(Validate.vec3({ x = 1, y = 2, z = 3 }) == true, "gecerli vektor reddedildi")
	check(Validate.vec3({ x = -30, y = 8.2, z = 0.5 }) == true, "gercek sut hizi reddedildi")
	check(Validate.vec3({ x = nan, y = 0, z = 0 }) == false, "NaN bilesen kabul edildi")
	check(Validate.vec3({ x = 0, y = math.huge, z = 0 }) == false, "inf bilesen kabul edildi")
	check(Validate.vec3({ x = 0, y = 0 }) == false, "z eksik ama kabul edildi (ipairs tuzağı)")
	check(Validate.vec3({ x = 0 }) == false, "y ve z eksik ama kabul edildi")
	check(Validate.vec3({}) == false, "bos tablo kabul edildi")
	check(Validate.vec3({ x = 0, y = 0, z = "1" }) == false, "string bilesen kabul edildi")
	check(Validate.vec3(nil) == false, "nil kabul edildi")
	check(Validate.vec3("hiz") == false, "string kabul edildi")
	check(Validate.vec3(30) == false, "sayi kabul edildi")
	check(Validate.vec3({ x = 2e6, y = 0, z = 0 }) == false, "buyukluk sinirini asan deger kabul edildi")
end)

test("Validate.shotType: beyaz liste disindaki her sey varsayilana duser", function()
	local allowed = Validate.shotTypeSet({ types = { "place", "instep", "drive", "outside" } })
	check(Validate.shotType("drive", allowed) == "drive", "gecerli tur degisti")
	check(Validate.shotType("place", allowed) == "place", "gecerli tur degisti")
	-- Config.SHOT.labels ve Config.SHOT.types GERCEK tablolar: beyaz liste olmasa
	-- KickAnim icinde sp.power = nil -> aritmetik hatasi.
	check(Validate.shotType("labels", allowed) == Validate.DEFAULT_SHOT_TYPE, "Config.SHOT.labels tur sayildi")
	check(Validate.shotType("types", allowed) == Validate.DEFAULT_SHOT_TYPE, "Config.SHOT.types tur sayildi")
	check(Validate.shotType(nil, allowed) == Validate.DEFAULT_SHOT_TYPE, "nil tur kabul edildi")
	check(Validate.shotType({}, allowed) == Validate.DEFAULT_SHOT_TYPE, "tablo tur kabul edildi")
	check(Validate.shotType(7, allowed) == Validate.DEFAULT_SHOT_TYPE, "sayi tur kabul edildi")
	check(Validate.shotType(true, allowed) == Validate.DEFAULT_SHOT_TYPE, "boolean tur kabul edildi")
	local empty = Validate.shotTypeSet(nil)
	check(empty[Validate.DEFAULT_SHOT_TYPE] == true, "Config yokken gecerli tur kalmadi")
	check(Validate.shotType("place", empty) == Validate.DEFAULT_SHOT_TYPE, "bos listede tur kabul edildi")
	check(Validate.shotType(nil, nil) == Validate.DEFAULT_SHOT_TYPE, "allowed verilmeden cagri")
end)

test("Validate.foot: yalniz L/R, diger her sey nil (animasyon otomatik secer)", function()
	check(Validate.foot("L") == "L", "sol ayak degisti")
	check(Validate.foot("R") == "R", "sag ayak degisti")
	check(Validate.foot("l") == nil, "kucuk harf kabul edildi (concatenate riski)")
	check(Validate.foot({}) == nil, "tablo kabul edildi")
	check(Validate.foot(nil) == nil, "nil -> nil olmadi")
	check(Validate.foot(1) == nil, "sayi kabul edildi")
	check(Validate.foot("Left") == nil, "'Left' kabul edildi")
end)

test("Validate beyaz listesi gercek Config.SHOT ile uyumlu (KickAnim patlamaz)", function()
	local allowed = Validate.shotTypeSet(Config.SHOT)
	check(type(Config.SHOT.types) == "table", "Config.SHOT.types tablo degil")
	for _, typeName in ipairs(Config.SHOT.types) do
		check(Validate.shotType(typeName, allowed) == typeName, "Config turu reddedildi: " .. tostring(typeName))
		local sp = Config.SHOT[typeName]
		check(type(sp) == "table", "Config.SHOT[" .. tostring(typeName) .. "] yok -> KickAnim nil indexler")
		check(type(sp and sp.power) == "number", "Config.SHOT." .. tostring(typeName) .. ".power sayi degil -> aritmetik hatasi")
	end
	check(Validate.shotType(Validate.DEFAULT_SHOT_TYPE, allowed) == Validate.DEFAULT_SHOT_TYPE, "varsayilan tur Config'te yok")
	check(type(Config.SHOT[Validate.DEFAULT_SHOT_TYPE]) == "table", "varsayilan tur icin Config girdisi yok")
end)

print("\n== 14. Nisan girdisi: fare -> dünya isini -> AimMarker ==")

-- Kamera Scriptable ve sabit bir ofsette durur; bu yüzden kameranin LookVector'u
-- oyuncunun baktigi yer DEGILDIR. Nisan FARE ile alinir: computeAim once
-- UserInputService:GetMouseLocation() + camera:ViewportPointToRay ile isin kurar,
-- isin kale duzlemini onden kesmiyorsa kamera bakisina duser.
-- Bu grup o baglantiyi kilitler: mouseRay kaldirilirsa fare hareketi nisan
-- noktasini degistirmeyi birakir ve asagidaki testler duser.
local aimWorld = nil

test("fare ekrani nisana bagli: AimMarker fareyle birlikte kayiyor", function()
	aimWorld = bootWorld({ striker = false })
	check(aimWorld.installOk and aimWorld.serverOk and aimWorld.clientOk,
		"dunya kurulamadi: " .. tostring(aimWorld.installErr or aimWorld.serverErr or aimWorld.clientErr))
	placePlayerAtBall(aimWorld, 0.8)
	-- Fare nişanı 3. şahıs/izleme kipinde anlamlıdır: 1. şahısta fare ekranın
	-- ortasına kilitlidir ve nişan karakterin baktığı yöndür (bkz. sonraki test).
	aimWorld.mock.pressKey("C") -- 1. sahis -> 3. sahis
	stepWorld(aimWorld, 0.1)

	local marker = aimWorld.mock.workspace:FindFirstChild("AimMarker")
	check(marker ~= nil, "workspace.AimMarker yok (nisan gostergesi hic kurulmamis)")
	local vp = aimWorld.mock.viewportSize
	check(vp and vp.X > 0 and vp.Y > 0, "mock viewport boyutu gecersiz")

	-- Fareyi ekran noktasina tasi, bir kac kare adimla, nisan noktasini oku
	local function aimAt(x, y)
		aimWorld.mock.setMouseLocation(x, y)
		local stepped = stepWorld(aimWorld, 0.05)
		check(#stepped.errors == 0, "nisan kareleri hata verdi: " .. table.concat(stepped.errors, " | "))
		check(marker.Transparency < 1, "nisan yok sayildi (AimMarker gizli) -> computeAim nil dondu")
		return marker.CFrame.Position
	end

	local center = aimAt(vp.X * 0.5, vp.Y * 0.5)
	local right = aimAt(vp.X * 0.85, vp.Y * 0.5)
	local left = aimAt(vp.X * 0.15, vp.Y * 0.5)
	local up = aimAt(vp.X * 0.5, vp.Y * 0.2)
	local down = aimAt(vp.X * 0.5, vp.Y * 0.8)

	-- YATAY: sag/sol nisan noktasini ters yonlerde kaydirmali
	check(math.abs(right.Z - left.Z) > 0.5,
		string.format("fare sag/sol nisani degistirmiyor: rightZ=%.2f leftZ=%.2f (stud)", right.Z, left.Z))
	check((right.Z - center.Z) * (left.Z - center.Z) < 0,
		"sag ve sol ayni yone kaydi (nisan ters baglanmis)")
	-- DIKEY: yukarı/asagi nisan yuksekligini degistirmeli
	check(math.abs(up.Y - down.Y) > 0.2,
		string.format("fare yukarı/asagi nisan yuksekligini degistirmiyor: upY=%.2f downY=%.2f", up.Y, down.Y))

	-- Her ornek saha sinirlari icinde kalmali (z: +/-3.3 m, y: 0.25..2.3 m)
	local zLimit = 3.3 * STUDS_PER_METER + 0.01
	for _, p in ipairs({ center, right, left, up, down }) do
		check(math.abs(p.Z) <= zLimit, "nisan z sinirini asti: " .. string.format("%.2f stud", p.Z))
		check(p.Y >= 0.25 * STUDS_PER_METER - 0.01 and p.Y <= 2.3 * STUDS_PER_METER + 0.01,
			"nisan y sinirini asti: " .. string.format("%.2f stud", p.Y))
	end
end)

test("asiri fare konumu sutu yutmuyor (kamera bakisina duser, sut yine atilir)", function()
	check(aimWorld ~= nil, "onceki nisan testi dunya kurmadi")
	-- Ekrani kosesi: isin kale duzlemini onden kesmeyebilir. computeAim nil
	-- donerse fireKick hic FireServer cagirmaz ve sut SESSIZCE yutulur.
	aimWorld.mock.setMouseLocation(1, 1)
	local attacker = makeAttacker(aimWorld, "Aimer", 0.8)
	aimWorld.mock.pressKey("Space")
	local charge = stepWorld(aimWorld, 1.0)
	check(#charge.errors == 0, "guc toplarken hata: " .. table.concat(charge.errors, " | "))
	aimWorld.mock.releaseKey("Space")
	local res = stepWorld(aimWorld, 1.2)
	check(#res.errors == 0, "sut sirasinda hata: " .. table.concat(res.errors, " | "))
	check(res.launches >= 1,
		"kose nisaninda sut atilmadi (launch " .. tostring(res.launches) .. ") -> nisan sessizce yutuluyor")
	check(res.maxSpeed > 20, "sut hizi dusuk: " .. string.format("%.1f m/s", res.maxSpeed))
	check(attacker ~= nil, "saldirgan kurulamadi")
end)

-- 1. ŞAHISTA nişan karakterin baktığı yöndür (fare ekranın ortasına kilitlidir).
-- Ayrıca hiçbir ışın kaleyi önden kesmese bile nişan kale ortasına düşer; şut
-- SESSİZCE YUTULMAZ (computeAim nil dönerse fireKick hiç FireServer çağırmaz).
test("1. sahista nisan karakterin baktigi yone bagli ve sut yutulmuyor", function()
	local w = bootWorld({ striker = false })
	check(w.installOk and w.serverOk and w.clientOk,
		"dunya kurulamadi: " .. tostring(w.installErr or w.serverErr or w.clientErr))
	local settled = settleBall(w)
	check(#settled.errors == 0, "top oturtulurken hata: " .. table.concat(settled.errors, " | "))
	placePlayerAtBall(w, 0.8)
	local marker = w.mock.workspace:FindFirstChild("AimMarker")
	check(marker ~= nil, "workspace.AimMarker yok")

	-- Fare bilerek köşede: 1. şahısta nişanı DEĞİŞTİRMEMELİ
	w.mock.setMouseLocation(1, 1)
	local s1 = stepWorld(w, 0.2)
	check(#s1.errors == 0, "kareler hata verdi: " .. table.concat(s1.errors, " | "))
	check(marker.Transparency < 1, "1. sahista nisan yok sayildi (computeAim nil dondu)")
	local straight = marker.CFrame.Position
	check(math.abs(straight.X - 52.5 * STUDS_PER_METER) < 0.5,
		"1. sahista nisan kale duzleminde degil: x=" .. string.format("%.1f", straight.X))

	w.mock.setMouseLocation(1200, 900)
	stepWorld(w, 0.2)
	local straight2 = marker.CFrame.Position
	check(math.abs(straight2.Z - straight.Z) < 0.05 and math.abs(straight2.Y - straight.Y) < 0.05,
		"1. sahista fare konumu nisani degistirdi (fare ortada kilitli olmali): " ..
		string.format("%.2f -> %.2f", straight.Z, straight2.Z))

	-- Karakteri sola çevir: nişan da kaymalı
	local pos = w.hrp.Position
	w.hrp.CFrame = CFrame.lookAt(pos, pos + Vector3.new(10, 0, -6))
	stepWorld(w, 0.25)
	local turned = marker.CFrame.Position
	check(math.abs(turned.Z - straight.Z) > 0.5, string.format(
		"1. sahista karakter donunce nisan kaymadi: straightZ=%.2f turnedZ=%.2f", straight.Z, turned.Z))
	check(turned.Z < straight.Z, "sola donus nisani +z yonune kaydirdi (ters baglanmis)")

	-- Şut çıkmalı
	w.mock.pressKey("Space")
	local charge = stepWorld(w, 1.0)
	check(#charge.errors == 0, "guc toplarken hata: " .. table.concat(charge.errors, " | "))
	w.mock.releaseKey("Space")
	local res = stepWorld(w, 1.2)
	check(#res.errors == 0, "sut sirasinda hata: " .. table.concat(res.errors, " | "))
	check(res.launches >= 1,
		"1. sahista sut atilmadi (launch " .. tostring(res.launches) .. ") -> nisan sessizce yutuluyor")
end)

-- Karakterin sırtı kaleye dönükken bile şut çıkmalı: hiçbir ışın kale düzlemini
-- önden kesmez; nişan kale ortasına düşer (eski kodda computeAim nil döner,
-- fireKick hiç FireServer çağırmaz ve şut SESSİZCE yutulurdu).
test("kaleye sirti donukken bile sut atiliyor (nisan kale ortasina duser)", function()
	local w = bootWorld({ striker = false })
	check(w.installOk and w.serverOk and w.clientOk, "dunya kurulamadi")
	local settled = settleBall(w)
	check(#settled.errors == 0, "top oturtulurken hata: " .. table.concat(settled.errors, " | "))
	placePlayerAtBall(w, 0.8)
	-- Karakter -x yönüne baksın (kaleye sırtı dönük)
	local bp = w.ball.Position
	local pos = Vector3.new(bp.X - 0.8 * STUDS_PER_METER, bp.Y, bp.Z)
	w.hrp.CFrame = CFrame.lookAt(pos, pos + Vector3.new(-10, 0, 0))
	w.hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	stepWorld(w, 0.2)
	local marker = w.mock.workspace:FindFirstChild("AimMarker")
	check(marker.Transparency < 1, "sirti donuk karakterde nisan yok sayildi (sut yutulacak)")

	w.mock.pressKey("Space")
	stepWorld(w, 1.0)
	w.mock.releaseKey("Space")
	local res = stepWorld(w, 1.2)
	check(#res.errors == 0, "sut sirasinda hata: " .. table.concat(res.errors, " | "))
	check(res.launches >= 1,
		"kaleye sirti donukken sut atilmadi (launch " .. tostring(res.launches) .. ")")
end)

print("  GECEN: " .. tostring(passed) .. "   BASARISIZ: " .. tostring(failed))
if failed > 0 then
	print("  Basarisiz: " .. table.concat(failures, ", "))
end
print("==============================================")
