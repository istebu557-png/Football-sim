--[[
	Vec3 — saf Lua vektör matematiği.

	Neden Roblox'un Vector3'ü değil?
	  * Çekirdek simülasyonun motor API'sine bağımlı olmaması gerekiyor: aynı kod
	    hem Roblox içinde hem de masaüstünde (test/CI) çalışmalı.
	  * Determinizm: float32 Vector3 yuvarlama hataları birikim yapar; burada
	    standart Lua double (float64) kullanıyoruz.
	  * Roblox katmanı (görsel) bu vektörleri Vector3'e çevirir, o kadar.

	Koordinat sistemi (saha merkezli, sağ el):
	  +x : orta saha çizgisinden bir kaleye doğru (uzunluk ekseni)
	  +z : yan çizgiye doğru (genişlik ekseni)
	  +y : yukarı (yerçekimine zıt)

	Kural: tüm fonksiyonlar YENİ tablo döndürür, argümanları asla değiştirmez.
]]

local Vec3 = {}
local sqrt = math.sqrt
-- Lua 5.3: math.atan(y, x) | Luau: math.atan2(y, x). Ikisi de desteklensin.
local atan2 = math.atan2 or math.atan

local function make(x, y, z)
	return { x = x, y = y, z = z }
end

Vec3.new = function(x, y, z)
	return make(x or 0, y or 0, z or 0)
end

-- Paylaşılan sabitler: değiştirilmemeli (tüm fonksiyonlar yeni tablo döndürür).
Vec3.ZERO = make(0, 0, 0)
Vec3.UP = make(0, 1, 0)

function Vec3.add(a, b)
	return make(a.x + b.x, a.y + b.y, a.z + b.z)
end

function Vec3.sub(a, b)
	return make(a.x - b.x, a.y - b.y, a.z - b.z)
end

function Vec3.scale(v, k)
	return make(v.x * k, v.y * k, v.z * k)
end

function Vec3.negate(v)
	return make(-v.x, -v.y, -v.z)
end

function Vec3.addScaled(a, b, k)
	return make(a.x + b.x * k, a.y + b.y * k, a.z + b.z * k)
end

function Vec3.dot(a, b)
	return a.x * b.x + a.y * b.y + a.z * b.z
end

function Vec3.cross(a, b)
	return make(
		a.y * b.z - a.z * b.y,
		a.z * b.x - a.x * b.z,
		a.x * b.y - a.y * b.x
	)
end

function Vec3.lengthSq(v)
	return v.x * v.x + v.y * v.y + v.z * v.z
end

function Vec3.length(v)
	return sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

-- Yatay (y=0) düzlemdeki hız bileşeni.
function Vec3.horizontal(v)
	return make(v.x, 0, v.z)
end

function Vec3.lengthHorizontal(v)
	return sqrt(v.x * v.x + v.z * v.z)
end

function Vec3.withY(v, y)
	return make(v.x, y, v.z)
end

function Vec3.unit(v)
	local len = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
	if len < 1e-12 then
		return make(0, 0, 0)
	end
	local inv = 1 / len
	return make(v.x * inv, v.y * inv, v.z * inv)
end

function Vec3.lerp(a, b, t)
	return make(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
end

-- a vektörünün b vektörü üzerindeki izdüşümü.
function Vec3.project(a, b)
	local d = Vec3.dot(b, b)
	if d < 1e-12 then
		return make(0, 0, 0)
	end
	return Vec3.scale(b, Vec3.dot(a, b) / d)
end

-- İki vektör arasındaki açı (radyan).
function Vec3.angleBetween(a, b)
	local denom = Vec3.length(a) * Vec3.length(b)
	if denom < 1e-12 then
		return 0
	end
	local c = Vec3.dot(a, b) / denom
	if c > 1 then c = 1 elseif c < -1 then c = -1 end
	return math.acos(c)
end

-- Yatay düzlemde yön açısı: +x ekseninden +z'ye doğru (atan2(z, x)).
function Vec3.yaw(v)
	return atan2(v.z, v.x)
end

function Vec3.fromYaw(angle)
	return make(math.cos(angle), 0, math.sin(angle))
end

function Vec3.distance(a, b)
	return Vec3.length(Vec3.sub(a, b))
end

function Vec3.distanceHorizontal(a, b)
	return Vec3.lengthHorizontal(Vec3.sub(a, b))
end

function Vec3.isFinite(v)
	return v.x == v.x and v.y == v.y and v.z == v.z
		and math.abs(v.x) < 1e30 and math.abs(v.y) < 1e30 and math.abs(v.z) < 1e30
end

function Vec3.tostring(v)
	return string.format("(%.3f, %.3f, %.3f)", v.x, v.y, v.z)
end

return Vec3
