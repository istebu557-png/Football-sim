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

	R15 karakterlerde 12 eklem, R6 karakterlerde 5 eklem (omuz/kalça/boyun)
	sürülür; ikisi de yoksa sessizce hiçbir şey yapmaz (karakter donmaz, Roblox'un
	varsayılan animasyonu çalışmaya devam eder).
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

-- R6 karakterlerde eklem adları FARKLIDIR: bel/diz/dirsek yoktur, omuz ve kalça
-- motorları Torso'nun içinde ve adlarında boşluk vardır ("Left Shoulder").
-- R6 avatarlarda poz hiç uygulanamıyordu -> karakter donmuş görünüyordu.
-- Bu eşlemeyle omuz + kalça + boyun yine sürülür (kaba ama görünür hareket).
local JOINTS_R6 = {
	{ motor = "Neck", joint = "neck" },
	{ motor = "Left Shoulder", joint = "shoulderL" },
	{ motor = "Right Shoulder", joint = "shoulderR" },
	{ motor = "Left Hip", joint = "hipL" },
	{ motor = "Right Hip", joint = "hipR" },
}

local R15_MIN_JOINTS = 8
local R6_MIN_JOINTS = 4

-- karakter -> { {motor, joint} ... } (zayıf önbellek; yalnız BAŞARILI sonuç
-- önbelleğe alınır, karakter hâlâ yükleniyorsa sonraki karede yeniden denenir)
local cache = setmetatable({}, { __mode = "k" })

-- Yeni R15 avatarlarda Motor6D YOK: StarterPlayer.AvatarJointUpgrade varsayılan
-- olarak açık olduğundan eklemler AnimationConstraint olur. İkisini de kabul
-- etmiyoruz; aksi hâlde supported() false döner ve prosedürel poz hiç yazılmaz.
local function isPoseJoint(obj)
	return obj ~= nil and (obj:IsA("Motor6D") or obj:IsA("AnimationConstraint"))
end

local function findMotors(character, maps)
	local found = {}
	for _, map in ipairs(maps) do
		local joint = character:FindFirstChild(map.motor, true)
		if isPoseJoint(joint) then
			found[#found + 1] = { motor = joint, joint = map.joint }
		end
	end
	return found
end

local function collect(character)
	local cached = cache[character]
	if cached then
		return cached
	end
	local found = findMotors(character, JOINTS)
	if #found >= R15_MIN_JOINTS then
		cache[character] = found
		return found
	end
	-- R15 değil (ya da eksik): R6 adlarıyla dene
	local alt = findMotors(character, JOINTS_R6)
	if #alt >= R6_MIN_JOINTS then
		cache[character] = alt
		return alt
	end
	return found -- yetersiz: supported() false der, önbelleğe alınmaz
end

--[[ Karakterin pozlanabilir eklemleri var mı? (R15 ya da R6; yoksa false) ]]
function HumanoidPose.supported(character)
	if not character then
		return false
	end
	local found = collect(character)
	return #found >= R6_MIN_JOINTS
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
