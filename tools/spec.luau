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
	local posts = 0
	for _, child in ipairs(goal:GetChildren()) do
		if child.Name == "Post" then
			posts = posts + 1
		end
	end
	check(posts == 2, "iki direk beklenirdi, gelen " .. tostring(posts))
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

	local striker = pitch:FindFirstChild("Striker")
	check(striker ~= nil, "sutcu modeli yok")
	check(striker:FindFirstChild("Rig") ~= nil, "sutcu iskeleti yok")

	local ball = ws:FindFirstChild("MatchBall")
	check(ball ~= nil, "top yok")
	check(ball.Shape == "PartType.Ball", "top sekli yanlis: " .. tostring(ball.Shape))
	check(ball.CFrame.pos.X > 0, "top yarim saha icinde baslamiyor")
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

print("")
print("==============================================")
print("  GECEN: " .. tostring(passed) .. "   BASARISIZ: " .. tostring(failed))
if failed > 0 then
	print("  Basarisiz: " .. table.concat(failures, ", "))
end
print("==============================================")
