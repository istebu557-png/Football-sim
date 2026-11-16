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

print("")
print("==============================================")
print("  GECEN: " .. tostring(passed) .. "   BASARISIZ: " .. tostring(failed))
if failed > 0 then
	print("  Basarisiz: " .. table.concat(failures, ", "))
end
print("==============================================")
