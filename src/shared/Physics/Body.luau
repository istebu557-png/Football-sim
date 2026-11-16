--[[
	Body — hareketli gövde (oyuncu/kaleci) ile top çarpışması.

	Oyuncu ve kaleci dikey bir kapsül (silindir) olarak modellenir. Top küre.
	Çarpışma anında:
	  * top yüzeyin dışına taşınır,
	  * gövdeye GÖRE bağıl hız yansıtılır (koşan oyuncu topa hız katar),
	  * teğetsel sürtünme uygulanır.

	Neden bağıl hız? Sabit gövdeye çarpan top sadece seker; koşan bir oyuncunun
	bacağına çarpan top ise oyuncunun hızını da alır. Bu, "top oyuncudan sekiyor"
	hissini veren kritik detaydır.

	Roblox API'si kullanmaz -> test edilebilir.
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)

local Body = {}

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

-- Bir noktaya, dikey doğru parçası üzerindeki en yakın nokta.
local function closestOnVerticalSegment(point, base, height)
	local y = clamp(point.y, base.y, base.y + height)
	return Vec3.new(base.x, y, base.z)
end

--[[ Topu gövdeye karşı çözer. body:
	{ pos = Vec3 (ayak seviyesi), vel = Vec3, radius, height, restitution, hits }
	Dönüş: çarpıştı mı? ]]
function Body.collide(ball, body)
	if not body or not body.pos then
		return false
	end
	local ballR = ball.cfg.BALL.radius
	local bodyR = body.radius or 0.42
	local height = body.height or 1.8
	local e = body.restitution or 0.42

	local closest = closestOnVerticalSegment(ball.pos, body.pos, height)
	local delta = Vec3.sub(ball.pos, closest)
	local dist = Vec3.length(delta)
	local minDist = ballR + bodyR

	if dist >= minDist then
		return false
	end

	local n
	if dist > 1e-9 then
		n = Vec3.scale(delta, 1 / dist)
	else
		n = Vec3.negate(Vec3.unit(ball.vel))
		if Vec3.lengthSq(n) < 1e-9 then
			n = Vec3.new(1, 0, 0)
		end
	end

	-- Topu dışarı taşı
	ball.pos = Vec3.add(closest, Vec3.scale(n, minDist + 1e-4))

	-- Bağıl hız: top - gövde
	local bodyVel = body.vel or Vec3.ZERO
	local relVel = Vec3.sub(ball.vel, bodyVel)
	local vn = Vec3.dot(relVel, n)

	if vn < 0 then
		-- Normal bileşen: yansıt ve gövde hızını ekle
		local newRel = Vec3.sub(relVel, Vec3.scale(n, (1 + e) * vn))

		-- Teğetsel sürtünme (top ayağa sürtünür)
		local normalPart = Vec3.scale(n, Vec3.dot(newRel, n))
		local tangent = Vec3.sub(newRel, normalPart)
		local tangentSpeed = Vec3.length(tangent)
		if tangentSpeed > 1e-6 then
			local mu = body.friction or 0.30
			local reduce = min(tangentSpeed, mu * (1 + e) * (-vn))
			tangent = Vec3.scale(tangent, 1 - reduce / tangentSpeed)
		end

		ball.vel = Vec3.add(Vec3.add(bodyVel, normalPart), tangent)
		ball.spin = Vec3.scale(ball.spin, 0.7)
		body.hits = (body.hits or 0) + 1
	end

	return true
end

--[[ Bir gövdenin topa uzanıp uzanamayacağını ölçer (kaleci uzanma mesafesi,
	oyuncu kademesi). Dönüş: mesafe (m). ]]
function Body.reachDistance(ball, body)
	local closest = closestOnVerticalSegment(ball.pos, body.pos, body.height or 1.8)
	return Vec3.length(Vec3.sub(ball.pos, closest))
end

return Body
