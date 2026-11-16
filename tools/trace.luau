--[[
	Fizik izi üreteci (yalnızca geliştirme aracı).

	Motorun gerçek çıktısını JSON olarak döker; preview/index.html bunu çizip
	topun nasıl davrandığını gösterir. Yani görsel, elle çizilmiş bir animasyon
	değil — Buradaki 240 Hz simülasyonun birebir kaydı.
]]

local Config = __load("shared/Config")
local Vec3 = __load("shared/Core/Vec3")
local Ballistics = __load("shared/Core/Ballistics")
local Ball = __load("shared/Physics/Ball")
local Pitch = __load("shared/Physics/Pitch")
local Sim = __load("shared/Sim")
local Net = __load("shared/Physics/Net")

local R = Config.BALL.radius
local SAMPLE_EVERY = 4 -- 240 Hz -> 60 Hz kayıt

local function num(v)
	return string.format("%.4f", v)
end

local function jsonVec(v)
	return "[" .. num(v.x) .. "," .. num(v.y) .. "," .. num(v.z) .. "]"
end

local function jsonPath(samples)
	local parts = {}
	for i = 1, #samples do
		parts[i] = jsonVec(samples[i])
	end
	return "[" .. table.concat(parts, ",") .. "]"
end

--[[ Bir vuruşu simüle eder ve iz kaydeder.
	opts: { from, to?, elevation?, speed, spin, highArc?, maxSeconds? }]]
local function simulate(opts)
	local sim = Sim.new({ seed = 1 })
	local goalNet = nil
	if opts.net then
		goalNet = Net.new(Config, 1)
		sim.nets[1] = goalNet
	end
	local from = opts.from
	local velocity = opts.velocity
	if not velocity then
		velocity = Ballistics.solveLaunch(from, opts.to, opts.speed, Config.GRAVITY, opts.highArc)
		if not velocity then
			return nil
		end
	end

	sim.ball:setState(from, velocity, opts.spin or Vec3.new(0, 0, 0))

	local samples = { Vec3.new(from.x, from.y, from.z) }
	local maxHeight = from.y
	local goal = nil
	local goalSpeed = nil
	local maxSag = 0
	local ticks = 240 * (opts.maxSeconds or 4)

	for i = 1, ticks do
		-- Gol anındaki hızı kaydet: ağ topu tuttuğu için tick sonrası hız 0 olur.
		local speedBefore = Vec3.length(sim.ball.vel)
		sim:tick()
		local p = sim.ball.pos
		if p.y > maxHeight then
			maxHeight = p.y
		end
		if i % SAMPLE_EVERY == 0 then
			samples[#samples + 1] = Vec3.new(p.x, p.y, p.z)
		end
		if goalNet and goalNet.sag > maxSag then
			maxSag = goalNet.sag
		end

		if sim.lastGoal then
			goal = sim.lastGoal.side
			goalSpeed = speedBefore
			sim.lastGoal = nil
			if not opts.net then
				break
			end
		end
		local inNet = goalNet and goalNet:isInsideGoalBox(p)
		if Pitch.isOutOfPlay(p, R) and not inNet then
			break
		end
		-- Ağda durduysa izlemeyi bitir
		if goalNet and sim.ball:speed() < 0.25 and i > 30 then
			break
		end
		if sim.ball.vel.x * sim.ball.vel.x + sim.ball.vel.y * sim.ball.vel.y + sim.ball.vel.z * sim.ball.vel.z < 1e-6 then
			break
		end
	end

	-- Düz çizgiden sapma (falso etkisi): başlangıç-hedef doğrusuna dik mesafe
	local curve = 0
	if opts.to then
		local line = Vec3.unit(Vec3.new(opts.to.x - from.x, 0, opts.to.z - from.z))
		for _, p in ipairs(samples) do
			local rel = Vec3.new(p.x - from.x, 0, p.z - from.z)
			local along = Vec3.dot(rel, line)
			local perp = Vec3.sub(rel, Vec3.scale(line, along))
			local d = Vec3.length(perp)
			if d > math.abs(curve) then
				curve = (Vec3.dot(perp, Vec3.cross(Vec3.UP, line)) >= 0) and d or -d
			end
		end
	end

	return {
		aim = opts.to,
		samples = samples,
		maxHeight = maxHeight,
		goal = goal,
		curve = curve,
		postHits = sim.ball.postHits,
		maxSag = maxSag,
		final = sim.ball.pos,
		speedStart = Vec3.length(velocity),
		speedEnd = (opts.net and Vec3.length(sim.ball.vel)) or goalSpeed or Vec3.length(sim.ball.vel),
		time = sim.time,
	}
end

local shots = {}

-- 1) Düz şut: penaltı noktasından kaleye, hava direnci etkisi görünsün
shots[#shots + 1] = {
	id = "duz",
	label = "Düz şut (drag)",
	desc = "27 m/s, penaltı noktasından kale ortasına. Direnç hızı ~27'den düşürür.",
	data = simulate({
		from = Vec3.new(41.5, R, 0),
		to = Vec3.new(52.5, 1.0, 0),
		speed = 27,
	}),
}

-- 2) Falso: 3 metre bükülen serbest vuruş
shots[#shots + 1] = {
	id = "falso",
	label = "Falso (Magnus)",
	desc = "27 m/s, 45 rad/s yan falso. Hedefin ~3 m dışına nişanlı, spin onu kaleye büker.",
	data = simulate({
		from = Vec3.new(30, R, 8),
		to = Vec3.new(52.5, 2.0, 0.2),
		speed = 27,
		spin = Vec3.new(0, 45, 0),
	}),
}

-- 3) Aşırtma: kaleci üstünden çip, backspin ile
shots[#shots + 1] = {
	id = "asirtma",
	label = "Aşırtma (çip)",
	desc = "14 m/s çip + backspin. Tepe 2.7 m: kaleci üstünden, üst direk altından.",
	data = simulate({
		from = Vec3.new(38.5, R, 0),
		to = Vec3.new(52.5, 1.8, 0),
		speed = 14,
		spin = Vec3.new(0, 0, 20),
	}),
}

-- 4) Direk: tam direğe nişanlı şut -> sekerek dışarı
shots[#shots + 1] = {
	id = "direk",
	label = "Direk (çarpışma)",
	desc = "24 m/s, tam direğe nişanlı. Sürekli çarpışma testi topu sektirir: gol değil.",
	data = simulate({
		from = Vec3.new(41.5, R, 3.0),
		to = Vec3.new(52.5, 1.2, 3.66),
		speed = 24,
		maxSeconds = 2.2,
	}),
}

-- 5) File: kaleye giren şutun ağda sönümlenmesi
shots[#shots + 1] = {
	id = "file",
	label = "File (ağ)",
	desc = "24 m/s ile kaleye: ağ enerjiyi yutar, esner ve top içeride durur — geri sekmez.",
	data = simulate({
		from = Vec3.new(41.5, R, 0),
		to = Vec3.new(52.5, 1.1, 0),
		speed = 24,
		net = true,
		maxSeconds = 2.5,
	}),
}

-- 6) Sekme: 2 m'den düşen topun dikey izi
local dropshot = { samples = {}, maxHeight = 2, goal = nil, curve = 0 }
do
	local b = Ball.new(Config, Vec3.new(0, 2 + R, 0))
	b:setState(Vec3.new(0, 2 + R, 0), Vec3.new(0, 0, 0), Vec3.new(0, 0, 0))
	dropshot.samples[1] = Vec3.new(0, b.pos.y, 0)
	for i = 1, 240 * 4 do
		b:step(Config.FIXED_DT)
		if i % SAMPLE_EVERY == 0 then
			dropshot.samples[#dropshot.samples + 1] = Vec3.new(i * Config.FIXED_DT, b.pos.y, 0)
		end
	end
	dropshot.speedStart = 0
	dropshot.speedEnd = 0
	dropshot.time = 4
	dropshot.final = b.pos
	dropshot.bounces = b.contacts
	dropshot.drop = true
	dropshot.postHits = 0
end
shots[#shots + 1] = {
	id = "sekme",
	label = "Zemin sekmesi",
	desc = "2 m'den düşen top: e=0.74 ile ~1.1 m seker, sonra sönümlenir.",
	data = dropshot,
}

-- JSON çıktısı
local out = {}
out[#out + 1] = "{"
out[#out + 1] = '"pitch":{"length":' .. num(Config.PITCH.length) .. ',"width":' .. num(Config.PITCH.width) .. "},"
out[#out + 1] = '"ball":{"radius":' .. num(R) .. ',"mass":' .. num(Config.BALL.mass) .. "},"
out[#out + 1] = '"simHz":' .. tostring(Config.SIM_HZ) .. ","
out[#out + 1] = '"shots":['
for i, shot in ipairs(shots) do
	local d = shot.data
	out[#out + 1] = "{"
	out[#out + 1] = '"id":"' .. shot.id .. '",'
	out[#out + 1] = '"label":"' .. shot.label .. '",'
	out[#out + 1] = '"desc":"' .. shot.desc .. '",'
	out[#out + 1] = '"path":' .. jsonPath(d.samples) .. ","
	out[#out + 1] = '"maxHeight":' .. num(d.maxHeight) .. ","
	out[#out + 1] = '"curve":' .. num(d.curve) .. ","
	out[#out + 1] = '"speedStart":' .. num(d.speedStart or 0) .. ","
	out[#out + 1] = '"speedEnd":' .. num(d.speedEnd or 0) .. ","
	out[#out + 1] = '"time":' .. num(d.time or 0) .. ","
	out[#out + 1] = '"goal":' .. (d.goal and ('"' .. d.goal .. '"') or "null") .. ","
	out[#out + 1] = '"bounces":' .. tostring(d.bounces or 0) .. ","
	out[#out + 1] = '"postHits":' .. tostring(d.postHits or 0) .. ","
	out[#out + 1] = '"maxSag":' .. num(d.maxSag or 0) .. ","
	out[#out + 1] = '"type":"' .. (d.drop and "drop" or "shot") .. '",'
	out[#out + 1] = '"aim":' .. (shot.data.aim and jsonVec(shot.data.aim) or "null")
	out[#out + 1] = (i < #shots) and "}," or "}"
end
out[#out + 1] = "]}"

io.write(table.concat(out, ""))
