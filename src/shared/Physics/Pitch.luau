--[[
	Pitch — saha geometrisi ve çizgi/kale olayları.

	Saha 105 x 68 m, merkez orijinde:
	  x ∈ [-52.5, +52.5]  (uzunluk)
	  z ∈ [-34, +34]      (genişlik)
	  Ev sahibi takım +x yönüne hücum eder ("home" kalesi +x'te).

	"Top çizgiyi geçti" kuralı gerçek futbolla aynı: topun TAMAMI çizgiyi geçmeli,
	yani merkez çizginin r kadar ötesine ulaşmalı. Bu yüzden kale/taç tespiti
	top yarıçapını hesaba katar.
]]

local Config = require(script.Parent.Parent.Config)
local Vec3 = require(script.Parent.Parent.Core.Vec3)

local Pitch = {}
local P = Config.PITCH

Pitch.halfLength = P.halfLength
Pitch.halfWidth = P.halfWidth
Pitch.goalHalfWidth = P.goalHalfWidth
Pitch.goalHeight = P.goalHeight

-- Saha içinde mi? (çizgiler dahil)
function Pitch.isInside(pos)
	return math.abs(pos.x) <= P.halfLength and math.abs(pos.z) <= P.halfWidth
end

-- Top tamamen saha dışına çıktı mı? (oyun durur: taç/korner/kale vuruşu)
function Pitch.isOutOfPlay(pos, radius)
	local r = radius or 0
	return math.abs(pos.x) > P.halfLength + r or math.abs(pos.z) > P.halfWidth + r
end

--[[
	Kale çizgisi geçildi mi?
	fromPos -> toPos arasında x = ±(halfLength + r) düzlemini kesen noktayı bulur,
	o noktada top kale ağzının içinde ve üst direğin altında mı diye bakar.
	Dönüş: "home" (+x kalesine gol = ev sahibi attı), "away" (-x kalesi), ya da nil.
]]
function Pitch.goalCrossed(fromPos, toPos, radius)
	local r = radius or 0
	local plane = P.halfLength + r

	for _, side in ipairs({ 1, -1 }) do
		local target = side * plane
		local x0, x1 = fromPos.x, toPos.x
		if (x0 - target) * (x1 - target) <= 0 and x1 ~= x0 then
			local t = (target - x0) / (x1 - x0)
			if t >= 0 and t <= 1 then
				local z = fromPos.z + (toPos.z - fromPos.z) * t
				local y = fromPos.y + (toPos.y - fromPos.y) * t
				if math.abs(z) < P.goalHalfWidth - r and y < P.goalHeight and y > -r then
					return side == 1 and "home" or "away"
				end
			end
		end
	end
	return nil
end

-- Top kale ağının içinde mi? (gol sonrası topu tutmak için)
function Pitch.isInsideGoal(pos)
	return math.abs(pos.x) > P.halfLength and math.abs(pos.z) < P.goalHalfWidth and pos.y < P.goalHeight
end

-- Oyun dışı türü. "corner"/"goalKick" ayrımı son dokunan takıma bağlı olduğu için
-- maç mantığında (Adım 5) çözülür; burada sadece çizgi sınıflandırılır.
function Pitch.classifyOutOfPlay(pos, radius)
	local r = radius or 0
	if math.abs(pos.z) > P.halfWidth + r then
		return "touchLine"
	end
	if math.abs(pos.x) > P.halfLength + r then
		return "goalLine"
	end
	return nil
end

-- Saha üzerinde deterministik başlangıç pozisyonları (Adım 3: diziliş).
function Pitch.kickoffSpot(side)
	return Vec3.new(side * 1.0, Config.BALL.radius, 0)
end

-- Oyuncu pozisyonunun sahanın içine kırpılması (AI taşmasın).
function Pitch.clampPosition(pos, margin)
	local m = margin or 1.0
	return Vec3.new(
		math.max(-P.halfLength + m, math.min(P.halfLength - m, pos.x)),
		pos.y,
		math.max(-P.halfWidth + m, math.min(P.halfWidth - m, pos.z))
	)
end

-- Sahanın önemli noktaları (Adım 3+: diziliş, korner, penaltı).
Pitch.points = {
	center = Vec3.new(0, 0, 0),
	penaltySpotHome = Vec3.new(P.halfLength - P.penaltySpot, 0, 0),
	penaltySpotAway = Vec3.new(-(P.halfLength - P.penaltySpot), 0, 0),
	goalHome = Vec3.new(P.halfLength, 0, 0),
	goalAway = Vec3.new(-P.halfLength, 0, 0),
}

return Pitch
