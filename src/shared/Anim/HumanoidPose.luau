--[[
	HumanoidPose — R15 karakterinin eklemlerini sunucudan, kodla sürmek.

	Roblox'ta bir karakterin hareketi normalde yayınlanmış Animation asset'leriyle
	oynar. Burada asset yok: Motor6D.Transform her karede yazılıyor. Bu, Animator
	sisteminin kullandığı mekanizmanın aynısı (C0 * Transform * C1^-1), yani
	kemik hiyerarşisi ve kemik uzunlukları korunur.

	Eksen dönüşümü (Rig -> Roblox karakteri):
		Rig: +x sağ, +y yukarı, +z İLERİ
		Roblox karakteri: +x sağ, +y yukarı, -z ileri (LookVector = -Z)
		Ayna dönüşümü olduğu için Euler işaretleri: (x, y, z) -> (-x, -y, +z)

	Bu modül yalnızca R15 karakterlerde çalışır (R6'da sessizce hiçbir şey yapmaz).
	Karakterin kendi Animate script'i de Transform yazdığı için görsel çakışma
	olabilir: Config.ANIM.poseHumanoid = false ile kapatılabilir.
]]

local HumanoidPose = {}

-- Motor6D adı -> Rig eklemi
local JOINTS = {
	{ motor = "Waist", joint = "spine" },
	{ motor = "Neck", joint = "neck" },
	{ motor = "LeftHip", joint = "hipL" },
	{ motor = "LeftKnee", joint = "kneeL" },
	{ motor = "LeftAnkle", joint = "ankleL" },
	{ motor = "RightHip", joint = "hipR" },
	{ motor = "RightKnee", joint = "kneeR" },
	{ motor = "RightAnkle", joint = "ankleR" },
	{ motor = "LeftShoulder", joint = "shoulderL" },
	{ motor = "LeftElbow", joint = "elbowL" },
	{ motor = "RightShoulder", joint = "shoulderR" },
	{ motor = "RightElbow", joint = "elbowR" },
}

-- karakter -> { {motor, joint} ... } (zayıf önbellek)
local cache = setmetatable({}, { __mode = "k" })

local function collect(character)
	local found = cache[character]
	if found then
		return found
	end
	found = {}
	for _, map in ipairs(JOINTS) do
		local motor = character:FindFirstChild(map.motor, true)
		if motor and motor:IsA("Motor6D") then
			found[#found + 1] = { motor = motor, joint = map.joint }
		end
	end
	cache[character] = found
	return found
end

--[[ Karakterin R15 eklemleri var mı? (yoksa sessizce false) ]]
function HumanoidPose.supported(character)
	if not character then
		return false
	end
	return #collect(character) >= 8
end

local function anglesFor(pose, jointName)
	local a = pose and pose[jointName]
	if not a then
		return nil
	end
	local x, y, z = a.x or 0, a.y or 0, a.z or 0
	if x == 0 and y == 0 and z == 0 then
		return nil
	end
	return -x, -y, z
end

--[[ Pozu uygular. pose = KickAnim:sample(t).pose (veya nil = dinlenme) ]]
function HumanoidPose.apply(character, pose)
	local joints = collect(character)
	if #joints == 0 then
		return false
	end
	for _, entry in ipairs(joints) do
		local x, y, z = anglesFor(pose, entry.joint)
		if x then
			entry.motor.Transform = CFrame.Angles(x, y, z)
		else
			entry.motor.Transform = CFrame.new()
		end
	end
	return true
end

--[[ Karakteri motorun kendi animasyonuna bırakır ]]
function HumanoidPose.clear(character)
	local joints = collect(character)
	for _, entry in ipairs(joints) do
		entry.motor.Transform = CFrame.new()
	end
	cache[character] = nil
end

HumanoidPose.JOINTS = JOINTS

return HumanoidPose
