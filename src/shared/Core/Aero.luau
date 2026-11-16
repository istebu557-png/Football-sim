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
