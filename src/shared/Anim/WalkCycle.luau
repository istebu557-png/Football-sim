--[[
	WalkCycle — prosedürel koşu/yürüme döngüsü.

	Oyuncunun görsel iskeleti (rig) kodla sürüldüğü için yürüme animasyonu da
	kodla üretilir: kalça salınımı, diz kırılması, kol karşı salınımı ve gövde
	sekmesi. Adım uzunluğu gerçek mesafeye bağlıdır -> kayma (foot sliding) olmaz.

	faz = kat edilen mesafe / adım döngüsü uzunluğu  (0..1 arası döner)
]]

local Ease = require(script.Parent.Ease)
local Pose = require(script.Parent.Pose)
local Vec3 = require(script.Parent.Parent.Core.Vec3)

local WalkCycle = {}

WalkCycle.STRIDE = 1.9 -- bir tam döngüde kat edilen mesafe (m)

--[[ speed: m/s, phase: 0..1, time: saniye (dururken nefes için) ]]
function WalkCycle.sample(speed, phase, time)
	local pose = Pose.new()
	local amp = Ease.clamp01(speed / 7.6)
	local ph = (phase or 0) * math.pi * 2
	local s = math.sin(ph)
	local c = math.cos(ph)

	if amp < 0.05 then
		-- Duruyor: atletik bekleyiş + nefes. Eskiden bu dal neredeyse kimlikle
		-- aynıydı (knee 0.06, rootOffset -0.005) -> karakter sahada HEYKEL
		-- gibi duruyordu. Dizler kırık, gövde hafif öne, kollar açık: kaleci
		-- karşısındaki oyuncunun bekleyişi.
		local breath = math.sin((time or 0) * 1.8) * 0.5 + 0.5
		pose.spine = Pose.joint(0.10 + 0.03 * breath, 0, 0)
		pose.neck = Pose.joint(-0.07, 0, 0)
		pose.shoulderL = Pose.joint(0.04, 0, 0.26 + 0.03 * breath)
		pose.shoulderR = Pose.joint(0.04, 0, -0.26 - 0.03 * breath)
		pose.elbowL = Pose.joint(-0.40, 0, 0)
		pose.elbowR = Pose.joint(-0.40, 0, 0)
		pose.kneeL = Pose.joint(0.24 + 0.04 * breath, 0, 0)
		pose.kneeR = Pose.joint(0.24 + 0.04 * breath, 0, 0)
		pose.ankleL = Pose.joint(-0.14, 0, 0)
		pose.ankleR = Pose.joint(-0.14, 0, 0)
		pose.rootOffset = Vec3.new(0, -0.035 - 0.025 * breath, 0)
		return pose
	end

	-- Bacaklar: +hip.x geriye savurur
	pose.hipL = Pose.joint(0.62 * amp * s, 0, 0)
	pose.hipR = Pose.joint(-0.62 * amp * s, 0, 0)

	-- Diz: bacak geriye giderken kırılır (yerden kaldırma)
	local kneeL = 0.12 + 0.85 * amp * math.max(0, math.sin(ph + 1.2))
	local kneeR = 0.12 + 0.85 * amp * math.max(0, math.sin(ph + 1.2 + math.pi))
	pose.kneeL = Pose.joint(kneeL, 0, 0)
	pose.kneeR = Pose.joint(kneeR, 0, 0)

	-- Ayak bileği: topuk-parmak yuvarlanması
	pose.ankleL = Pose.joint(-0.15 * amp * c, 0, 0)
	pose.ankleR = Pose.joint(0.15 * amp * c, 0, 0)

	-- Kollar karşılıklı salınır
	pose.shoulderL = Pose.joint(-0.55 * amp * s, 0, 0.12)
	pose.shoulderR = Pose.joint(0.55 * amp * s, 0, -0.12)
	pose.elbowL = Pose.joint(-0.45 - 0.25 * amp * math.max(0, s), 0, 0)
	pose.elbowR = Pose.joint(-0.45 - 0.25 * amp * math.max(0, -s), 0, 0)

	-- Gövde: hafif öne eğik + salınım
	pose.spine = Pose.joint(0.06 + 0.10 * amp, 0.08 * amp * s, 0)
	pose.neck = Pose.joint(-0.05 * amp, 0, 0)

	-- Dikey sekme: her adımda iki kez
	pose.rootOffset = Vec3.new(0, -0.02 * amp * (0.5 + 0.5 * math.cos(2 * ph)), 0)

	return pose
end

return WalkCycle
