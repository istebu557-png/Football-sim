--[[
	Roblox benzetim katmanı (yalnızca test için).

	Üretim kodu, Roblox'da olduğu gibi `require(script.Parent.X)` yazar. Bu dosya
	o zinciri düz Lua'da taklit eder: modül dosyaları bir "düğüm ağacına" bağlanır,
	`script.Parent` gezintisi ve `require(<düğüm>)` çalışır.

	Böylece motor kodu Roblox'ta ve CI'da AYNI kaynaktan çalışır; kopyala-yapıştır
	veya build adımı yok.
]]

local loaded = {}
local nodes = {}

local function nodeFor(path)
	local n = nodes[path]
	if n then
		return n
	end
	n = { __path = path }
	nodes[path] = n

	local parentPath = path:match("^(.*)/[^/]+$")

	setmetatable(n, {
		__index = function(_, k)
			if k == "Parent" then
				if not parentPath then
					return nil
				end
				return nodeFor(parentPath)
			end
			return nodeFor(path .. "/" .. tostring(k))
		end,
	})
	return n
end

local realRequire = require

local function loadModule(path)
	local cached = loaded[path]
	if cached ~= nil then
		return cached
	end
	local src = SOURCES[path]
	if not src then
		error("modul bulunamadi: " .. tostring(path), 2)
	end
	local chunk, err = load(src, "@" .. path)
	if not chunk then
		error(err, 0)
	end
	local prevScript = _G.script
	_G.script = nodeFor(path)
	local ok, result = pcall(chunk)
	_G.script = prevScript
	if not ok then
		error(tostring(path) .. " yuklenemedi: " .. tostring(result), 0)
	end
	loaded[path] = result
	return result
end

_G.require = function(target)
	if type(target) == "table" and rawget(target, "__path") then
		return loadModule(rawget(target, "__path"))
	end
	return realRequire(target)
end

_G.__load = loadModule
