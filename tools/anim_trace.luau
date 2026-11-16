--[[
	Animasyon izi üreteci (geliştirme aracı).

	Animasyonlar sunucuda kodla hesaplandığı için, pozları tarayıcıda birebir
	çizebiliyoruz: burada üretilen JSON, oyunun içinde çalışan FK'nın aynısıdır
	(Rig.solve). Yani preview/anim.html elle çizilmiş bir animasyon değil,
	motorun gerçek çıktısıdır.

	Çıktı: preview/anim.json
]]

local Config = __load("shared/Config")
local Rig = __load("shared/Anim/Rig")
local KickAnim = __load("shared/Anim/KickAnim")
local KeeperAnim = __load("shared/Anim/KeeperAnim")

local HZ = 40
local JOINT_ORDER = {
	"root", "spine", "neck", "head",
	"shoulderL", "elbowL", "handL",
	"shoulderR", "elbowR", "handR",
	"hipL", "kneeL", "ankleL", "toeL",
	"hipR", "kneeR", "ankleR", "toeR",
}
local JOINT_INDEX = {}
for i, name in ipairs(JOINT_ORDER) do
	JOINT_INDEX[name] = i
end

-- Kemik listesi (eklem indeksleriyle) - sayfa çizgi çizmek için kullanır
local BONE_PAIRS = {}
for _, bone in ipairs(Rig.bones) do
	BONE_PAIRS[#BONE_PAIRS + 1] = { JOINT_INDEX[bone.a], JOINT_INDEX[bone.b], bone.radius }
end

local function round(v)
	return string.format("%.3f", v)
end

local function encodeFrames(sampleFn, duration, ball)
	local frames = {}
	local contactFrame = nil
	local steps = math.floor(duration * HZ + 0.5)
	for i = 0, steps do
		local t = i / HZ
		local pose = sampleFn(t)
		local solved = Rig.solve(pose)
		local parts = {}
		for j, name in ipairs(JOINT_ORDER) do
			local p = solved.pos[name]
			parts[j] = "[" .. round(p.x) .. "," .. round(p.y) .. "," .. round(p.z) .. "]"
		end
		frames[#frames + 1] = "[" .. table.concat(parts, ",") .. "]"
		if not contactFrame and pose and pose ~= nil then
			local isContact = t >= KickAnim.CONTACT_TIME
			if isContact then
				contactFrame = i
			end
		end
	end
	return frames, contactFrame
end

local scenes = {}

local function addScene(scene)
	scenes[#scenes + 1] = scene
end

-- ---------------------------------------------------------------- şutlar
local KICKS = {
	{
		id = "surukleme",
		label = "Yerden sürükleyici şut",
		desc = "Top yerde (0.11 m): ayak kalça hizasından geçer, gövde öne kapanır.",
		opts = { ballHeight = 0.11, ballLateral = 0.12, ballForward = 0.55, charge = 0.95 },
	},
	{
		id = "yarim-vole",
		label = "Yarım vole",
		desc = "Top 0.75 m'de: savurma düzlemi yükselir, destek ayağı yerden kesilir.",
		opts = { ballHeight = 0.75, ballLateral = 0.25, ballForward = 0.5, charge = 0.8 },
	},
	{
		id = "vole",
		label = "Vole (havadan)",
		desc = "Top 1.6 m'de: kalça 2.2 rad'e bükülür, ayak 1.4 m'ye çıkar, gövde geriye yatar.",
		opts = { ballHeight = 1.6, ballLateral = 0.1, ballForward = 0.35, charge = 0.75 },
	},
	{
		id = "sol-ayak",
		label = "Sol ayakla vuruş",
		desc = "Top oyuncunun solunda: vuran ayak topun yanına göre seçilir.",
		opts = { ballHeight = 0.11, ballLateral = -0.55, ballForward = 0.6, charge = 0.7 },
	},
	{
		id = "yavas-pas",
		label = "Yavaş pas",
		desc = "Güç 0.2: kısa hazırlık, kısa takip. Aynı iskelet, farklı genlik.",
		opts = { ballHeight = 0.11, ballLateral = -0.1, ballForward = 0.7, charge = 0.2 },
	},
}

for _, k in ipairs(KICKS) do
	local anim = KickAnim.new(k.opts)
	local frames, contactFrame = encodeFrames(function(t)
		return anim:sample(t).pose
	end, anim:duration(), true)
	addScene({
		id = k.id,
		label = k.label,
		desc = k.desc,
		view = "side",
		duration = anim:duration(),
		contact = (contactFrame or 0) / HZ,
		ball = { k.opts.ballLateral, k.opts.ballHeight, k.opts.ballForward },
		frames = frames,
		fps = HZ,
	})
end

-- ---------------------------------------------------------------- kaleci
local DIVES = {
	{
		id = "dalis-sag",
		label = "Sağa alçak dalış",
		desc = "Top sağ alt köşeye: gövde sağa devrilir, kollar topa uzanır, eller 0.4 m'ye iner.",
		opts = { dz = 1.35, height = 0.35, speed = 24 },
	},
	{
		id = "dalis-sol",
		label = "Sola alçak dalış",
		desc = "Aynı hareketin aynası; uzanma miktarı topun uzaklığına göre değişir.",
		opts = { dz = -1.9, height = 0.55, speed = 26 },
	},
	{
		id = "ziplama",
		label = "Yüksek topa zıplama",
		desc = "Top 1.9 m'de ve ortada: kaleci zıplar, iki kol dümdüz yukarı (eller 2.2 m).",
		opts = { dz = 0.25, height = 1.9, speed = 21 },
	},
	{
		id = "ziplamali-dalis",
		label = "Zıplamalı yana dalış",
		desc = "Yüksek + yanda: hem zıplama hem yana uzanma birleşir.",
		opts = { dz = 1.45, height = 1.8, speed = 23 },
	},
	{
		id = "blok",
		label = "Ayakta blok",
		desc = "Göğüs hizasına gelen topa çömelip gövdeyle kapatır.",
		opts = { dz = 0.15, height = 0.9, speed = 18 },
	},
}

for _, d in ipairs(DIVES) do
	local anim = KeeperAnim.new(d.opts)
	local frames = encodeFrames(function(t)
		return anim:sample(t).pose
	end, anim:duration(), false)
	addScene({
		id = d.id,
		label = d.label,
		desc = d.desc,
		view = "front",
		kind = anim.kind,
		duration = anim:duration(),
		reach = anim.reach,
		ball = { d.opts.dz, d.opts.height, 1.0 },
		frames = frames,
		fps = HZ,
	})
end

-- ---------------------------------------------------------------- JSON
local out = {}
out[#out + 1] = "{\"fps\":" .. HZ .. ",\"joints\":["
for i, name in ipairs(JOINT_ORDER) do
	out[#out + 1] = "\"" .. name .. "\"" .. (i < #JOINT_ORDER and "," or "")
end
out[#out + 1] = "],\"bones\":["
for i, b in ipairs(BONE_PAIRS) do
	out[#out + 1] = "[" .. b[1] .. "," .. b[2] .. "," .. b[3] .. "]" .. (i < #BONE_PAIRS and "," or "")
end
out[#out + 1] = "],\"scenes\":["
for i, sc in ipairs(scenes) do
	out[#out + 1] = "{"
	out[#out + 1] = "\"id\":\"" .. sc.id .. "\",\"label\":\"" .. sc.label .. "\",\"desc\":\"" .. sc.desc .. "\","
	out[#out + 1] = "\"view\":\"" .. sc.view .. "\",\"duration\":" .. round(sc.duration) .. ","
	out[#out + 1] = "\"fps\":" .. HZ .. ","
	out[#out + 1] = "\"kind\":" .. (sc.kind and ('"' .. sc.kind .. '"') or "null") .. ","
	out[#out + 1] = "\"reach\":" .. round(sc.reach or 0) .. ","
	out[#out + 1] = "\"contact\":" .. round(sc.contact or 0) .. ","
	out[#out + 1] = "\"ball\":[" .. round(sc.ball[1]) .. "," .. round(sc.ball[2]) .. "," .. round(sc.ball[3]) .. "],"
	out[#out + 1] = "\"frames\":[" .. table.concat(sc.frames, ",") .. "]"
	out[#out + 1] = (i < #scenes) and "}," or "}"
end
out[#out + 1] = "]}"

io.write(table.concat(out, ""))
