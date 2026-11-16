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
		local dir = Vec3.unit(Vec3.add(Vec3.scale(facingDir, 0.80), Vec3.scale(flatDir, 0.20)))
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
