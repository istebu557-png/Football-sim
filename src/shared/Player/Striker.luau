--[[
	Striker — sunucu tarafındaki şutçu NPC'si (prosedürel iskeletle çizilir).

	Neden NPC? Animasyonun tamamı sunucuda, kodla üretiliyor; gerçek bir Roblox
	karakteri kendi Animate script'iyle çakışır. Bu şutçu:
	  * topa yürür (adım döngüsü gerçek hıza bağlı: kayma yok),
	  * ayak mesafesine gelince topun GERÇEK konumuna göre şut pozisyonu seçer,
	  * temas anında (0.24 s) top ayrılır — animasyon nedensel, süs değil,
	  * her şutta farklı köşe/yükseklik hedefler: kaleci her seferinde farklı atlar.

	Roblox API'si kullanmaz: aynı kod testte ölçülebilir.
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)
local WalkCycle = require(script.Parent.Parent.Anim.WalkCycle)
local KickAnim = require(script.Parent.Parent.Anim.KickAnim)
local Ease = require(script.Parent.Parent.Anim.Ease)

local Striker = {}
Striker.__index = Striker

Striker.REACH = 1.00 -- şut için topun ayağa uzaklığı (m)
Striker.WALK_SPEED = 5.2 -- yaklaşma hızı (m/s)
Striker.COOLDOWN = 1.4 -- şutlar arası bekleme (s)
Striker.MAX_WAIT = 1.2 -- hareketli topa bekleme süresi (s)

local clamp01 = Ease.clamp01

-- Şut hedefleri: döngüyle değişir (alt köşe -> üst köşe -> orta)
local TARGETS = {
	{ z = 2.55, y = 0.32 },
	{ z = -2.40, y = 1.90 },
	{ z = 1.05, y = 0.85 },
}

function Striker.new(cfg, opts)
	opts = opts or {}
	local P = cfg.PITCH
	local side = opts.side or 1
	local pos = opts.pos or Vec3.new(P.halfLength * 0.30, 0, 0.8)
	return setmetatable({
		cfg = cfg,
		side = side,
		pos = pos,
		vel = Vec3.new(0, 0, 0),
		facing = Vec3.yaw(Vec3.new(side, 0, 0)),
		state = "idle", -- idle | approach | wait | kick
		kick = nil,
		kickT = 0,
		cooldown = 0,
		waitTimer = 0,
		walkPhase = 0,
		time = 0,
		shots = 0,
		aimIndex = 0,
		target = nil,
		speed = 0,
	}, Striker)
end

function Striker:goalPoint()
	local P = self.cfg.PITCH
	return Vec3.new(self.side * P.halfLength, 0, 0)
end

-- Şut için gereken geometri: topun ayağa göre yan/ön/ileri bileşenleri
function Striker:ballGeometry(ball)
	local toBall = Vec3.sub(ball.pos, self.pos)
	local forward = Vec3.new(math.cos(self.facing), 0, math.sin(self.facing))
	local right = Vec3.cross(forward, Vec3.new(0, 1, 0))
	local flat = Vec3.withY(toBall, 0)
	return {
		dist = Vec3.length(flat),
		lateral = Vec3.dot(flat, right),
		forward = Vec3.dot(flat, forward),
		height = ball.pos.y,
	}
end

function Striker:beginKick(ball)
	local geo = self:ballGeometry(ball)
	local goal = self:goalPoint()
	local dx = goal.x - ball.pos.x
	local dz = goal.z - ball.pos.z
	local distGoal = math.sqrt(dx * dx + dz * dz)

	self.aimIndex = (self.aimIndex % #TARGETS) + 1
	local aim = TARGETS[self.aimIndex]

	-- Uzaktan sert, yakından kontrollü
	local charge = clamp01(0.42 + distGoal / 42)
	local speed = 15 + 11 * charge

	self.kick = KickAnim.new({
		ballHeight = geo.height,
		ballLateral = geo.lateral,
		ballForward = geo.forward,
		charge = charge,
	})
	self.kickT = 0
	self.speed = speed
	self.target = Vec3.new(goal.x, aim.y, aim.z)
	self.state = "kick"
	self.shots = self.shots + 1
	return self.kick
end

--[[ Bir adım. Dönüş: nil veya {
		type = "shoot", kick = KickAnim, target = Vec3 (metre), speed = m/s } ]]
function Striker:step(dt, ball)
	self.time = self.time + dt
	if self.cooldown > 0 then
		self.cooldown = math.max(0, self.cooldown - dt)
	end

	-- 1) Şut animasyonu sürüyor: sadece zaman ilerler
	if self.kick then
		local before = self.kickT
		self.kickT = self.kickT + dt
		-- Hazırlık boyunca ayak yere basar; itiş hızı sabit kalır (gerçekçi)
		local event = nil
		if before < KickAnim.CONTACT_TIME and self.kickT >= KickAnim.CONTACT_TIME then
			event = {
				type = "shoot",
				kick = self.kick,
				target = self.target,
				speed = self.speed,
				charge = self.kick.charge,
			}
		end
		if self.kickT >= self.kick:duration() then
			self.kick = nil
			self.kickT = 0
			self.cooldown = Striker.COOLDOWN
			self.state = "idle"
		end
		self.vel = Vec3.new(0, 0, 0)
		return event
	end

	-- 2) Topa yaklaş
	local geo = self:ballGeometry(ball)
	local ballSpeed = ball:speed()

	if geo.dist > Striker.REACH then
		local dir = Vec3.unit(Vec3.withY(Vec3.sub(ball.pos, self.pos), 0))
		local want = Striker.WALK_SPEED
		-- Yavaşlayarak yaklaş: hedefe 0.4 m kalınca yavaşla
		if geo.dist < 2.2 then
			want = Striker.WALK_SPEED * clamp01((geo.dist - Striker.REACH) / 1.2) + 0.6
		end
		self.vel = Vec3.scale(dir, want)
		self.pos = Vec3.add(self.pos, Vec3.scale(self.vel, dt))
		self.facing = Vec3.yaw(dir)
		self.walkPhase = (self.walkPhase + Vec3.length(self.vel) * dt / WalkCycle.STRIDE) % 1
		self.state = "approach"
		return nil
	end

	self.vel = Vec3.new(0, 0, 0)

	-- 3) Top hızlıysa bekle (ayağına gelsin)
	if ballSpeed > 1.2 then
		self.waitTimer = self.waitTimer + dt
		self.state = "wait"
		if self.waitTimer < Striker.MAX_WAIT then
			return nil
		end
	else
		self.waitTimer = 0
	end

	-- 4) Top kaleye dönük mü? Değilse önce etrafından dolaş (kale arkasına geçme)
	if self.cooldown > 0 then
		self.state = "idle"
		return nil
	end

	self.facing = Vec3.yaw(Vec3.withY(Vec3.sub(self:goalPoint(), self.pos), 0))
	self:beginKick(ball)
	return nil
end

-- Görsel poz: şut sürüyorsa şut, değilse adım döngüsü
function Striker:pose()
	if self.kick then
		return self.kick:sample(self.kickT).pose
	end
	local speed = Vec3.length(self.vel)
	return WalkCycle.sample(speed, self.walkPhase, self.time)
end

function Striker:isKicking()
	return self.kick ~= nil
end

return Striker
