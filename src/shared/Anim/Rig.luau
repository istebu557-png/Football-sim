--[[
	Rig — prosedürel iskelet ve ileri kinematik (FK).

	Neden? Roblox'ta animasyon normalde yayınlanmış bir Animation asset'i (ID) ile
	oynatılır. Biz asset YAYINLAMIYORUZ: iskelet tamamen kodla, sunucuda çözülüyor.
	Böylece poz, topun konumuna/hızına göre milimetre düzeyinde değiştirilebiliyor.

	Yerel koordinat sistemi (sağ el):
		+x : sağ
		+y : yukarı
		+z : ileri (oyuncunun baktığı yön)
		Tüm ölçüler metre. Köken (0,0,0) = ayakların yere bastığı nokta.

	FK: her eklem, ebeveynine göre bir ofset ve bir Euler dönüşü taşır.
		worldRot[j] = worldRot[parent] * localRot[j]
		pos[j]      = pos[parent] + worldRot[parent] * offset[j]

	Dönüş matrisi 3 eksen vektörüyle temsil edilir (kolonlar = yerel eksenlerin
	görüntüsü). Böylece Lua'da determinant/tuhaflık derdi olmadan çarpım yapılır.

	Rig.solve(pose) -> { pos = {eklem -> Vec3}, bones = { {a, b, radius, name} } }

	Bu modül Roblox API'si kullanmaz: animasyonlar testte ölçülebilir.
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)

local Rig = {}

local cos, sin = math.cos, math.sin

-- ---------------------------------------------------------------- matrisler
local IDENTITY = {
	x = Vec3.new(1, 0, 0),
	y = Vec3.new(0, 1, 0),
	z = Vec3.new(0, 0, 1),
}

local function matVec(m, v)
	return Vec3.new(
		m.x.x * v.x + m.y.x * v.y + m.z.x * v.z,
		m.x.y * v.x + m.y.y * v.y + m.z.y * v.z,
		m.x.z * v.x + m.y.z * v.y + m.z.z * v.z
	)
end

local function matMul(a, b)
	return {
		x = matVec(a, b.x),
		y = matVec(a, b.y),
		z = matVec(a, b.z),
	}
end

local function rotX(a)
	local c, s = cos(a), sin(a)
	return { x = Vec3.new(1, 0, 0), y = Vec3.new(0, c, s), z = Vec3.new(0, -s, c) }
end

local function rotY(a)
	local c, s = cos(a), sin(a)
	return { x = Vec3.new(c, 0, -s), y = Vec3.new(0, 1, 0), z = Vec3.new(s, 0, c) }
end

local function rotZ(a)
	local c, s = cos(a), sin(a)
	return { x = Vec3.new(c, s, 0), y = Vec3.new(-s, c, 0), z = Vec3.new(0, 0, 1) }
end

-- Euler: önce Z (roll), sonra Y (yaw), en son X (pitch) uygulanır.
function Rig.matFromEuler(angles)
	if not angles
		or ((angles.x or 0) == 0 and (angles.y or 0) == 0 and (angles.z or 0) == 0)
	then
		return IDENTITY
	end
	local m = IDENTITY
	if angles.z and angles.z ~= 0 then
		m = matMul(m, rotZ(angles.z))
	end
	if angles.y and angles.y ~= 0 then
		m = matMul(m, rotY(angles.y))
	end
	if angles.x and angles.x ~= 0 then
		m = matMul(m, rotX(angles.x))
	end
	return m
end

Rig.matVec = matVec
Rig.matMul = matMul

-- --------------------------------------------------------------- iskelet
-- parent = ebeveyn eklem, offset = ebeveyne göre konum (metre)
Rig.joints = {
	{ name = "root", parent = nil, offset = Vec3.new(0, 1.00, 0) },
	{ name = "spine", parent = "root", offset = Vec3.new(0, 0.14, 0) },
	{ name = "neck", parent = "spine", offset = Vec3.new(0, 0.30, 0) },
	{ name = "head", parent = "neck", offset = Vec3.new(0, 0.12, 0) },

	{ name = "shoulderL", parent = "spine", offset = Vec3.new(-0.20, 0.24, 0) },
	{ name = "elbowL", parent = "shoulderL", offset = Vec3.new(0, -0.28, 0) },
	{ name = "handL", parent = "elbowL", offset = Vec3.new(0, -0.26, 0) },

	{ name = "shoulderR", parent = "spine", offset = Vec3.new(0.20, 0.24, 0) },
	{ name = "elbowR", parent = "shoulderR", offset = Vec3.new(0, -0.28, 0) },
	{ name = "handR", parent = "elbowR", offset = Vec3.new(0, -0.26, 0) },

	{ name = "hipL", parent = "root", offset = Vec3.new(-0.11, -0.05, 0) },
	{ name = "kneeL", parent = "hipL", offset = Vec3.new(0, -0.45, 0) },
	{ name = "ankleL", parent = "kneeL", offset = Vec3.new(0, -0.44, 0) },
	{ name = "toeL", parent = "ankleL", offset = Vec3.new(0, -0.06, 0.13) },

	{ name = "hipR", parent = "root", offset = Vec3.new(0.11, -0.05, 0) },
	{ name = "kneeR", parent = "hipR", offset = Vec3.new(0, -0.45, 0) },
	{ name = "ankleR", parent = "kneeR", offset = Vec3.new(0, -0.44, 0) },
	{ name = "toeR", parent = "ankleR", offset = Vec3.new(0, -0.06, 0.13) },
}

-- Görsel parçalar: iki eklem arasındaki segmentler
Rig.bones = {
	{ name = "pelvis", a = "root", b = "spine", radius = 0.13 },
	{ name = "torso", a = "spine", b = "neck", radius = 0.15 },
	{ name = "head", a = "neck", b = "head", radius = 0.11 },

	{ name = "upperArmL", a = "shoulderL", b = "elbowL", radius = 0.055 },
	{ name = "forearmL", a = "elbowL", b = "handL", radius = 0.048 },
	{ name = "upperArmR", a = "shoulderR", b = "elbowR", radius = 0.055 },
	{ name = "forearmR", a = "elbowR", b = "handR", radius = 0.048 },

	{ name = "thighL", a = "hipL", b = "kneeL", radius = 0.075 },
	{ name = "shinL", a = "kneeL", b = "ankleL", radius = 0.062 },
	{ name = "footL", a = "ankleL", b = "toeL", radius = 0.055 },
	{ name = "thighR", a = "hipR", b = "kneeR", radius = 0.075 },
	{ name = "shinR", a = "kneeR", b = "ankleR", radius = 0.062 },
	{ name = "footR", a = "ankleR", b = "toeR", radius = 0.055 },
}

-- --------------------------------------------------------------- çözüm
--[[ pose = {
	rootOffset = Vec3 (opsiyonel, tüm gövdeyi öteler),
	root = {x,y,z}, spine = {...}, hipL = {...}, ... (radyan)
} ]]
function Rig.solve(pose)
	pose = pose or {}
	local positions = {}
	local rotations = {}

	for _, joint in ipairs(Rig.joints) do
		local localRot = Rig.matFromEuler(pose[joint.name])
		if joint.parent then
			local parentRot = rotations[joint.parent]
			local parentPos = positions[joint.parent]
			rotations[joint.name] = matMul(parentRot, localRot)
			positions[joint.name] = Vec3.add(parentPos, matVec(parentRot, joint.offset))
		else
			rotations[joint.name] = localRot
			positions[joint.name] = Vec3.new(joint.offset.x, joint.offset.y, joint.offset.z)
		end
	end

	-- Tüm gövdeyi ötele (dalış, zıplama, düşme)
	local offset = pose.rootOffset
	if offset then
		for name, p in pairs(positions) do
			positions[name] = Vec3.add(p, offset)
		end
	end

	local bones = {}
	for _, bone in ipairs(Rig.bones) do
		bones[#bones + 1] = {
			name = bone.name,
			a = positions[bone.a],
			b = positions[bone.b],
			radius = bone.radius,
		}
	end

	return { pos = positions, bones = bones, rotations = rotations }
end

-- Dinlenme pozundaki kemik uzunlukları (görsel parça boyutları için)
local REST_POS = nil
function Rig.boneLengths()
	if not REST_POS then
		REST_POS = Rig.solve({}).pos
	end
	local out = {}
	for _, bone in ipairs(Rig.bones) do
		out[bone.name] = Vec3.distance(REST_POS[bone.a], REST_POS[bone.b])
	end
	return out
end

-- Yerel (rig) noktayı dünya uzayına çevirir.
-- origin: ayak noktası, yaw: baktığı yön (Vec3.yaw ile aynı ölçek)
function Rig.toWorld(localPoint, origin, yaw, studsPerMeter)
	local s = studsPerMeter or 1
	local forward = Vec3.new(cos(yaw), 0, sin(yaw))
	local up = Vec3.new(0, 1, 0)
	local right = Vec3.cross(forward, up) -- (cos,0,sin) x (0,1,0)

	local world = Vec3.add(origin, Vec3.new(
		(right.x * localPoint.x + up.x * localPoint.y + forward.x * localPoint.z) * s,
		(right.y * localPoint.x + up.y * localPoint.y + forward.y * localPoint.z) * s,
		(right.z * localPoint.x + up.z * localPoint.y + forward.z * localPoint.z) * s
	))
	return world, forward, right, up
end

return Rig
