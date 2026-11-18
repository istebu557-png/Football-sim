--[[
	KeeperAnim — topa göre değişen adaptif kaleci hareketi.

	Kaleci "hangi topa nasıl atlayacağını" kendisi seçer; poz her kurtarışta
	topun tahmini varış noktasından yeniden üretilir:

	  |dz| < 0.5 m ve alçak  -> "block" : ayakta kalır, kollar öne, dizler kırık
	  yüksek top (>1.45 m)   -> "jump"  : zıplar, kollar yukarı, bacaklar toplanır
	  yana uzak top          -> "dive"  : gövde yana devrilir, kollar o tarafa uzanır
	  yan + yüksek           -> "jumpDive": zıplayarak yana uzanır

	Uzanma miktarı topun ne kadar uzağa gideceğine bağlı (0.35-1.0 m). Bu öteleme
	sunucuda KALECİNİN FİZİKSEL GÖVDESİNE de uygulanır; yani dalış yapan kaleci
	gerçekten daha uzağa uzanır (görsel ile fizik ayrışmaz).

	Zaman çizelgesi:
	  0.00-0.10  hazırlık (hafif çömelme, ters yöne ağırlık)
	  0.10-0.35  fırlama/uzanma
	  0.35-0.62  zirve (havada/zemin temas)
	  0.62-0.95  toparlanma

	sample(t) -> { pose = <poz>, contact = false }
	(KickAnim ile aynı sözleşme: her aksiyon animasyonu poz tablosu döndürür.)
]]

local Ease = require(script.Parent.Ease)
local Pose = require(script.Parent.Pose)
local Vec3 = require(script.Parent.Parent.Core.Vec3)

local KeeperAnim = {}
KeeperAnim.__index = KeeperAnim

KeeperAnim.DURATION = 0.95

local clamp01 = Ease.clamp01

--[[ opts:
	dz     : topun kaleciye göre yanal varış noktası (m, + = kaleci sağı)
	height : varış noktasındaki yükseklik (m)
	speed  : topun hızı (m/s) — sertlik/tepki ayarı
]]
function KeeperAnim.new(opts)
	opts = opts or {}
	local dz = opts.dz or 0
	local height = opts.height or 0.5
	local absDz = math.abs(dz)
	local dir = (dz >= 0) and 1 or -1
	local speed = opts.speed or 15

	local kind
	if height >= 1.45 and absDz < 0.55 then
		kind = "jump"
	elseif height >= 1.45 then
		kind = "jumpDive"
	elseif absDz < 0.5 then
		kind = "block"
	else
		kind = "dive"
	end

	-- Uzanma: ne kadar uzağa gidecekse o kadar uzanır (0.30-1.0 m)
	-- Yüksek topda daha az yana uzanır (el yerine göz/topu takip eder)
	local reach = math.max(0.30, math.min(1.0, absDz / 1.15))
	-- Hızlı topa daha sert/çabuk tepki
	local urgency = clamp01((speed - 10) / 20)

	return setmetatable({
		kind = kind,
		dz = dz,
		height = height,
		dir = dir,
		absDz = absDz,
		reach = reach,
		urgency = urgency,
	}, KeeperAnim)
end

function KeeperAnim:duration()
	return KeeperAnim.DURATION
end

--[[ Dalış yokken kaleci HEYKEL gibi durmasın: yavaş nefes + ağırlık salınımı.
     sample() gibi poz tablosu döndürür; sunucu her karede bunu uygular.
     t = saniye (sunucu saati). ]]
function KeeperAnim.idle(t)
	local pose = Pose.new()
	local breath = math.sin(t * 1.7) * 0.5 + 0.5 -- 0..1, ~3.7 s dönem
	local sway = math.sin(t * 0.9) -- yana ağırlık aktarımı
	pose.rootOffset = Vec3.new(sway * 0.06, -0.10 - 0.035 * breath, 0)
	pose.root = Pose.joint(0, 0, sway * 0.05)
	pose.spine = Pose.joint(0.16, sway * 0.06, 0)
	pose.neck = Pose.joint(-0.10, -sway * 0.08, 0)
	pose.shoulderL = Pose.joint(-1.10 - 0.06 * breath, 0, -0.35)
	pose.shoulderR = Pose.joint(-1.10 - 0.06 * breath, 0, 0.35)
	pose.elbowL = Pose.joint(-0.45, 0, 0)
	pose.elbowR = Pose.joint(-0.45, 0, 0)
	pose.hipL = Pose.joint(-0.35 - 0.06 * breath, 0, -0.10)
	pose.hipR = Pose.joint(-0.35 - 0.06 * breath, 0, 0.10)
	pose.kneeL = Pose.joint(0.70, 0, 0)
	pose.kneeR = Pose.joint(0.70, 0, 0)
	return pose
end

-- Uzanma eğrisi: daha yumuşak hazırlık, sert uzanma, yavaş toparlanma
local function extensionAt(t)
	return Ease.track(t, {
		{ t = 0.00, v = 0 },
		{ t = 0.08, v = -0.10 }, -- erken hafif çökme
		{ t = 0.16, v = 0.45 },  -- hızlı fırlama
		{ t = 0.38, v = 1 },     -- zirve
		{ t = 0.68, v = 0.75 },  -- hafif geri çekilme
		{ t = 0.95, v = 0 },
	})
end

function KeeperAnim:sample(t)
	local ext = extensionAt(t)
	local pose = Pose.new()
	local kind = self.kind
	local dir = self.dir
	local reach = self.reach

	-- Hazırlık: daha belirgin çömelme (enerji toplanışı)
	local crouch = Ease.track(t, {
		{ t = 0.00, v = 0 },
		{ t = 0.10, v = 0.14 },
		{ t = 0.25, v = 0.08 },
		{ t = 0.95, v = 0 },
	})

	if kind == "block" then
		-- Ayakta blok: dizler kırık, kollar öne, ağırlık merkezi alçak
		local guard = Ease.track(t, {
			{ t = 0.00, v = 0 },
			{ t = 0.14, v = 1 },
			{ t = 0.68, v = 1 },
			{ t = 0.95, v = 0 },
		})
		pose.rootOffset = Vec3.new(0, -0.18 * guard - 0.06 * crouch, 0)
		pose.spine = Pose.joint(0.20 * guard, -dir * 0.14 * guard, 0)
		pose.hipL = Pose.joint(-0.45 * guard, 0, -0.12 * guard)
		pose.hipR = Pose.joint(-0.45 * guard, 0, 0.12 * guard)
		pose.kneeL = Pose.joint(0.90 * guard, 0, 0)
		pose.kneeR = Pose.joint(0.90 * guard, 0, 0)
		pose.shoulderL = Pose.joint(-1.20 * guard, 0, -0.40 * guard)
		pose.shoulderR = Pose.joint(-1.20 * guard, 0, 0.40 * guard)
		pose.elbowL = Pose.joint(-0.50 * guard, 0, 0)
		pose.elbowR = Pose.joint(-0.50 * guard, 0, 0)
		pose.neck = Pose.joint(-0.12 * guard, 0, 0)
		return { pose = pose }
	end

	if kind == "jump" then
		-- Yüksek top: güçlü zıpla, kollar düz yukarı, bacaklar toplanır
		local air = Ease.track(t, {
			{ t = 0.00, v = 0 },
			{ t = 0.08, v = -0.10 },
			{ t = 0.30, v = 0.60 },
			{ t = 0.55, v = 0.45 },
			{ t = 0.95, v = 0 },
		})
		pose.rootOffset = Vec3.new(0, air, 0)
		pose.spine = Pose.joint(0.12, 0, 0)
		pose.hipL = Pose.joint(-0.60 * ext, 0, -0.10)
		pose.hipR = Pose.joint(-0.60 * ext, 0, 0.10)
		pose.kneeL = Pose.joint(1.10 * math.abs(ext), 0, 0)
		pose.kneeR = Pose.joint(1.10 * math.abs(ext), 0, 0)
		-- Kollar düz yukarı (negatif shoulder.x)
		pose.shoulderL = Pose.joint(-2.60 * ext, 0, -0.20)
		pose.shoulderR = Pose.joint(-2.60 * ext, 0, 0.20)
		pose.elbowL = Pose.joint(-0.20, 0, 0)
		pose.elbowR = Pose.joint(-0.20, 0, 0)
		pose.neck = Pose.joint(-0.30 * ext, 0, 0)
		return { pose = pose }
	end

	-- Yana dalış (dive / jumpDive)
	local isJump = kind == "jumpDive"
	local lateral = dir * reach * ext
	local vertical
	if isJump then
		-- Zıplamalı dalış: daha yüksek, daha geniş uzanma
		vertical = math.max(0, Ease.track(t, {
			{ t = 0.00, v = 0 },
			{ t = 0.08, v = -0.08 },
			{ t = 0.30, v = 0.52 },
			{ t = 0.55, v = 0.35 },
			{ t = 0.95, v = 0 },
		}))
	else
		-- Alçak/düz dalış: gövde daha çok yere doğru
		vertical = -0.35 * math.max(0, ext)
	end

	pose.rootOffset = Vec3.new(lateral, vertical - 0.10 * crouch, 0)

	-- Gövde daha çok devrilir (daha geniş dalış görünümü)
	pose.root = Pose.joint(0, 0, -dir * (isJump and 0.65 or 1.15) * math.max(0, ext))
	pose.spine = Pose.joint(0.14, -dir * 0.30 * ext, -dir * 0.25 * ext)
	pose.neck = Pose.joint(-0.20 * ext, dir * 0.40 * ext, 0)

	-- Kollar: top yüksekliğine göre daha hassas
	-- Alçak top: yana yatay. Yüksek top: neredeyse düz yukarı.
	local aimUp = clamp01((self.height - 0.9) / 1.0)
	local armUp = (isJump and 2.30 or 2.05) + 0.95 * aimUp
	pose.shoulderL = Pose.joint(-0.45 * ext, 0, dir * (armUp + 0.12) * ext)
	pose.shoulderR = Pose.joint(-0.45 * ext, 0, dir * (armUp + 0.12) * ext)
	pose.elbowL = Pose.joint(-0.20 * ext, 0, 0)
	pose.elbowR = Pose.joint(-0.12 * ext, 0, 0)

	-- Bacaklar: dalış yönünün tersine daha çok uzanır (denge)
	pose.hipL = Pose.joint(-0.30 * ext, 0, -dir * 0.35 * ext)
	pose.hipR = Pose.joint(-0.50 * ext, 0, -dir * 0.18 * ext)
	pose.kneeL = Pose.joint(0.70 * ext, 0, 0)
	pose.kneeR = Pose.joint(0.40 * ext, 0, 0)

	return { pose = pose }
end

return KeeperAnim
