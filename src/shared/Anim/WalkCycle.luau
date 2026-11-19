--[[
	WalkCycle — prosedürel koşu/yürüme döngüsü.

	Oyuncunun görsel iskeleti (rig) kodla sürüldüğü için yürüme animasyonu da
	kodla üretilir: kalça salınımı, diz kırılması, kol karşı salınımı ve gövde
	sekmesi. Adım uzunluğu gerçek mesafeye bağlıdır -> kayma (foot sliding) olmaz.

	faz = kat edilen mesafe / adım döngüsü uzunluğu  (0..1 arası döner)

	ÖNEMLİ: duruş ve yürüyüş ayrı iki poz DEĞİL; aynı pozun iki ucu. Eskiden
	amp < 0.05 eşiğinde bir daldiği gibi diğerine geçiliyordu: hız bir karede
	0.04 -> 0.06 olduğunda diz/kalça açıları bir karede sıçrıyor, oyuncu
	"ışınlanıyormuş" gibi görünüyordu. Artık iki poz sürekli olarak blend edilir.
]]

local Ease = require(script.Parent.Ease)
local Pose = require(script.Parent.Pose)
local Vec3 = require(script.Parent.Parent.Core.Vec3)

local WalkCycle = {}

WalkCycle.STRIDE = 1.9 -- bir tam döngüde kat edilen mesafe (m)
WalkCycle.FULL_SPEED = 7.6 -- tam salınım genliğine ulaşan hız (m/s)

-- Dururkenki atletik bekleyiş + nefes. Dizler kırık, gövde hafif öne, kollar
-- açık: karakter sahada HEYKEL gibi durmasın.
local function idlePose(time)
	local pose = Pose.new()
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

-- Tam genlikli adım döngüsü (amp=1). Hız ölçeklemesi sample() içinde yapılır.
local function stridePose(phase)
	local pose = Pose.new()
	local ph = (phase or 0) * math.pi * 2
	local s = math.sin(ph)
	local c = math.cos(ph)

	-- Bacaklar: +hip.x geriye savurur
	pose.hipL = Pose.joint(0.62 * s, 0, 0)
	pose.hipR = Pose.joint(-0.62 * s, 0, 0)

	-- Diz: bacak geriye giderken kırılır (yerden kaldırma)
	pose.kneeL = Pose.joint(0.12 + 0.85 * math.max(0, math.sin(ph + 1.2)), 0, 0)
	pose.kneeR = Pose.joint(0.12 + 0.85 * math.max(0, math.sin(ph + 1.2 + math.pi)), 0, 0)

	-- Ayak bileği: topuk-parmak yuvarlanması
	pose.ankleL = Pose.joint(-0.15 * c, 0, 0)
	pose.ankleR = Pose.joint(0.15 * c, 0, 0)

	-- Kollar karşılıklı salınır
	pose.shoulderL = Pose.joint(-0.55 * s, 0, 0.12)
	pose.shoulderR = Pose.joint(0.55 * s, 0, -0.12)
	pose.elbowL = Pose.joint(-0.45 - 0.25 * math.max(0, s), 0, 0)
	pose.elbowR = Pose.joint(-0.45 - 0.25 * math.max(0, -s), 0, 0)

	-- Gövde: hafif öne eğik + salınım
	pose.spine = Pose.joint(0.16, 0.08 * s, 0)
	pose.neck = Pose.joint(-0.05, 0, 0)

	-- Dikey sekme: her adımda iki kez
	pose.rootOffset = Vec3.new(0, -0.02 * (0.5 + 0.5 * math.cos(2 * ph)), 0)
	return pose
end

--[[ speed: m/s, phase: 0..1, time: saniye (dururken nefes için)
     Genlik sıfırken BİREBİR duruş, birken birebir koşu pozudur; aradaki
     değerlerde iki poz sürekli karıştırılır (ışınlanma/sıçrama yok). ]]
function WalkCycle.sample(speed, phase, time)
	local amp = Ease.clamp01((speed or 0) / WalkCycle.FULL_SPEED)
	local idle = idlePose(time)
	if amp <= 0 then
		return idle
	end
	local stride = stridePose(phase)
	if amp >= 1 then
		return stride
	end
	return Pose.blend(idle, stride, amp)
end

return WalkCycle
