--[[
	PlayerPose — SAHADA OYNAYAN OYUNCUNUN prosedürel hareket animasyonu.

	Neden var: şut pozunu (KickAnim) sunucu yalnızca vuruş beklerken uyguluyordu;
	geri kalan zamanda karakter ya Roblox'un varsayılan Animator'üne kalıyor ya da
	donmuş görünüyordu. Kullanıcı bunu "oyuncu animasyonları çalışmıyor" diye
	yaşıyordu. Bu modül her karede pozlanacak bir tablo verir.

	İki kaynak:
	  WalkCycle.sample(hız, faz, zaman) — koşu/duruş döngüsünün kendisi (fiziksel
	    adım uzunluğuna bağlı, kayma yok). Bu modül onu SARAR: zamanı hıza göre
	    faza çevirir, böylece çağıran tarafın adım uzunluğuyla uğraşması gerekmez.
	  ready — dururken atletik bekleyiş (WalkCycle'ın duruş dalı).

	Kullanım (istemci, kendi karakteri — en güvenilir yol, ağ sahipliği istemcide):
		HumanoidPose.apply(hrp.Parent, PlayerPose.walk(t, hiz))
	Kullanım (sunucu, kendi kontrolündeki karakterler):
		HumanoidPose.apply(model, PlayerPose.walk(t, hiz))

	Poz sözleşmesi KeeperAnim/KickAnim/WalkCycle ile aynıdır:
	{ eklemAdı = { x = , y = , z = }, rootOffset = Vec3 }  (Rig uzayı, +z ileri;
	 Roblox karakterine aynalamayı HumanoidPose yapar.)
]]

local WalkCycle = require(script.Parent.WalkCycle)

local PlayerPose = {}

-- Tam salınım genliğine ulaşan hız (m/s). WalkCycle içerde speed/7.6 ile
-- ölçekler; bu sabit yalnızca dışarıya "koşu ne zaman tam koşu olur" bilgisini
-- vermek ve testlerin eşiğini tek yerden okuması için tutulur.
PlayerPose.FULL_STRIDE_SPEED = 7.6

--[[ Hız -> salınım oranı (0..1). Dururken 0, FULL_STRIDE_SPEED'de 1.
     speed : m/s (işaretli olabilir; büyüklüğü kullanılır) ]]
function PlayerPose.strideAmp(speed)
	local s = math.abs(speed or 0)
	if s <= 0 then
		return 0
	end
	if s >= PlayerPose.FULL_STRIDE_SPEED then
		return 1
	end
	return s / PlayerPose.FULL_STRIDE_SPEED
end

--[[ Zamandan adım fazı üretir (0..1, döner). Faz MESAFEYE bağlıdır: hızlı
     koşan oyuncu adımlarını sıklaştırır, yavaş yürüyen seyreltir — böylece
     ayaklar yerde kaymaz.
     t     : saniye (kesintili olmasın diye sürekli bir saat verilmeli)
     speed : m/s ]]
function PlayerPose.phaseAt(t, speed)
	local s = math.max(0, speed or 0)
	if s <= 0 then
		return 0
	end
	local traveled = (t or 0) * s -- metre
	-- WalkCycle.STRIDE metre = bir tam döngü
	return (traveled / WalkCycle.STRIDE) % 1
end

--[[ Yürüyüş/koşu pozunu üret. Hız ~0 ise duruşa döner (WalkCycle'ın duruş dalı).
     t     : saniye
     speed : m/s
     Dönüş : poz tablosu ]]
function PlayerPose.walk(t, speed)
	local time = t or 0
	local s = math.max(0, speed or 0)
	return WalkCycle.sample(s, PlayerPose.phaseAt(time, s), time)
end

--[[ Duruş pozunu üret (atletik bekleyiş + nefes). Hız verilirse ve yürüyüş
     eşiğini geçiyorsa walk'a düşer: çağıran tarafın "duruyor mu" diye
     düşünmesi gerekmez.
     t     : saniye (nefes fazı)
     speed : m/s (isteğe bağlı) ]]
function PlayerPose.ready(t, speed)
	if PlayerPose.strideAmp(speed) > 0.05 then
		return PlayerPose.walk(t, speed)
	end
	return WalkCycle.sample(0, 0, t or 0)
end

return PlayerPose
