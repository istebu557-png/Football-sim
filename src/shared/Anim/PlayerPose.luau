--[[
	PlayerPose — SAHADA OYNAYAN OYUNCUNUN prosedürel hareket animasyonu.

	Neden var: şut pozunu (KickAnim) sunucu yalnızca vuruş beklerken uyguluyordu;
	geri kalan zamanda karakter ya Roblox'un varsayılan Animator'üne kalıyor ya da
	donmuş görünüyordu. Kullanıcı bunu "oyuncu animasyonları çalışmıyor" diye
	yaşıyordu. Bu modül her karede pozlanacak bir tablo verir.

	İki kaynak:
	  WalkCycle.sample(hız, faz, zaman) — koşu/duruş döngüsünün kendisi (fiziksel
	    adım uzunluğuna bağlı, kayma yok). Bu modül onu SARAR.
	  ready — dururken atletik bekleyiş (WalkCycle'ın duruş ucu).

	ÖNEMLİ (ikinci şikâyet: "animasyon ışınlanarak oluyor"):
	  Eski `walk(t, speed)` fazı `(t * speed / STRIDE) % 1` ile hesaplıyordu.
	  `t` mutlak saat olduğu için hız DEĞİŞTİĞİNDE (özellikle durup tekrar
	  koşmaya başlayınca) faz bir karede rastgele bir yere atlıyordu. Canlı
	  oyuncular `step()` kullanır: faz her karede `speed * dt` ile biriktirilir,
	  hız sıçraması poz sıçramasına dönüşmez. Genlik de aynı şekilde yumuşatılır.

	Kullanım (istemci / sunucu, her oyuncu için BİR state):
		local state = PlayerPose.newState()
		local pose = PlayerPose.step(state, dt, zaman, hiz)
		HumanoidPose.apply(character, pose)

	`walk()` / `phaseAt()` yalnızca saf test yardımcıları olarak korunur; canlı
	kare döngüsünde KULLANILMAMALIDIR.

	Poz sözleşmesi KeeperAnim/KickAnim/WalkCycle ile aynıdır:
	{ eklemAdı = { x = , y = , z = }, rootOffset = Vec3 }  (Rig uzayı, +z ileri;
	 Roblox karakterine aynalamayı HumanoidPose yapar.)
]]

local WalkCycle = require(script.Parent.WalkCycle)

local PlayerPose = {}

-- Tam salınım genliğine ulaşan hız (m/s). WalkCycle içerde speed/FULL_SPEED
-- ile ölçekler; bu sabit dışarıya "koşu ne zaman tam koşu olur" bilgisini verir.
PlayerPose.FULL_STRIDE_SPEED = WalkCycle.FULL_SPEED

-- Duruş <-> koşu geçişinin zaman sabiti (s). ~0.15 s, birkaç karede yumuşak
-- geçiş demektir; daha küçük değer yine gözle görülür sıçrama yapar.
PlayerPose.BLEND_TAU = 0.15

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

--[[ SAF test yardımcısı: mutlak zamandan faz üretir (ESKİ DAVRANIŞ).
     Canlı kare döngüsünde kullanma — hız değişince faz sıçrar. ]]
function PlayerPose.phaseAt(t, speed)
	local s = math.max(0, speed or 0)
	if s <= 0 then
		return 0
	end
	local traveled = (t or 0) * s -- metre
	return (traveled / WalkCycle.STRIDE) % 1
end

--[[ SAF test yardımcısı: eski poz üretimi (faz + mutlak zaman).
     Canlı kare döngüsünde `step()` kullanılır. ]]
function PlayerPose.walk(t, speed)
	local time = t or 0
	local s = math.max(0, speed or 0)
	return WalkCycle.sample(s, PlayerPose.phaseAt(time, s), time)
end

--[[ Dururkenki atletik bekleyiş + nefes. Hız verilirse ve yürüyüş eşiğini
     geçiyorsa walk'a düşer (çağıran tarafın hızı kıyaslaması gerekmez). ]]
function PlayerPose.ready(t, speed)
	if PlayerPose.strideAmp(speed) > 0.05 then
		return PlayerPose.walk(t, speed)
	end
	return WalkCycle.sample(0, 0, t or 0)
end

---------------------------------------------------------------- canlı kullanım

-- Her oyuncu/karakter için bir tane. Weak-table değil: çağıran taraf oyuncu
-- başına tutar (istemcide tek state, sunucuda player -> state eşlemesi).
function PlayerPose.newState()
	return { phase = 0, amp = 0 }
end

--[[ IŞINLANMA ÖNLEYEN kare adımı.
     state : newState() ile üretilen tablo (oyuncu başına)
     dt    : bu karenin saniye cinsinden süresi
     time  : sürekli saat (duruş nefesi için)
     speed : anlık yatay hız (m/s)

     Faz ve genlik biriktirilir: hız bir karede 0 -> 7 olsa bile eklemler
     mevcut pozundan KÜÇÜK bir adımla ilerler. ]]
function PlayerPose.step(state, dt, time, speed)
	state = state or PlayerPose.newState()
	-- Sekme arka planda kalınca dt devasa olabilir: 0.1 s ile sınırla, aksi
	-- halde faz bir karede yarım döngü atlar ve yine "ışınlanma" görünür.
	local step = math.min(math.max(tonumber(dt) or 0, 0), 0.1)
	local s = math.max(tonumber(speed) or 0, 0)

	state.phase = (state.phase + s * step / WalkCycle.STRIDE) % 1
	local target = PlayerPose.strideAmp(s)
	local alpha = 1 - math.exp(-step / PlayerPose.BLEND_TAU)
	state.amp = state.amp + (target - state.amp) * alpha

	-- WalkCycle hızı amp olarak bekliyor: amp * FULL_SPEED = amp (0..1) demek.
	return WalkCycle.sample(state.amp * PlayerPose.FULL_STRIDE_SPEED, state.phase, time)
end

return PlayerPose
