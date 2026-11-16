--[[
	Colliders — top ile direk/üst direk çarpışması.

	Direkler silindir, üst direk yatay silindirdir. Bunları "doğru parçası + yarıçap"
	(kapsül) olarak modelliyoruz; top da bir küre. Böylece genel bir çözücü yeterli:

	  1) Topun bu adımdaki hareket doğrusu (önceki konum -> yeni konum) ile direk
	     ekseni arasındaki EN YAKIN noktalar bulunur.
	  2) Mesafe (top yarıçapı + direk yarıçapı)'ndan küçükse çarpışma vardır.
	  3) Top yüzeyin dışına taşınır, normal bileşen -e ile yansıtılır, teğetsel
	     bileşene sürtünme uygulanır.

	Neden hareket doğrusu üzerinden? 30 m/s'lik bir şut 240 Hz'de adım başına
	12.5 cm ilerler; direk yarıçapı 6 cm olduğu için sadece konum kontrolü
	(discrete) bazı çarpışmaları kaçırırdı. Sürekli (continuous) test bunu önler.

	Bu modül Roblox API'si kullanmaz: aynı kod hem sunucuda hem testte çalışır.
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)

local Colliders = {}

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

--[[ İki doğru parçası arasındaki en yakın noktalar (Ericson, Real-Time Collision
	Detection, 5.1.9). Dönüş: c1 (p1-q1 üzerinde), c2 (p2-q2 üzerinde). ]]
local function closestPointsBetweenSegments(p1, q1, p2, q2)
	local d1 = Vec3.sub(q1, p1)
	local d2 = Vec3.sub(q2, p2)
	local r = Vec3.sub(p1, p2)

	local a = Vec3.dot(d1, d1)
	local e = Vec3.dot(d2, d2)
	local f = Vec3.dot(d2, r)

	local s, t

	if a <= 1e-12 and e <= 1e-12 then
		s, t = 0, 0
	elseif a <= 1e-12 then
		s = 0
		t = clamp(f / e, 0, 1)
	else
		local c = Vec3.dot(d1, r)
		if e <= 1e-12 then
			t = 0
			s = clamp(-c / a, 0, 1)
		else
			local b = Vec3.dot(d1, d2)
			local denom = a * e - b * b
			if denom > 1e-12 then
				s = clamp((b * f - c * e) / denom, 0, 1)
			else
				s = 0
			end
			t = (b * s + f) / e
			if t < 0 then
				t = 0
				s = clamp(-c / a, 0, 1)
			elseif t > 1 then
				t = 1
				s = clamp((b - c) / a, 0, 1)
			end
		end
	end

	local c1 = Vec3.add(p1, Vec3.scale(d1, s))
	local c2 = Vec3.add(p2, Vec3.scale(d2, t))
	return c1, c2
end

Colliders.closestPointsBetweenSegments = closestPointsBetweenSegments

--[[ Tek bir kapsül engeline karşı çarpışma çözümü. Dönüş: çarpıştı mı? ]]
local function resolveObstacle(ball, obs, fromPos)
	local cfg = ball.cfg
	local r = cfg.BALL.radius

	local c1, c2 = closestPointsBetweenSegments(fromPos, ball.pos, obs.a, obs.b)
	local delta = Vec3.sub(c1, c2)
	local dist = Vec3.length(delta)
	local minDist = r + (obs.radius or 0.06)

	if dist >= minDist then
		return false
	end

	-- Normal: direk ekseninden topa doğru
	local n
	if dist > 1e-9 then
		n = Vec3.scale(delta, 1 / dist)
	else
		n = Vec3.negate(Vec3.unit(ball.vel))
		if Vec3.lengthSq(n) < 1e-9 then
			n = Vec3.new(1, 0, 0)
		end
	end

	-- Topu yüzeyin dışına taşı (gömülmeyi önler)
	ball.pos = Vec3.add(c2, Vec3.scale(n, minDist + 1e-4))

	local vn = Vec3.dot(ball.vel, n)
	if vn >= 0 then
		-- Uzaklaşıyor: sadece konum düzeltmesi yeterli
		return true
	end

	local e = cfg.BALL.postRestitution or 0.62
	local vt = Vec3.sub(ball.vel, Vec3.scale(n, vn))
	local tangentSpeed = Vec3.length(vt)

	if tangentSpeed > 1e-6 then
		local mu = cfg.BALL.postFriction or 0.35
		local normalImpulse = (1 + e) * (-vn) -- birim kütle
		local reduce = min(tangentSpeed, mu * normalImpulse)
		vt = Vec3.scale(vt, 1 - reduce / tangentSpeed)
	end

	ball.vel = Vec3.add(Vec3.scale(n, -e * vn), vt)

	-- Spini gerçekçi biçimde sönümle (çarpma enerjinin bir kısmını yutar)
	ball.spin = Vec3.scale(ball.spin, 0.55)
	ball.postHits = (ball.postHits or 0) + 1
	return true
end

--[[ Topu tüm engellere karşı kontrol eder. fromPos: adım öncesi konum. ]]
function Colliders.resolve(ball, obstacles, fromPos)
	if not obstacles or #obstacles == 0 then
		return 0
	end
	local from = fromPos or ball.pos
	local hits = 0
	for i = 1, #obstacles do
		if resolveObstacle(ball, obstacles[i], from) then
			hits = hits + 1
		end
	end
	return hits
end

return Colliders
