--[[
	KickAnim — TOPA GÖRE DEĞİŞEN adaptif şut hareketi.

	Yayınlanmış animasyon yok: poz, topun oyuncuya göre konumundan ve şut gücünden
	her seferinde yeniden hesaplanıyor.

	Top nerede?
	  * yerde (0-0.4 m)     -> "sürükleyici" düz vuruş; ayak kalça hizasından geçer
	  * bel/bacak (0.4-1.2) -> yarım vole; savurma düzlemi yükselir, gövde geriye yatar
	  * göğüs/üstü (>1.2)   -> vole; ayak göğüs hizasına kadar çıkar, gövde iyice yatar
	  * yanda (lateral)     -> o tarafın ayağı, kalça abduksiyonu ile uzanır
	  * güç (charge)        -> savurma genliği ve takip (follow-through) yüksekliği

	Zaman çizelgesi (saniye):
		0.00-0.13  hazırlık: arka ayak geriye, diz kırılır, gövde ters döner
		0.13-0.24  savurma: kalça öne fırlar, diz kontakt anında düzleşir
		0.24       TEMAS (top bu anda ayrılır)
		0.24-0.40  takip: bacak yukarıda kalır, gövde döner
		0.40-0.62  toparlanma: başlangıç pozisyonuna dönüş

	Ölçü birimi radyan; işaretler Rig'in yerel çerçevesine göre:
		+hip.x  bacağı GERİYE savurur (pozitif dönüş -Y'yi -Z'ye götürür)
]]

local Ease = require(script.Parent.Ease)
local Pose = require(script.Parent.Pose)
local Vec3 = require(script.Parent.Parent.Core.Vec3)

local KickAnim = {}
KickAnim.__index = KickAnim

KickAnim.DURATION = 0.62
KickAnim.CONTACT_TIME = 0.24

local clamp01 = Ease.clamp01

--[[ opts:
	ballHeight  : topun yerden yüksekliği (m)
	ballLateral : topun oyuncunun sağına (+) / soluna (-) uzaklığı (m)
	ballForward : topun önde (+) / arkada (-) olması (m)
	charge      : 0..1 şut gücü
	foot        : "L" | "R" (verilmezse topun yanına göre seçilir)
]]
function KickAnim.new(opts)
	opts = opts or {}

	local charge = clamp01(opts.charge or 0.7)
	local height = math.max(0, opts.ballHeight or 0.11)
	local lateral = opts.ballLateral or 0
	local forward = opts.ballForward or 0.8

	local foot = opts.foot
	if not foot then
		foot = (lateral >= 0) and "R" or "L"
	end

	-- Yüksek top -> vole: savurma düzlemi yükselir
	local tall = clamp01((height - 0.45) / 1.1)
	-- Genlik güçle artar
	local amp = 0.82 + 0.42 * charge
	-- Yana uzanma (kalça abduksiyonu)
	local reach = math.max(-1, math.min(1, lateral / 0.55))
	-- Top çok gerideyse daha kısa, daha kontrollü vuruş
	local behind = math.max(-1, math.min(0, forward / 0.6))

	return setmetatable({
		charge = charge,
		height = height,
		lateral = lateral,
		forward = forward,
		foot = foot,
		otherFoot = foot == "R" and "L" or "R",
		tall = tall,
		amp = amp,
		reach = reach,
		behind = behind,
	}, KickAnim)
end

function KickAnim:duration()
	return KickAnim.DURATION
end

function KickAnim:contactTime()
	return KickAnim.CONTACT_TIME
end

--[[ Verilen an için poz ü retir. Dönüş: { pose = <poz>, contact = bool } ]]
function KickAnim:sample(t)
	local amp = self.amp
	local tall = self.tall
	local reach = self.reach
	local contact = t >= KickAnim.CONTACT_TIME

	-- Yüksek topta bacak daha yukarı çıkar (negatif hip = öne)
	-- Yüksek top: kalça daha çok bükülür, savurma düzlemi yükselir
	local swingHigh = 0.55 + 1.35 * tall
	local backAngle = 0.90 * amp
	local contactAngle = -(swingHigh * amp)
	local followAngle = -((swingHigh + 0.50) * amp)

	-- Hip: daha yumuşak hazırlık, sert savurma, geniş takip
	local hipX = Ease.track(t, {
		{ t = 0.00, v = 0 },
		{ t = 0.10, v = backAngle * 0.6 }, -- erken hafif geri
		{ t = 0.16, v = backAngle },       -- tam geri (maksimum gevşeme)
		{ t = 0.24, v = contactAngle },    -- temas: kalça önde, bacak uzanır
		{ t = 0.38, v = followAngle },     -- takip: bacak yukarıda
		{ t = 0.62, v = 0 },
	})

	local kneeX = Ease.track(t, {
		{ t = 0.00, v = 0.08 },
		{ t = 0.13, v = 1.30 * amp },      -- güçlü diz kırılma
		{ t = 0.24, v = 0.10 + 0.12 * tall }, -- temas anında düz
		{ t = 0.40, v = 0.65 },            -- takip: diz yüksek
		{ t = 0.62, v = 0.08 },
	})

	-- Temas anında ayak bileği: yüksek topta daha düz, alçakta iç üstü
	local ankleContact = 0.35 + 0.15 * tall
	local ankleX = Ease.track(t, {
		{ t = 0.00, v = 0.10 },
		{ t = 0.13, v = -0.30 },
		{ t = 0.24, v = ankleContact },
		{ t = 0.40, v = 0.10 },
		{ t = 0.62, v = 0.10 },
	})

	-- Destek bacağı: yüksek topta daha çok kırılır, ağırlık merkezi alçak
	local supportHip = -(0.12 + 0.28 * tall)
	local supportKnee = 0.20 + 0.42 * tall + 0.18 * math.abs(reach)

	-- Gövde: savurmada ters, temasta öne, yüksek topta güçlü geriye
	local spineY = Ease.track(t, {
		{ t = 0.00, v = 0 },
		{ t = 0.13, v = 0.38 * amp },
		{ t = 0.24, v = -0.34 * amp },
		{ t = 0.40, v = -0.48 * amp },
		{ t = 0.62, v = 0 },
	})
	local spineX = 0.12 + 0.50 * tall -- yüksek top: daha çok geriye
	local spineZ = -0.25 * reach

	-- Kollar: karşı kol daha çok açılır (denge), vuran kol daha sığ
	local shoulderSwing = Ease.track(t, {
		{ t = 0.00, v = 0 },
		{ t = 0.13, v = -0.50 },
		{ t = 0.24, v = 0.60 },
		{ t = 0.40, v = 0.75 },
		{ t = 0.62, v = 0 },
	})

	-- Gövde salınımı: temas anında hafif Titreşim (realistik)
	local bob = Ease.track(t, {
		{ t = 0.00, v = 0 },
		{ t = 0.13, v = -0.050 },
		{ t = 0.28, v = -0.020 },
		{ t = 0.62, v = 0 },
	})

	local pose = Pose.new()
	pose.rootOffset = Vec3.new(0, bob, 0)

	-- Gövde ve baş
	pose.spine = Pose.joint(spineX, spineY, spineZ)
	pose.neck = Pose.joint(0.12 + 0.12 * (1 - tall), -spineY * 0.5, 0)
	pose.head = Pose.joint(0.06, 0, 0)

	-- Vuran bacak: daha geniş kalça açısı, topa göre hizalı
	local kickHip = pose["hip" .. self.foot]
	kickHip = Pose.joint(hipX, 0.14 * self.reach, (self.foot == "R" and -1 or 1) * 0.25 * math.abs(reach))
	pose["hip" .. self.foot] = kickHip
	pose["knee" .. self.foot] = Pose.joint(kneeX, 0, 0)
	pose["ankle" .. self.foot] = Pose.joint(ankleX, 0, 0)

	-- Destek bacağı: ağırlık merkezi dengeleme
	pose["hip" .. self.otherFoot] = Pose.joint(supportHip, 0, 0)
	pose["knee" .. self.otherFoot] = Pose.joint(supportKnee, 0, 0)
	pose["ankle" .. self.otherFoot] = Pose.joint(-0.14 - 0.25 * tall, 0, 0)

	-- Kollar: karşı kol güçlü denge, vuran kol sığ takip
	local otherArm = (self.foot == "R") and "L" or "R"
	local kickArm = (self.foot == "R") and "R" or "L"
	pose["shoulder" .. otherArm] = Pose.joint(-0.28 + shoulderSwing, 0.18, 0.60 + 0.30 * tall)
	pose["elbow" .. otherArm] = Pose.joint(-0.40 - 0.25 * math.abs(shoulderSwing), 0, 0)
	pose["shoulder" .. kickArm] = Pose.joint(0.35 - shoulderSwing * 0.75, 0, -0.32)
	pose["elbow" .. kickArm] = Pose.joint(-0.50, 0, 0)

	return { pose = pose, contact = contact }
end

return KickAnim
