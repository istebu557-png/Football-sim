--[[
	Pose — eklem açılarının (radyan) aritmetiği.

	Bir poz: { jointName = {x=, y=, z=}, rootOffset = Vec3 }
	Animasyonlar poz üretir, motor bunları karıştırır (yürüme + şut gibi).
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)

local Pose = {}

function Pose.new()
	return { rootOffset = Vec3.new(0, 0, 0) }
end

local function jointOf(pose, name)
	local j = pose[name]
	if not j then
		j = { x = 0, y = 0, z = 0 }
		pose[name] = j
	end
	return j
end

-- a'ya b'yi ekler (açılar toplanır, öteler vektörel toplanır)
function Pose.add(a, b)
	local out = {}
	for name, j in pairs(a) do
		if name ~= "rootOffset" then
			out[name] = { x = j.x or 0, y = j.y or 0, z = j.z or 0 }
		end
	end
	for name, j in pairs(b) do
		if name ~= "rootOffset" then
			local target = jointOf(out, name)
			target.x = target.x + (j.x or 0)
			target.y = target.y + (j.y or 0)
			target.z = target.z + (j.z or 0)
		end
	end
	local ao = a.rootOffset or Vec3.ZERO
	local bo = b.rootOffset or Vec3.ZERO
	out.rootOffset = Vec3.add(ao, bo)
	return out
end

-- a'dan b'ye t oranında geçiş
function Pose.blend(a, b, t)
	local out = {}
	local names = {}
	for name in pairs(a) do
		if name ~= "rootOffset" then
			names[name] = true
		end
	end
	for name in pairs(b) do
		if name ~= "rootOffset" then
			names[name] = true
		end
	end
	for name in pairs(names) do
		local ja = a[name] or { x = 0, y = 0, z = 0 }
		local jb = b[name] or { x = 0, y = 0, z = 0 }
		out[name] = {
			x = (ja.x or 0) + ((jb.x or 0) - (ja.x or 0)) * t,
			y = (ja.y or 0) + ((jb.y or 0) - (ja.y or 0)) * t,
			z = (ja.z or 0) + ((jb.z or 0) - (ja.z or 0)) * t,
		}
	end
	out.rootOffset = Vec3.lerp(a.rootOffset or Vec3.ZERO, b.rootOffset or Vec3.ZERO, t)
	return out
end

-- Değerleri k ile çarpar (şiddet ölçekleme)
function Pose.scale(a, k)
	local out = {}
	for name, j in pairs(a) do
		if name ~= "rootOffset" then
			out[name] = { x = (j.x or 0) * k, y = (j.y or 0) * k, z = (j.z or 0) * k }
		end
	end
	out.rootOffset = Vec3.scale(a.rootOffset or Vec3.ZERO, k)
	return out
end

-- Tek eklem için küçük yardımcı
function Pose.joint(x, y, z)
	return { x = x or 0, y = y or 0, z = z or 0 }
end

return Pose
