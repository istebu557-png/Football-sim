--[[
	Sahte Roblox ortamı (yalnızca test için).

	Amaç: tek kurulum dosyasını ve SceneBuilder'ı Roblox olmadan ÇALIŞTIRMAK.
	Böylece "Studio'da hata veriyor" sürprizlerini yakalarız: yanlış sınıf adı,
	boş kaynak, hatalı ebeveyn, nil özellik gibi sorunlar testte ortaya çıkar.

	Taklit edilenler: Instance.new, FindFirstChild, IsA, Destroy, GetChildren,
	WaitForChild, FindFirstChildOfClass, game:GetService, workspace, Vector3,
	CFrame, Color3, Enum, bir de require (ModuleScript -> Source yükleme).
]]

local Mock = {}

local nextId = 0

local function makeVector3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, {
		__mul = function(a, k)
			if type(k) == "number" then
				return makeVector3(a.X * k, a.Y * k, a.Z * k)
			end
			return makeVector3(a.X * k.X, a.Y * k.Y, a.Z * k.Z)
		end,
		__add = function(a, b)
			return makeVector3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
		end,
		__sub = function(a, b)
			return makeVector3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
		end,
	})
end

local CFrameMeta = {}
CFrameMeta.__index = CFrameMeta
CFrameMeta.__mul = function(a, b)
	return setmetatable({ pos = a.pos, other = b }, CFrameMeta)
end

local function makeCFrame(pos)
	return setmetatable({ pos = pos or makeVector3(0, 0, 0) }, CFrameMeta)
end

local EnumMock = setmetatable({}, {
	__index = function(_, category)
		return setmetatable({}, {
			__index = function(_, item)
				return category .. "." .. item
			end,
		})
	end,
})

-- Olay (Signal) taklidi: Connect / Fire. Sunucu döngüsünü testte sürmek için.
local function makeSignal()
	local handlers = {}
	local signal = {}
	function signal:Connect(fn)
		handlers[#handlers + 1] = fn
		return {
			Disconnect = function()
				for i = #handlers, 1, -1 do
					if handlers[i] == fn then
						table.remove(handlers, i)
					end
				end
			end,
		}
	end
	function signal:Wait()
		return nil
	end
	function signal:Fire(...)
		local snapshot = {}
		for i, fn in ipairs(handlers) do
			snapshot[i] = fn
		end
		for _, fn in ipairs(snapshot) do
			fn(...)
		end
	end
	function signal:HandlerCount()
		return #handlers
	end
	return signal
end

local function makeClass(className, name)
	nextId = nextId + 1
	local obj = {
		__robloxInstance = true,
		__path = "inst" .. tostring(nextId),
		__className = className,
		__children = {},
		__props = { Name = name or className, ClassName = className },
	}

	if className == "ModuleScript" or className == "Script" or className == "LocalScript" then
		obj.__props.Source = ""
	end

	local methods = {}

	function methods:FindFirstChild(childName)
		local kids = rawget(self, "__children")
		for i = #kids, 1, -1 do
			if kids[i].__props.Name == childName then
				return kids[i]
			end
		end
		return nil
	end

	function methods:FindFirstChildOfClass(class)
		local kids = rawget(self, "__children")
		for i = #kids, 1, -1 do
			if kids[i].__className == class then
				return kids[i]
			end
		end
		return nil
	end

	function methods:WaitForChild(childName)
		return self:FindFirstChild(childName)
	end

	function methods:GetChildren()
		local out = {}
		for _, child in ipairs(rawget(self, "__children")) do
			out[#out + 1] = child
		end
		return out
	end

	function methods:IsA(class)
		return rawget(self, "__className") == class
	end

	function methods:Destroy()
		local parent = rawget(self, "__parent")
		if parent then
			local kids = rawget(parent, "__children")
			for i = #kids, 1, -1 do
				if kids[i] == self then
					table.remove(kids, i)
				end
			end
		end
		rawset(self, "__parent", nil)
	end

	for nameMethod, fn in pairs(methods) do
		rawset(obj, nameMethod, fn)
	end

	setmetatable(obj, {
		__index = function(t, key)
			if key == "Parent" then
				return rawget(t, "__parent")
			end
			if key == "ClassName" then
				return rawget(t, "__className")
			end
			local props = rawget(t, "__props")
			local value = props[key]
			if value ~= nil then
				return value
			end
			-- Roblox davranışı: alt öğeye isimle erişim
			local kids = rawget(t, "__children")
			for i = #kids, 1, -1 do
				if kids[i].__props.Name == key then
					return kids[i]
				end
			end
			return nil
		end,
		__newindex = function(t, key, value)
			if key == "Parent" then
				local old = rawget(t, "__parent")
				if old then
					local kids = rawget(old, "__children")
					for i = #kids, 1, -1 do
						if kids[i] == t then
							table.remove(kids, i)
						end
					end
				end
				rawset(t, "__parent", value)
				if value then
					table.insert(rawget(value, "__children"), t)
				end
				return
			end
			rawget(t, "__props")[key] = value
		end,
	})
	return obj
end

--[[ Sahte ortamı kurar (globalleri değiştirir) ve tutamaçları döndürür.
	Çağıran taraf, işi bitince Mock.restore() ile globalleri temizlemelidir. ]]
function Mock.install()
	local saved = {}
	local function set(name, value)
		saved[name] = _G[name]
		_G[name] = value
	end

	local workspace = makeClass("Workspace", "Workspace")
	local lighting = makeClass("Lighting", "Lighting")
	local replicatedStorage = makeClass("ReplicatedStorage", "ReplicatedStorage")
	local serverScriptService = makeClass("ServerScriptService", "ServerScriptService")
	local starterPlayer = makeClass("StarterPlayer", "StarterPlayer")
	local starterPlayerScripts = makeClass("StarterPlayerScripts", "StarterPlayerScripts")
	starterPlayerScripts.Parent = starterPlayer

	local runService = makeClass("RunService", "RunService")
	runService.Heartbeat = makeSignal()
	runService.RenderStepped = makeSignal()

	local playersService = makeClass("Players", "Players")
	playersService.PlayerAdded = makeSignal()
	playersService.PlayerRemoving = makeSignal()
	playersService.GetPlayers = function()
		return {}
	end

	local services = {
		Workspace = workspace,
		Lighting = lighting,
		ReplicatedStorage = replicatedStorage,
		ServerScriptService = serverScriptService,
		StarterPlayer = starterPlayer,
		Players = playersService,
		RunService = runService,
		UserInputService = makeClass("UserInputService", "UserInputService"),
	}

	local gameMock = {
		__robloxInstance = false,
		GetService = function(_, name)
			if not services[name] then
				services[name] = makeClass(name, name)
			end
			return services[name]
		end,
	}

	local InstanceMock = {
		new = function(class)
			local obj = makeClass(class, class)
			if class == "RemoteEvent" then
				obj.OnServerEvent = makeSignal()
				obj.OnClientEvent = makeSignal()
				obj.FireServer = function() end
				obj.FireAllClients = function() end
				obj.FireClient = function() end
			end
			return obj
		end,
	}

	set("game", gameMock)
	set("workspace", workspace)
	set("Instance", InstanceMock)
	set("Vector3", { new = makeVector3, zero = makeVector3(0, 0, 0) })
	set("CFrame", {
		new = function(a, b, c)
			if type(a) == "table" then
				return makeCFrame(a)
			end
			return makeCFrame(makeVector3(a, b, c))
		end,
		Angles = function()
			return makeCFrame()
		end,
		lookAt = function(a, b)
			return makeCFrame(a)
		end,
	})
	set("Color3", {
		fromRGB = function(r, g, b)
			return { R = r, G = g, B = b }
		end,
		new = function(r, g, b)
			return { R = r, G = g, B = b }
		end,
	})
	set("Enum", EnumMock)
	set("UDim2", { new = function() return {} end })
	set("Vector2", { new = makeVector3 })
	set("NumberSequence", { new = function() return {} end })
	set("NumberSequenceKeypoint", { new = function() return {} end })
	set("ColorSequence", { new = function() return {} end })

	-- Testler sunucu döngüsünü elle sürer
	local function stepHeartbeat(seconds, dt)
		dt = dt or 1 / 60
		local steps = math.floor(seconds / dt)
		for _ = 1, steps do
			runService.Heartbeat:Fire(dt)
		end
	end

	return {
		workspace = workspace,
		runService = runService,
		players = playersService,
		stepHeartbeat = stepHeartbeat,
		lighting = lighting,
		replicatedStorage = replicatedStorage,
		serverScriptService = serverScriptService,
		starterPlayerScripts = starterPlayerScripts,
		services = services,
		restore = function()
			for name, value in pairs(saved) do
				_G[name] = value
			end
		end,
	}
end

return Mock
