--[[
	Ballistics — hedefe vuruş açısı çözümü.

	Bir oyuncu (veya AI) "şu noktaya şu hızla" pas/şut atmak istediğinde, yerçekimi
	altında gereken fırlatma açısını burada çözüyoruz. Formül, sabit yerçekimi
	varsayımıyla klasik eğik atış çözümüdür (hava direnci ihmal edilir; %5-8 hata
	yapar, gerçek oyuncunun nişan hatasıyla aynı mertebede).

	Denklem:  tanθ = (v² ± sqrt(v⁴ - g(g·R² + 2·h·v²))) / (g·R)
	  R = yatay mesafe, h = hedefin yükseklik farkı
	  "−" düz (sert) yörünge, "+" aşırtma (lob) yörüngesi

	Çözüm yoksa (hedef menzil dışı) nil döner — AI bunu "pas imkânsız" olarak yorumlar.
]]

local Vec3 = require(script.Parent.Vec3)

local Ballistics = {}

function Ballistics.solveLaunch(from, to, speed, gravity, highArc)
	local g = gravity or 9.81
	local dx = to.x - from.x
	local dz = to.z - from.z
	local h = to.y - from.y
	local horiz = math.sqrt(dx * dx + dz * dz)

	if speed <= 0 then
		return nil
	end
	if horiz < 1e-4 then
		-- Dikey atış
		return Vec3.new(0, speed, 0)
	end

	local v2 = speed * speed
	local disc = v2 * v2 - g * (g * horiz * horiz + 2 * h * v2)
	if disc < 0 then
		return nil
	end
	local root = math.sqrt(disc)
	local tanTheta
	if highArc then
		tanTheta = (v2 + root) / (g * horiz)
	else
		tanTheta = (v2 - root) / (g * horiz)
	end

	local theta = math.atan(tanTheta)
	local dir = Vec3.unit(Vec3.new(dx, 0, dz))
	local cosT = math.cos(theta)
	local sinT = math.sin(theta)

	return Vec3.new(dir.x * speed * cosT, speed * sinT, dir.z * speed * cosT)
end

-- Verilen hızla hedefe ulaşılabilir mi?
function Ballistics.isReachable(from, to, speed, gravity)
	return Ballistics.solveLaunch(from, to, speed, gravity) ~= nil
end

return Ballistics
