--[[
	Ease — animasyon eğrileri.

	Gerçek hareketler sabit hızda olmaz: kaslar hızlanır, eklemler yumuşar.
	Buradaki eğriler, "takvim" tabanlı animasyonların temel taşı.
]]

local Ease = {}

function Ease.clamp01(v)
	if v < 0 then
		return 0
	elseif v > 1 then
		return 1
	end
	return v
end

-- t'yi [a,b] aralığından [0,1]'e normalize eder (dışarısı kırpılır)
function Ease.segment(t, a, b)
	if b <= a then
		return t >= b and 1 or 0
	end
	return Ease.clamp01((t - a) / (b - a))
end

-- Yumuşak başlangıç/bitiş (3t² - 2t³)
function Ease.smoothstep(x)
	local t = Ease.clamp01(x)
	return t * t * (3 - 2 * t)
end

-- Hızlı başlar, yavaş biter
function Ease.outCubic(x)
	local t = Ease.clamp01(x)
	return 1 - (1 - t) ^ 3
end

-- Yavaş başlar, hızlanır (vuruş öncesi savurma)
function Ease.inCubic(x)
	local t = Ease.clamp01(x)
	return t * t * t
end

-- 0 -> 1 -> 0 (darbe/uzanma eğrisi)
function Ease.pulse(x)
	local t = Ease.clamp01(x)
	return math.sin(t * math.pi)
end

function Ease.lerp(a, b, t)
	return a + (b - a) * t
end

--[[ Aşamalı geçiş: verilen zaman noktalarında (keys) değerleri tutar,
	aralarda yumuşak geçiş yapar. keys = { {t=0, v=0}, {t=0.2, v=1}, ... } ]]
function Ease.track(t, keys)
	if #keys == 0 then
		return 0
	end
	if t <= keys[1].t then
		return keys[1].v
	end
	for i = 2, #keys do
		local a, b = keys[i - 1], keys[i]
		if t <= b.t then
			local f = Ease.smoothstep(Ease.segment(t, a.t, b.t))
			return Ease.lerp(a.v, b.v, f)
		end
	end
	return keys[#keys].v
end

return Ease
