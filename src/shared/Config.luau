--[[
	Config — motorun tüm ayar parametreleri.

	Birim sistemi: SI (metre, saniye, kilogram, radyan).
	Roblox sahnesi için STUD_PER_METER ile çevrim yapılır (1 stud ≈ 0.28 m).
	Böylece fizik "gerçek dünya" sayılarıyla çalışır; Roblox'un 20 stud'luk
	"dev" ölçeğine sıkışmayız.

	Değerler gerçek FIFA ölçüleri ve spor bilimi literatüründen alınmıştır:
	  saha 105 x 68 m, kale 7.32 x 2.44 m, top çapı 22 cm (0.43 kg), hava 1.225 kg/m³
]]

local Config = {}

Config.STUDS_PER_METER = 1 / 0.28 -- 3.5714 stud/metre

-- Simülasyon frekansı. 240 Hz: 25 m/s'lik bir şutta top adım başına ~10 cm ilerler,
-- yani yarıçapından (11 cm) az — tünel geçişi (tunneling) fiziksel olarak imkânsız.
Config.SIM_HZ = 240
Config.FIXED_DT = 1 / Config.SIM_HZ
Config.MAX_FRAME_DT = 0.25 -- tek karede işlenecek maksimum gerçek zaman (spiral ölüm koruması)
Config.MAX_SUBSTEPS = 60

Config.GRAVITY = 9.81

Config.AIR = {
	density = 1.225, -- kg/m³ (deniz seviyesi, 15 °C)
}

local BALL_RADIUS = 0.11 -- FIFA: çevre 68-70 cm -> yarıçap ~0.11 m
Config.BALL = {
	radius = BALL_RADIUS,
	mass = 0.43, -- kg (FIFA: 410-450 g)
	crossSection = math.pi * BALL_RADIUS * BALL_RADIUS, -- m²

	-- Hava direnci: a = -0.5 * rho * A * Cd * |v| * v / m
	-- Cd=0.25 türbülanslı akış rejimi (hızlı şut). Yavaş topta Cd 0.4-0.5'e çıkar;
	-- bu geçiş "drag crisis" olarak adlandırılır ve Knuckleball etkisinin kaynağıdır.
	dragCoefficient = 0.25,
	dragCoefficientSlow = 0.47,
	dragCrisisSpeed = 12, -- m/s: bu hızın altında Cd yavaş değere doğru geçer
	dragCrisisWidth = 6, -- m/s: geçişin yumuşaklığı

	-- Magnus (spin) kuvveti: F = 0.5 * rho * A * Cl * v² * (ω̂ × v̂)
	-- Cl (kaldırma katsayısı) spin oranı S = ω*r/v ile artar, doyuma ulaşır.
	magnusScale = 0.8, -- Cl = min(magnusMax, magnusScale * S)
	magnusMax = 0.32,
	spinDecay = 0.06, -- 1/s: hava sürtünmesiyle spin sönümü (üssel)

	-- Zemin teması (çim, kuru)
	restitution = 0.74, -- dikey sekme katsayısı (zemin testi: 2 m'den ~1.10 m sekme)
	contactFriction = 0.45, -- Coulomb sürtünme katsayısı (teğetsel impuls sınırı)
	rollResistance = 0.06, -- yuvarlanma direnci; ivme = -mu * g ≈ 0.59 m/s²
	rollThreshold = 0.9, -- m/s: bundan yavaş dikey çarpmada sekmez, yuvarlanmaya geçer
	stopSpeed = 0.15, -- m/s: bu hızın altında top durur

	-- Sekme sonrası spinin dikey zıplamaya etkisi (backspin topu alçak tutar).
	spinBounceCoupling = 0.06,

	-- Direk/üst direk çarpışması (metal, çimden daha canlı sekmez)
	postRestitution = 0.62,
	postFriction = 0.35,
}

Config.PITCH = {
	length = 105,
	width = 68,
	halfLength = 52.5,
	halfWidth = 34,
	goalHalfWidth = 3.66, -- 7.32 m kale ağzı
	goalHeight = 2.44,
	goalDepth = 2.0,
	penaltyAreaLength = 16.5,
	penaltyAreaHalfWidth = 20.16,
	goalAreaLength = 5.5,
	goalAreaHalfWidth = 9.16,
	penaltySpot = 11,
	centerCircleRadius = 9.15,
	cornerArcRadius = 1,

	-- Direkler: top bunlara çarpıp döner (Colliders modülü)
	postRadius = 0.06, -- 12 cm direk
	crossbarRadius = 0.06,
}

Config.PLAYER = {
	radius = 0.35,
	maxSpeed = 7.6, -- m/s (27 km/h) — iyi bir amatörün sprint hızı
	sprintMultiplier = 1.0,
	acceleration = 6.5, -- m/s² (0-27 km/h ~1.2 s)
	deceleration = 9.0, -- m/s²
	turnRate = 7.0, -- rad/s (~400°/s) gövde dönüş hızı
	staminaDrainSprint = 0.045, -- 1/s (tam sprintte)
	staminaRegen = 0.07, -- 1/s (dururken)
	staminaMinFactor = 0.72, -- yorgunken hız çarpanı
}

--[[ Oyuncu-top ilişkisi (yakın kontrol / top sürme / şut) ]]
Config.BALL_CONTROL = {
	bodyRadius = 0.42, -- oyuncu gövde yarıçapı (m)
	bodyHeight = 1.80,
	controlRadius = 1.45, -- bu mesafede top "ayakta" sayılır
	kickReach = 1.70, -- şut atılabilen maksimum mesafe
	dribbleReach = 1.60,

	-- Dokunuş (touch) modeli: gerçekte top sürerken saniyede ~3 dokunuş olur
	touchInterval = 0.34,
	touchSpeedFactor = 1.0, -- (artık kullanılmıyor; dokunuş hızı çözülerek bulunuyor)
	touchForward = 0.18, -- dokunuşun ileri bileşeni (m/s) — küçük düzeltme
	maxTouchSpeed = 10.5,
	sprintTouchPenalty = 0.30, -- hızlı koşarken dokunuş aşırıya kaçar (top kaçar)

	-- İlk dokunuş / kapatma (trap)
	trapSpeedThreshold = 6.0,
	trapFactor = 0.30, -- gelen hızlı topun ne kadarı kalır
	trapRadius = 0.95,

	-- Şut
	minKickSpeed = 13,
	maxKickSpeed = 31,
	chargeTime = 0.9, -- tam güç için basılı tutma süresi
	kickHeight = 1.0, -- top bu yüksekliğin altındaysa vurulabilir
	aimErrorDeg = 2.2, -- nişan hatası (derece, standart sapma)
}

--[[ Kaleci AI ]]
Config.KEEPER = {
	height = 1.90,
	radius = 0.44,
	lineOffset = 0.55, -- kale çizgisinden öne mesafe (m)
	maxSpeed = 6.0, -- yan kayma hızı
	diveSpeed = 8.5,
	diveAccel = 22,
	reachZ = 3.15, -- direklerin içinde kalır
	restitution = 0.45,
	reactionTime = 0.12,
}

--[[ File (ağ) fiziği: top ağda yavaşlar, esnetir, geri sektirmez ]]
Config.NET = {
	damping = 7.0, -- ağ içinde üstel hız sönümü (1/s)
	restitution = 0.14, -- ağdan sekme katsayısı (çok ölü)
	sideRestitution = 0.10,
	topRestitution = 0.10,
	friction = 0.55,
	maxSag = 0.38, -- ağın en fazla esneme miktarı (m)
	sagStiffness = 11.0, -- geri toplama yayı
	sagDamping = 3.2,
	sagImpulse = 1.7, -- çarpma hızının esnemeye dönüşümü
}

Config.MATCH = {
	halves = 2,
	halfLengthSeconds = 45 * 60,
	stoppageBase = 60,
	kickoffCountdown = 3,
}

return Config
