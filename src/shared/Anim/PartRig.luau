--[[
	PartRig — prosedürel iskeleti gerçek Roblox parçalarına çevirir.

	Kaleci (ve gerektiğinde herhangi bir NPC) için tek bir model asset'i
	kullanılmaz: 13 parça `Instance.new("Part")` ile kodla üretilir, her karede
	sunucuda FK ile konumlandırılır. Motor6D / Animation / asset ID YOKTUR.
	Parçalar Anchored olduğu için CFrame yazmak yeterli; istemciye sadece
	parçaların CFrame'i replike olur.

	Yerleşim (Rig.toWorld):
		rig +x -> oyuncunun SAĞI
		rig +y -> yukarı
		rig +z -> oyuncunun İLERİSİ (baktığı yön)

	Aynı iskelet (Rig.luau) hem ölçüm testlerinde hem görselde kullanıldığı için
	"görünen" hareket ile "hesaplanan" hareket birebir aynıdır.
]]

local Rig = require(script.Parent.Rig)
local Vec3 = require(script.Parent.Parent.Core.Vec3)

local PartRig = {}

local KIT = Color3.fromRGB(250, 214, 60)
local KIT_DARK = Color3.fromRGB(30, 44, 66)
local SKIN = Color3.fromRGB(232, 190, 160)
local SOCK = Color3.fromRGB(240, 244, 250)
local BOOT = Color3.fromRGB(24, 24, 28)
local GLOVE = Color3.fromRGB(245, 245, 250)

-- bone -> görsel stil
local STYLE = {
	pelvis = { base = KIT_DARK, fat = 1.20, torso = true },
	torso = { base = KIT, fat = 1.10, torso = true },
	head = { base = SKIN, fat = 1.00, ball = true },
	upperArmL = { base = KIT, fat = 1.00 },
	forearmL = { base = SKIN, fat = 1.00 },
	upperArmR = { base = KIT, fat = 1.00 },
	forearmR = { base = SKIN, fat = 1.00 },
	thighL = { base = KIT_DARK, fat = 1.10 },
	shinL = { base = SOCK, fat = 1.00 },
	thighR = { base = KIT_DARK, fat = 1.10 },
	shinR = { base = SOCK, fat = 1.00 },
	footL = { base = BOOT, fat = 1.00 },
	footR = { base = BOOT, fat = 1.00 },
}

local function makePart(parent, name, size, color, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.CFrame = CFrame.new(0, 0, 0)
	p.Parent = parent
	return p
end

local function bonePartName(boneName)
	return boneName:sub(1, 1):upper() .. boneName:sub(2)
end

--[[ Model kur.
	parent: Folder | Model | Workspace
	opts = { name, studsPerMeter, kitColor }
	Dönüş: { folder, parts = {bone -> Part}, gloves = {L, R}, studsPerMeter } ]]
function PartRig.build(parent, opts)
	opts = opts or {}
	local s = opts.studsPerMeter or 1
	local kitColor = opts.kitColor or KIT
	local lengths = Rig.boneLengths()

	local folder = Instance.new("Folder")
	folder.Name = opts.name or "Rig"
	folder.Parent = parent

	local parts = {}
	for _, bone in ipairs(Rig.bones) do
		local style = STYLE[bone.name] or { base = kitColor, fat = 1 }
		local thickness = bone.radius * 2 * (style.fat or 1)
		local len = lengths[bone.name] or 0.3
		local color = style.base
		if style.torso or bone.name:find("Arm") == 1 then
			color = kitColor
			if bone.name == "pelvis" then
				color = KIT_DARK
			end
		end
		parts[bone.name] = makePart(
			folder,
			bonePartName(bone.name),
			Vector3.new(thickness * s, thickness * s, len * s),
			color,
			style.ball and Enum.PartType.Ball or nil
		)
	end

	local gloves = {}
	for _, side in ipairs({ "L", "R" }) do
		gloves[side] = makePart(
			folder,
			"Glove" .. side,
			Vector3.new(0.16 * s, 0.16 * s, 0.16 * s),
			GLOVE,
			Enum.PartType.Ball
		)
	end

	return {
		folder = folder,
		parts = parts,
		gloves = gloves,
		studsPerMeter = s,
		lengths = lengths,
	}
end

--[[ Modeli poza göre konumlandırır.
	pose   : Rig.solve'un beklediği tablo (KickAnim / KeeperAnim çıktısı)
	origin : ayakların bastığı dünya noktası (STUD, Vector3) veya metre Vec3 + s
	yaw    : modelin baktığı yön (Vec3.yaw ölçeği: +x'ten +z'ye)
	s      : stud/metre ]]
function PartRig.apply(model, pose, origin, yaw, studsPerMeter)
	if not model then
		return
	end
	local s = studsPerMeter or model.studsPerMeter or 1
	local solved = Rig.solve(pose)

	local function toStuds(point)
		return Rig.toWorld(point, origin, yaw, s)
	end

	for _, bone in ipairs(Rig.bones) do
		local part = model.parts[bone.name]
		if part then
			local a = toStuds(solved.pos[bone.a])
			local b = toStuds(solved.pos[bone.b])
			local mid = Vec3.lerp(a, b, 0.5)
			local style = STYLE[bone.name]
			if style and style.ball then
				-- Kafa: kemik ortası değil, eklemden yukarı doğru yarım çap
				local dir = Vec3.unit(Vec3.sub(b, a))
				local center = Vec3.add(a, Vec3.scale(dir, bone.radius * 0.55))
				part.CFrame = CFrame.new(center.x, center.y, center.z)
			else
				local dir = Vec3.sub(b, a)
				if Vec3.length(dir) < 1e-6 then
					part.CFrame = CFrame.new(mid.x, mid.y, mid.z)
				else
					part.CFrame = CFrame.new(Vector3.new(mid.x, mid.y, mid.z), Vector3.new(b.x, b.y, b.z))
				end
			end
		end
	end

	-- Eldivenler: el eklemlerinin olduğu yerde
	for _, side in ipairs({ "L", "R" }) do
		local glove = model.gloves and model.gloves[side]
		local hand = solved.pos["hand" .. side]
		if glove and hand then
			local w = toStuds(hand)
			local wrist = toStuds(solved.pos["elbow" .. side])
			local dir = Vec3.unit(Vec3.sub(w, wrist))
			local center = Vec3.add(w, Vec3.scale(dir, 0.06))
			glove.CFrame = CFrame.new(center.x, center.y, center.z)
		end
	end

	return solved
end

return PartRig
