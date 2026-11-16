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
