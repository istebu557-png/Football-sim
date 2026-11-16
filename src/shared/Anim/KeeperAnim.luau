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

	-- Uzanma: ne kadar uzağa gidecekse o kadar uzanır (0.35-1.0 m)
	local reach = math.max(0.35, math.min(1.0, absDz / 1.15))
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

-- Uzanma eğrisi: hazırlıktan zirveye, sonra toparlanma
local function extensionAt(t)
	return Ease.track(t, {
		{ t = 0.00, v = 0 },
		{ t = 0.10, v = -0.12 },
		{ t = 0.35, v = 1 },
		{ t = 0.62, v = 1 },
		{ t = 0.95, v = 0 },
	})
end

function KeeperAnim:sample(t)
	local ext = extensionAt(t)
	local pose = Pose.new()
	local kind = self.kind
	local dir = self.dir
	local reach = self.reach

	-- Hazırlık: çömelme
	local crouch = Ease.track(t, {
		{ t = 0.00, v = 0 },
		{ t = 0.10, v = 0.10 },
		{ t = 0.35, v = 0.04 },
		{ t = 0.95, v = 0 },
	})

	if kind == "block" then
		-- Ayakta blok: dizler kırık, kollar öne, ağırlık merkezi alçak
		local guard = Ease.track(t, {
			{ t = 0.00, v = 0 },
			{ t = 0.16, v = 1 },
			{ t = 0.70, v = 1 },
			{ t = 0.95, v = 0 },
		})
		pose.rootOffset = Vec3.new(0, -0.16 * guard - 0.05 * crouch, 0)
		pose.spine = Pose.joint(0.18 * guard, -dir * 0.12 * guard, 0)
		pose.hipL = Pose.joint(-0.42 * guard, 0, -0.10 * guard)
		pose.hipR = Pose.joint(-0.42 * guard, 0, 0.10 * guard)
		pose.kneeL = Pose.joint(0.85 * guard, 0, 0)
		pose.kneeR = Pose.joint(0.85 * guard, 0, 0)
		pose.shoulderL = Pose.joint(-1.15 * guard, 0, -0.35 * guard)
		pose.shoulderR = Pose.joint(-1.15 * guard, 0, 0.35 * guard)
		pose.elbowL = Pose.joint(-0.45 * guard, 0, 0)
		pose.elbowR = Pose.joint(-0.45 * guard, 0, 0)
		pose.neck = Pose.joint(-0.10 * guard, 0, 0)
		return { pose = pose }
	end

	if kind == "jump" then
		-- Yüksek top: zıpla, kollar yukarı
		local air = Ease.track(t, {
			{ t = 0.00, v = 0 },
			{ t = 0.10, v = -0.12 },
			{ t = 0.35, v = 0.52 },
			{ t = 0.62, v = 0.40 },
			{ t = 0.95, v = 0 },
		})
		pose.rootOffset = Vec3.new(0, air, 0)
		pose.spine = Pose.joint(0.10, 0, 0)
		pose.hipL = Pose.joint(-0.55 * ext, 0, -0.08)
		pose.hipR = Pose.joint(-0.55 * ext, 0, 0.08)
		pose.kneeL = Pose.joint(1.00 * math.abs(ext), 0, 0)
		pose.kneeR = Pose.joint(1.00 * math.abs(ext), 0, 0)
		-- Kollar yukarı (negatif shoulder.x kolu yukarı kaldırır)
		pose.shoulderL = Pose.joint(-2.45 * ext, 0, -0.25)
		pose.shoulderR = Pose.joint(-2.45 * ext, 0, 0.25)
		pose.elbowL = Pose.joint(-0.25, 0, 0)
		pose.elbowR = Pose.joint(-0.25, 0, 0)
		pose.neck = Pose.joint(-0.25 * ext, 0, 0)
		return { pose = pose }
	end

	-- Yana dalış (dive / jumpDive)
	local isJump = kind == "jumpDive"
	local lateral = dir * reach * ext
	local vertical
	if isJump then
		vertical = math.max(0, Ease.track(t, {
			{ t = 0.00, v = 0 },
			{ t = 0.10, v = -0.10 },
			{ t = 0.35, v = 0.46 },
			{ t = 0.62, v = 0.30 },
			{ t = 0.95, v = 0 },
		}))
	else
		-- Alçak/düz dalışta gövde yere yaklaşır
		vertical = -0.30 * math.max(0, ext)
	end

	pose.rootOffset = Vec3.new(lateral, vertical - 0.08 * crouch, 0)

	-- Gövde yana devrilir (yerel Z ekseni = ileri; roll)
	pose.root = Pose.joint(0, 0, -dir * (isJump and 0.55 or 1.05) * math.max(0, ext))
	pose.spine = Pose.joint(0.12, -dir * 0.25 * ext, -dir * 0.20 * ext)
	pose.neck = Pose.joint(-0.18 * ext, dir * 0.35 * ext, 0)

	-- Kollar topa doğru yana uzanır. Kol -Y'den başlar; Z ekseni abduksiyon
	-- (yana açma) eksenidir. |z| = 1.9 -> kol yatayın biraz üstünde yana uzar.
	-- Top yükseldikçe kollar daha yukarı uzanır (yüksek topta parmak ucu)
	local aimUp = clamp01((self.height - 1.0) / 0.8)
	-- Yüksek top: kollar neredeyse dümdüz yukarı (parmak ucu), alçak top: yana yatay
	local armUp = (isJump and 2.15 or 1.93) + 0.85 * aimUp
	pose.shoulderL = Pose.joint(-0.40 * ext, 0, dir * (armUp + 0.10) * ext)
	pose.shoulderR = Pose.joint(-0.40 * ext, 0, dir * (armUp + 0.10) * ext)
	pose.elbowL = Pose.joint(-0.18 * ext, 0, 0)
	pose.elbowR = Pose.joint(-0.10 * ext, 0, 0)

	-- Bacaklar: dalış yönünün tersine uzanır (denge)
	pose.hipL = Pose.joint(-0.25 * ext, 0, -dir * 0.30 * ext)
	pose.hipR = Pose.joint(-0.45 * ext, 0, -dir * 0.15 * ext)
	pose.kneeL = Pose.joint(0.65 * ext, 0, 0)
	pose.kneeR = Pose.joint(0.35 * ext, 0, 0)

	return { pose = pose }
end

return KeeperAnim
