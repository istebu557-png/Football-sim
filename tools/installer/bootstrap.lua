--[[
	KURULUM MANTIĞI (tek kurulum dosyasının gövdesi)

	Yukarıdaki SOURCES tablosunu okur, oyuna yazar, sahneyi kurar.
	Roblox Studio'nun Command Bar'ında çalıştırılmalıdır (Script.Source yazma
	yetkisi orada vardır).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")

local ROOTS = {
	shared = ReplicatedStorage,
	server = ServerScriptService,
	client = StarterPlayerScripts,
}

local ROOT_FOLDER_NAMES = {
	shared = "Shared",
	server = "Server",
	client = "Client",
}

local function ensureFolder(parent, name)
	if not parent then
		return nil
	end
	local existing = parent:FindFirstChild(name)
	if existing and not existing:IsA("Folder") then
		existing:Destroy()
		existing = nil
	end
	if not existing then
		existing = Instance.new("Folder")
		existing.Name = name
		existing.Parent = parent
	end
	return existing
end

local function ensureScript(parent, name, className)
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName ~= className then
		existing:Destroy()
		existing = nil
	end
	if not existing then
		existing = Instance.new(className)
		existing.Name = name
		existing.Parent = parent
	end
	return existing
end

local function splitPath(p)
	local parts = {}
	for part in string.gmatch(p, "[^/]+") do
		table.insert(parts, part)
	end
	return parts
end

-- 1) Scriptleri yaz ---------------------------------------------------------
local keys = {}
for key in pairs(SOURCES) do
	table.insert(keys, key)
end
table.sort(keys)

local written, sourceFailed = 0, 0

for _, key in ipairs(keys) do
	local entry = SOURCES[key]
	local rootName, rest = string.match(key, "^(%w+)/(.+)$")
	local root = rootName and ROOTS[rootName]

	if root and rest then
		local folderName = ROOT_FOLDER_NAMES[rootName]
		local parent = folderName and ensureFolder(root, folderName) or root

		local parts = splitPath(rest)
		for i = 1, #parts - 1 do
			parent = ensureFolder(parent, parts[i])
		end

		local name = parts[#parts]
		if parent and name then
			local inst = ensureScript(parent, name, entry.class)
			local ok = pcall(function()
				inst.Source = entry.source
			end)
			if ok then
				written = written + 1
			else
				sourceFailed = sourceFailed + 1
			end
		end
	else
		warn("[FootballSim] Taninmayan modul yolu: " .. tostring(key))
	end
end

-- 2) Sahneyi kur ------------------------------------------------------------
local sceneOk, sceneErr = pcall(function()
	local SceneBuilder = require(ReplicatedStorage.Shared.World.SceneBuilder)
	SceneBuilder.build()
end)

-- 3) Rapor ------------------------------------------------------------------
local msg = {}
table.insert(msg, "==================================================")
table.insert(msg, "  FootballSim kurulumu")
table.insert(msg, "==================================================")
table.insert(msg, string.format("  Scriptler : %d yazildi, %d basarisiz", written, sourceFailed))
table.insert(msg, "  Sahne     : " .. (sceneOk and "kuruldu (cim, cizgiler, kaleler, ag, top, isik)" or ("HATA - " .. tostring(sceneErr))))
table.insert(msg, "")
table.insert(msg, "  Simdi Play'e bas. SPACE ile sut cekebilirsin.")
table.insert(msg, "  Top fizigi: 240 Hz, kendi motorumuz (Roblox fizigi kullanilmaz).")
table.insert(msg, "==================================================")
print(table.concat(msg, "\n"))

if sourceFailed > 0 then
	warn("[FootballSim] " .. tostring(sourceFailed) .. " script yazilamadi. Command Bar yerine")
	warn("bir Script icinden calistirdiysaniz Source yazma yetkisi yoktur;")
	warn("Command Bar'da calistirin ya da Rojo kullanin (rojo serve).")
end
