--[[
	Rng — deterministik sözde rastgele sayı üreteci (Park–Miller / MINSTD).

	Neden math.random değil?
	  * Roblox'un math.random'ı sunucu/istemcide ayrı tohumlanır ve sürümler arası
	    garantisi yoktur. Ağ senkronu ve tekrar oynatma (replay) için aynı tohumdan
	    aynı diziyi üretmemiz şart.
	  * Sadece double aritmetiği kullanır: Lua 5.1, Lua 5.3 ve Luau'da bit-bit aynı
	    sonucu verir (bitwise operatör yok, taşma yok).
]]

local Rng = {}
Rng.__index = Rng

local MOD = 2147483647 -- 2^31 - 1
local MUL = 48271 -- 48271 * 2^31 < 2^53 olduğu için double'da tam duyarlı

function Rng.new(seed)
	local s = math.floor(math.abs(tonumber(seed) or 1)) % MOD
	if s == 0 then
		s = 1
	end
	return setmetatable({ state = s, seed = s }, Rng)
end

-- [0, 1) aralığında float.
function Rng:next()
	self.state = (self.state * MUL) % MOD
	return (self.state - 1) / (MOD - 1)
end

-- [0, 1] aralığında float.
function Rng:nextInclusive()
	self.state = (self.state * MUL) % MOD
	return self.state / MOD
end

-- [a, b) aralığında float.
function Rng:range(a, b)
	return a + (b - a) * self:next()
end

-- [-a, +a] aralığında float.
function Rng:symmetric(a)
	return (self:next() * 2 - 1) * a
end

-- [a, b] aralığında tam sayı.
function Rng:int(a, b)
	if b < a then
		a, b = b, a
	end
	return a + math.floor(self:next() * (b - a + 1))
end

-- Normal dağılım (Box–Muller). Şut/pas hatası için gerçekçi sapma üretir.
function Rng:normal(mean, stddev)
	local u1 = math.max(self:next(), 1e-12)
	local u2 = self:next()
	local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
	return (mean or 0) + z * (stddev or 1)
end

function Rng:chance(p)
	return self:next() < p
end

function Rng:pick(list)
	return list[self:int(1, #list)]
end

function Rng:clone()
	return setmetatable({ state = self.state, seed = self.seed }, Rng)
end

return Rng
