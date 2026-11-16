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
