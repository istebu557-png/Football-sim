--[[
	Validate — doğrulanmamış girdiyi güvenle kullanılabilir değere indirger.

	NEDEN AYRI MODÜL
	  İstemci `Kick` remote'una HERHANGİ bir şey gönderebilir: nil, tablo, string,
	  NaN, 1e300. Sunucu bu değeri fiziğe ve animasyona verdiği için doğrulanmamış
	  girdi iki şekilde patlar:
	    1) Sessiz bozulma  — `math.min(1, NaN) == NaN`; NaN hız topun tüm durumunu
	       zehirler ve bir daha düzelmez (top görünmez olur, skor donar).
	    2) Handler çökmesi — `KickAnim`, `Config.SHOT[shotType]` ve `"hip" .. foot`
	       kullanır; shotType = "labels" (gerçek bir tablo!) -> `sp.power = nil` ->
	       aritmetik hatası; foot = {} -> concatenate hatası.
	  Bu yüzden politika: BEYAZ LİSTE + VARSAYILANA DÜŞ. Girdi geçersizse istek
	  reddedilmez, geçerli varsayılanla uygulanır (şut sessizce yutulmaz).

	  Mantık burada, SimLoop'un içinde değil: böylece birim olarak test edilebilir
	  ve hem sunucu hem istemci aynı kuralları paylaşır. Roblox API'si KULLANMAZ.
]]

local Validate = {}

-- Config.SHOT.types boş/eksik olsa bile her zaman bir geçerli vuruş türü kalsın
Validate.DEFAULT_SHOT_TYPE = "instep"

-- Fizikte anlamı olan en büyük büyüklük (m/s, m). Üstü ölçüm hatası/istismardır.
Validate.MAX_COMPONENT = 1e6

--- Sayı mı, sonlu mu? Değilse `fallback`.
-- tonumber("12") = 12 olduğu için sayısal string'ler de kabul edilir (istemci
-- JSON benzeri bir katmandan string gönderebilir); tonumber({}) = nil -> fallback.
function Validate.number(value, fallback)
	local n = tonumber(value)
	if n == nil then
		return fallback
	end
	if n ~= n or n == math.huge or n == -math.huge then
		return fallback
	end
	return n
end

--- Sayıya çevir, sonra [lo, hi] aralığına kıstır; geçersizse `fallback`.
-- Sıra önemli: önce sonluluk, sonra clamp. `math.min(1, NaN)` NaN döndürdüğü
-- için clamp tek başına koruma sağlamaz.
function Validate.clamp(value, lo, hi, fallback)
	local n = Validate.number(value, fallback)
	if n < lo then
		return lo
	end
	if n > hi then
		return hi
	end
	return n
end

--- Vec3 benzeri `{x, y, z}` gerçekten sonlu bir vektör mü?
-- Bu denetim topa YAZILACAK hız için son savunma hattıdır: balistik çözücü
-- (Ballistics.solveLaunch) hedefe ulaşılamadığında NaN üretebilir ve NaN hız
-- simülasyonun geri kalanını kalıcı olarak bozar.
function Validate.vec3(v)
	if type(v) ~= "table" then
		return false
	end
	-- BİLEREK ipairs değil, indis ile: `ipairs({v.x, v.y, v.z})` z nil olduğunda
	-- 2 elemanda durur ve eksik bileşenli tablo "geçerli" sayılırdı.
	local components = { v.x, v.y, v.z }
	for i = 1, 3 do
		local component = components[i]
		if type(component) ~= "number" or component ~= component or math.abs(component) > Validate.MAX_COMPONENT then
			return false
		end
	end
	return true
end

--- Config.SHOT'tan geçerli vuruş türü kümesi (set) üretir.
function Validate.shotTypeSet(shotConfig)
	local allowed = {}
	local types = shotConfig and shotConfig.types
	if type(types) == "table" then
		for _, typeName in ipairs(types) do
			if type(typeName) == "string" then
				allowed[typeName] = true
			end
		end
	end
	allowed[Validate.DEFAULT_SHOT_TYPE] = true
	return allowed
end

--- Vuruş türü beyaz listede mi? Değilse varsayılan tür.
-- `allowed` verilmezse Validate.shotTypeSet(nil) ile üretilen tek üyeli küme kullanılır.
function Validate.shotType(value, allowed)
	local set = allowed or Validate.shotTypeSet(nil)
	if type(value) == "string" and set[value] then
		return value
	end
	return Validate.DEFAULT_SHOT_TYPE
end

--- Ayak: yalnızca "L" veya "R". Diğer her şey nil -> animasyon otomatik seçer.
-- nil dönüşü bir hata değil, KickAnim'in topun yanına göre ayak seçtiği sözleşmedir.
function Validate.foot(value)
	if value == "L" or value == "R" then
		return value
	end
	return nil
end

return Validate
