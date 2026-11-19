--[[
	Sahte Roblox ortamı (yalnızca test için).

	Amaç: tek kurulum dosyasını, SceneBuilder'ı, SUNUCU döngüsünü (SimLoop) ve
	İSTEMCİ scriptini (BallView) Roblox olmadan ÇALIŞTIRMAK. Böylece "Studio'da
	hata veriyor" sürprizlerini yakalarız: yanlış sınıf adı, boş kaynak, hatalı
	ebeveyn, nil özellik, eksik remote, çağrılmayan fonksiyon...

	Taklit edilenler:
	  * Instance.new + Instance API (FindFirstChild[OfClass], WaitForChild,
	    GetChildren, GetDescendants, IsA (sınıf hiyerarşisiyle), Clone, Destroy,
	    ClearAllChildren, GetPropertyChangedSignal, isimle alt öğe erişimi)
	  * game:GetService, workspace, Workspace.CurrentCamera
	  * Vector3 / Vector2 / CFrame / Color3 / UDim / UDim2 / Enum /
	    NumberSequence / ColorSequence (gerçek matematikle)
	  * RemoteEvent DÖNGÜSÜ: FireServer -> OnServerEvent, FireAllClients /
	    FireClient -> OnClientEvent. Böylece istemci-sunucu sözleşmesi testte
	    gerçekten uçtan uca çalışır.
	  * Sinyaller: Humanoid.StateChanged, Player.CharacterAdded,
	    UserInputService.InputBegan/InputEnded, RunService.Heartbeat/RenderStepped
	  * Luau'da olup Lua 5.3'te (fengari) olmayan yardımcılar: math.clamp,
	    math.round, math.sign

	Kapsam dışı: gerçek replikasyon, görev çizelgeleme (task/coroutine),
	fizik motoru (motor zaten bizim, Roblox fiziği kullanılmıyor).
]]

local Mock = {}

local nextId = 0

-- ============================================================ Vector3 / Vector2
local Vector3Meta = {}

local function makeVector3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3Meta)
end

local function v3length(v)
	return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
end

local function v3unit(v)
	local len = v3length(v)
	if len < 1e-9 then
		return makeVector3(0, 0, 0)
	end
	return makeVector3(v.X / len, v.Y / len, v.Z / len)
end

local function v3dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end

local function v3cross(a, b)
	return makeVector3(
		a.Y * b.Z - a.Z * b.Y,
		a.Z * b.X - a.X * b.Z,
		a.X * b.Y - a.Y * b.X
	)
end

local function v3lerp(a, b, t)
	return makeVector3(
		a.X + (b.X - a.X) * t,
		a.Y + (b.Y - a.Y) * t,
		a.Z + (b.Z - a.Z) * t
	)
end

Vector3Meta.__index = function(v, key)
	if key == "Magnitude" then
		return v3length(v)
	end
	if key == "Unit" then
		return v3unit(v)
	end
	if key == "Lerp" then
		return function(self, goal, alpha)
			return v3lerp(self, goal, alpha or 0)
		end
	end
	if key == "Dot" then
		return function(self, other)
			return v3dot(self, other)
		end
	end
	if key == "Cross" then
		return function(self, other)
			return v3cross(self, other)
		end
	end
	if key == "AngleBetween" then
		return function(self, other)
			local d = v3dot(v3unit(self), v3unit(other))
			return math.acos(math.max(-1, math.min(1, d)))
		end
	end
	if key == "FuzzyEq" then
		return function(self, other, epsilon)
			epsilon = epsilon or 1e-5
			return math.abs(self.X - other.X) < epsilon
				and math.abs(self.Y - other.Y) < epsilon
				and math.abs(self.Z - other.Z) < epsilon
		end
	end
	return nil
end

Vector3Meta.__add = function(a, b)
	return makeVector3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
Vector3Meta.__sub = function(a, b)
	return makeVector3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
Vector3Meta.__mul = function(a, k)
	if type(k) == "number" then
		return makeVector3(a.X * k, a.Y * k, a.Z * k)
	end
	return makeVector3(a.X * k.X, a.Y * k.Y, a.Z * k.Z)
end
Vector3Meta.__div = function(a, k)
	if type(k) == "number" then
		return makeVector3(a.X / k, a.Y / k, a.Z / k)
	end
	return makeVector3(a.X / k.X, a.Y / k.Y, a.Z / k.Z)
end
Vector3Meta.__unm = function(a)
	return makeVector3(-a.X, -a.Y, -a.Z)
end
Vector3Meta.__eq = function(a, b)
	return getmetatable(b) == Vector3Meta and a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
Vector3Meta.__tostring = function(a)
	return string.format("%.4f, %.4f, %.4f", a.X, a.Y, a.Z)
end

local function makeVector2(x, y)
	return { X = x or 0, Y = y or 0 }
end

-- =============================================================== CFrame (3x3 + p)
-- Eksenler Roblox'taki gibi: X = sağ, Y = yukarı, Z = ARKA (LookVector = -Z).
-- `pos` alanı bu deponun kendi geleneği (spec/trace .pos okur); Roblox'taki
-- karşılığı `Position`'dır, ikisi de sağlanır.
local CFrameMeta = {}
CFrameMeta.__index = CFrameMeta

local function cfAxes(m)
	return { m[1], m[2], m[3] }, { m[4], m[5], m[6] }, { m[7], m[8], m[9] }
end

local IDENTITY_M = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

local function makeCFrame(pos, m)
	local self = setmetatable({}, CFrameMeta)
	rawset(self, "pos", pos or makeVector3(0, 0, 0))
	rawset(self, "m", m or { IDENTITY_M[1], IDENTITY_M[2], IDENTITY_M[3], IDENTITY_M[4], IDENTITY_M[5], IDENTITY_M[6], IDENTITY_M[7], IDENTITY_M[8], IDENTITY_M[9] })
	return self
end

local function cfTransformVector(cf, v)
	local m = rawget(cf, "m")
	return makeVector3(
		m[1] * v.X + m[4] * v.Y + m[7] * v.Z,
		m[2] * v.X + m[5] * v.Y + m[8] * v.Z,
		m[3] * v.X + m[6] * v.Y + m[9] * v.Z
	)
end

local function cfMultiply(a, b)
	local m1, m2 = rawget(a, "m"), rawget(b, "m")
	local m = {}
	for col = 0, 2 do
		local bx, by, bz = m2[col * 3 + 1], m2[col * 3 + 2], m2[col * 3 + 3]
		m[col * 3 + 1] = m1[1] * bx + m1[4] * by + m1[7] * bz
		m[col * 3 + 2] = m1[2] * bx + m1[5] * by + m1[8] * bz
		m[col * 3 + 3] = m1[3] * bx + m1[6] * by + m1[9] * bz
	end
	return makeCFrame(rawget(a, "pos") + cfTransformVector(a, rawget(b, "pos")), m)
end

-- Roblox CFrame.Angles: YXZ dönüş sırası (yaklaşım; testler yönden çok
-- konumu ve LookVector'ü doğrular).
local function cfFromAngles(rx, ry, rz)
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)

	local rx_m = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local ry_m = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local rz_m = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }

	local function mul3(a, b)
		local out = {}
		for col = 0, 2 do
			local bx, by, bz = b[col * 3 + 1], b[col * 3 + 2], b[col * 3 + 3]
			out[col * 3 + 1] = a[1] * bx + a[4] * by + a[7] * bz
			out[col * 3 + 2] = a[2] * bx + a[5] * by + a[8] * bz
			out[col * 3 + 3] = a[3] * bx + a[6] * by + a[9] * bz
		end
		return out
	end

	return makeCFrame(makeVector3(0, 0, 0), mul3(ry_m, mul3(rx_m, rz_m)))
end

local function cfLookAt(eye, target, up)
	local forward = v3unit(target - eye) -- LookVector
	if v3length(forward) < 1e-9 then
		forward = makeVector3(0, 0, -1)
	end
	up = up or makeVector3(0, 1, 0)
	local right = v3unit(v3cross(forward, up))
	if v3length(right) < 1e-9 then
		right = makeVector3(1, 0, 0)
	end
	local upActual = v3cross(right, forward)
	-- Kolonlar: X = sağ, Y = yukarı, Z = -ileri
	return makeCFrame(eye, {
		right.X, right.Y, right.Z,
		upActual.X, upActual.Y, upActual.Z,
		-forward.X, -forward.Y, -forward.Z,
	})
end

function CFrameMeta.__mul(a, b)
	if getmetatable(b) == CFrameMeta then
		return cfMultiply(a, b)
	end
	if getmetatable(b) == Vector3Meta then
		return rawget(a, "pos") + cfTransformVector(a, b)
	end
	error("CFrame * " .. tostring(b) .. " desteklenmiyor (mock)", 2)
end

CFrameMeta.__eq = function(a, b)
	return getmetatable(b) == CFrameMeta and rawget(a, "pos") == rawget(b, "pos")
end

CFrameMeta.__tostring = function(a)
	return "CFrame(" .. tostring(rawget(a, "pos")) .. ")"
end

-- Özellikler: Position / X / Y / Z / LookVector / RightVector / UpVector / Rotation
-- (cfMethods aşağıda: CFrameMeta'nın kendisi, ham tablo olarak okunur.)
local CF_PROPS = {
	Position = function(cf)
		return rawget(cf, "pos")
	end,
	X = function(cf)
		return rawget(cf, "pos").X
	end,
	Y = function(cf)
		return rawget(cf, "pos").Y
	end,
	Z = function(cf)
		return rawget(cf, "pos").Z
	end,
	LookVector = function(cf)
		local m = rawget(cf, "m")
		return makeVector3(-m[7], -m[8], -m[9])
	end,
	RightVector = function(cf)
		local m = rawget(cf, "m")
		return makeVector3(m[1], m[2], m[3])
	end,
	UpVector = function(cf)
		local m = rawget(cf, "m")
		return makeVector3(m[4], m[5], m[6])
	end,
	Rotation = function(cf)
		return makeCFrame(makeVector3(0, 0, 0), rawget(cf, "m"))
	end,
}

-- CFrameMeta.__index hem tablo hem fonksiyon olamaz; elle yönlendir.
-- cfMethods = CFrameMeta'nın kendisi (metatable'ı yok, yani ham okuma güvenlidir).
local cfMethods = CFrameMeta
CFrameMeta.__index = function(cf, key)
	local computed = CF_PROPS[key]
	if computed then
		return computed(cf)
	end
	return cfMethods[key]
end

function CFrameMeta:Lerp(goal, alpha)
	local p = v3lerp(rawget(self, "pos"), rawget(goal, "pos"), alpha or 0)
	return makeCFrame(p, rawget(goal, "m")) -- yönelim karışımı test için yeterli
end

function CFrameMeta:Inverse()
	local m = rawget(self, "m")
	-- Dik matris: ters = devrik
	local t = { m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] }
	local inv = makeCFrame(makeVector3(0, 0, 0), t)
	local p = rawget(self, "pos")
	return makeCFrame(-cfTransformVector(inv, p), t)
end

function CFrameMeta:ToWorldSpace(other)
	return cfMultiply(self, other)
end

function CFrameMeta:PointToWorldSpace(point)
	return rawget(self, "pos") + cfTransformVector(self, point)
end

function CFrameMeta:VectorToWorldSpace(vector)
	return cfTransformVector(self, vector)
end

function CFrameMeta:GetComponents()
	local m = rawget(self, "m")
	local p = rawget(self, "pos")
	return p.X, p.Y, p.Z, m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9]
end

local function cfNew(a, b, c, d, e, f)
	if a == nil then
		return makeCFrame(makeVector3(0, 0, 0))
	end
	if type(a) == "table" then
		if b ~= nil and type(b) == "table" then
			return cfLookAt(a, b, type(c) == "table" and c or nil)
		end
		return makeCFrame(a)
	end
	if type(b) == "number" and type(c) == "number" and d == nil then
		return makeCFrame(makeVector3(a, b, c))
	end
	-- CFrame.new(x, y, z, r00..r22): konum alınır, matris verilirse kullanılır
	if type(d) == "number" then
		return makeCFrame(makeVector3(a, b, c), { d, e or 0, f or 0, 0, 1, 0, 0, 0, 1 })
	end
	return makeCFrame(makeVector3(a, b or 0, c or 0))
end

local CFrameLib = {
	new = cfNew,
	identity = makeCFrame(makeVector3(0, 0, 0)),
	Angles = function(rx, ry, rz)
		return cfFromAngles(rx or 0, ry or 0, rz or 0)
	end,
	fromEulerAnglesXYZ = function(rx, ry, rz)
		return cfFromAngles(rx or 0, ry or 0, rz or 0)
	end,
	fromEulerAnglesYXZ = function(rx, ry, rz)
		return cfFromAngles(rx or 0, ry or 0, rz or 0)
	end,
	lookAt = function(eye, target, up)
		return cfLookAt(eye, target, up)
	end,
	fromMatrix = function(pos, x, y, z)
		return makeCFrame(pos, { x.X, x.Y, x.Z, y.X, y.Y, y.Z, z.X, z.Y, z.Z })
	end,
}

-- ====================================================================== Enum
local EnumMock = setmetatable({}, {
	__index = function(_, category)
		return setmetatable({}, {
			__index = function(_, item)
				return category .. "." .. item
			end,
		})
	end,
})

-- ==================================================================== Signal
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
	function signal:Once(fn)
		local conn
		conn = signal:Connect(function(...)
			if conn and conn.Disconnect then
				conn.Disconnect()
			end
			fn(...)
		end)
		return conn
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

-- ==================================================== sınıf hiyerarşisi (IsA)
local CLASS_PARENTS = {
	Part = "BasePart",
	SpawnLocation = "Part",
	MeshPart = "BasePart",
	TrussPart = "BasePart",
	BasePart = "PVInstance",
	PVInstance = "Instance",
	Model = "PVInstance",
	Folder = "Instance",
	Camera = "Instance",
	Humanoid = "Instance",
	Player = "Instance",
	ScreenGui = "LayerCollector",
	LayerCollector = "GuiObject",
	TextLabel = "GuiObject",
	TextButton = "GuiObject",
	Frame = "GuiObject",
	GuiObject = "GuiBase2d",
	GuiBase2d = "Instance",
	UICorner = "Instance",
	Trail = "Instance",
	Attachment = "Instance",
	Script = "LuaSourceContainer",
	LocalScript = "Script",
	ModuleScript = "LuaSourceContainer",
	LuaSourceContainer = "Instance",
	RemoteEvent = "Instance",
	RemoteFunction = "Instance",
	Atmosphere = "Instance",
	Workspace = "Model",
	Lighting = "Instance",
	ReplicatedStorage = "Instance",
	ServerScriptService = "Instance",
	ServerStorage = "Instance",
	StarterPlayer = "Instance",
	StarterPlayerScripts = "Instance",
	StarterGui = "Instance",
	StarterPack = "Instance",
	RunService = "Instance",
	Players = "Instance",
	UserInputService = "Instance",
	ContextActionService = "Instance",
	Motor6D = "Instance",
	AnimationConstraint = "Instance", -- AvatarJointUpgrade: yeni R15 eklemleri
}

local function classIsA(className, query)
	local c = className
	local guard = 0
	while c and guard < 32 do
		if c == query then
			return true
		end
		c = CLASS_PARENTS[c]
		guard = guard + 1
	end
	return query == "Instance"
end

-- Sınıf başına sinyaller (erişildiğinde tembel üretilir)
local CLASS_SIGNALS = {
	Humanoid = { "StateChanged", "Changed", "Died", "HealthChanged", "StateEnabledChanged" },
	Player = { "CharacterAdded", "CharacterRemoving", "Chatted", "Idled" },
	RemoteEvent = { "OnServerEvent", "OnClientEvent" },
	RemoteFunction = { "OnServerInvoke", "OnClientInvoke" },
	BasePart = { "Touched", "TouchEnded", "CollisionGroupChanged" },
	Model = { "PrimaryPartChanged" },
	Humanoid2 = {},
	GuiObject = { "MouseButton1Click", "Activated", "InputBegan", "InputEnded" },
}
local GENERIC_SIGNALS = {
	Changed = true,
	ChildAdded = true,
	ChildRemoved = true,
	AncestryChanged = true,
	DescendantAdded = true,
	DescendantRemoving = true,
	Destroying = true,
	AttributeChanged = true,
	Touched = true,
}

local function signalNamesFor(className)
	local out = {}
	local c = className
	local guard = 0
	while c and guard < 32 do
		local list = CLASS_SIGNALS[c]
		if list then
			for _, n in ipairs(list) do
				out[n] = true
			end
		end
		c = CLASS_PARENTS[c]
		guard = guard + 1
	end
	return out
end

-- Instance.new çağrıldığında sınıfa özel ek kurulum (env: Mock.install ortamı)
local env = nil

local function makeClass(className, name)
	nextId = nextId + 1
	local obj = {
		__robloxInstance = true,
		__path = "inst" .. tostring(nextId),
		__className = className,
		__children = {},
		__props = { Name = name or className, ClassName = className },
		__signals = signalNamesFor(className),
	}

	if className == "ModuleScript" or className == "Script" or className == "LocalScript" then
		obj.__props.Source = ""
	end
	if classIsA(className, "BasePart") then
		-- Roblox'ta okunmamış hız özellikleri sınıf varsayılanını verir (sıfır).
		obj.__props.AssemblyLinearVelocity = makeVector3(0, 0, 0)
		obj.__props.AssemblyAngularVelocity = makeVector3(0, 0, 0)
		obj.__props.Velocity = makeVector3(0, 0, 0)
		obj.__props.RotVelocity = makeVector3(0, 0, 0)
	end
	if className == "Humanoid" then
		obj.__props.__stateEnabled = {}
		obj.__props.State = "None"
	end

	local methods = {}

	function methods:FindFirstChild(childName, recursive)
		local kids = rawget(self, "__children")
		for i = #kids, 1, -1 do
			if kids[i].__props.Name == childName then
				return kids[i]
			end
		end
		if recursive then
			for _, kid in ipairs(kids) do
				local found = kid:FindFirstChild(childName, true)
				if found then
					return found
				end
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
		for _, kid in ipairs(kids) do
			local found = kid:FindFirstChildOfClass(class)
			if found then
				return found
			end
		end
		return nil
	end

	function methods:FindFirstChildWhichIsA(class)
		local kids = rawget(self, "__children")
		for _, kid in ipairs(kids) do
			if classIsA(kid.__className, class) then
				return kid
			end
		end
		return nil
	end

	function methods:WaitForChild(childName, _timeout)
		-- Mock'ta bekleme yok: varsa döner, yoksa nil (Roblox'ta timeout'ta nil).
		return self:FindFirstChild(childName)
	end

	function methods:GetChildren()
		local out = {}
		for _, child in ipairs(rawget(self, "__children")) do
			out[#out + 1] = child
		end
		return out
	end

	function methods:GetDescendants()
		local out = {}
		local function walk(node)
			for _, child in ipairs(rawget(node, "__children")) do
				out[#out + 1] = child
				walk(child)
			end
		end
		walk(self)
		return out
	end

	function methods:GetFullName()
		local parts = {}
		local node = self
		local guard = 0
		while node and guard < 64 do
			parts[#parts + 1] = tostring(node.__props.Name)
			node = rawget(node, "__parent")
			guard = guard + 1
		end
		local rev = {}
		for i = #parts, 1, -1 do
			rev[#rev + 1] = parts[i]
		end
		return table.concat(rev, ".")
	end

	function methods:IsA(class)
		return classIsA(rawget(self, "__className"), class)
	end

	function methods:IsDescendantOf(other)
		local node = rawget(self, "__parent")
		local guard = 0
		while node and guard < 64 do
			if node == other then
				return true
			end
			node = rawget(node, "__parent")
			guard = guard + 1
		end
		return false
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
		rawset(self, "__destroyed", true)
		local kids = rawget(self, "__children")
		local snapshot = {}
		for _, child in ipairs(kids) do
			snapshot[#snapshot + 1] = child
		end
		for i = #kids, 1, -1 do
			kids[i] = nil
		end
		for _, child in ipairs(snapshot) do
			child:Destroy()
		end
	end

	function methods:ClearAllChildren()
		local kids = rawget(self, "__children")
		local snapshot = {}
		for _, child in ipairs(kids) do
			snapshot[#snapshot + 1] = child
		end
		for i = #kids, 1, -1 do
			kids[i] = nil
		end
		for _, child in ipairs(snapshot) do
			child:Destroy()
		end
	end

	function methods:Clone()
		local copy = makeClass(rawget(self, "__className"), rawget(self, "__props").Name)
		for key, value in pairs(rawget(self, "__props")) do
			-- Mock içi alanlar (__) ve isim/sınıf kopyalanmaz; gerisi taşınır
			if key ~= "Name" and key ~= "ClassName" and key:sub(1, 2) ~= "__" then
				copy.__props[key] = value
			end
		end
		local kids = rawget(self, "__children")
		local snapshot = {}
		for _, child in ipairs(kids) do
			snapshot[#snapshot + 1] = child
		end
		for _, child in ipairs(snapshot) do
			local childCopy = child:Clone()
			childCopy.Parent = copy
		end
		return copy
	end

	function methods:GetPropertyChangedSignal(property)
		local props = rawget(self, "__props")
		props.__propSignals = props.__propSignals or {}
		if not props.__propSignals[property] then
			props.__propSignals[property] = makeSignal()
		end
		return props.__propSignals[property]
	end

	function methods:GetAttribute(key)
		local attrs = rawget(self, "__props").__attributes
		return attrs and attrs[key]
	end

	function methods:SetAttribute(key, value)
		local props = rawget(self, "__props")
		props.__attributes = props.__attributes or {}
		props.__attributes[key] = value
	end

	-- Humanoid
	function methods:SetStateEnabled(state, enabled)
		local map = rawget(self, "__props").__stateEnabled
		if map then
			map[tostring(state)] = enabled and true or false
		end
	end

	function methods:GetStateEnabled(state)
		local map = rawget(self, "__props").__stateEnabled
		if not map then
			return true
		end
		local v = map[tostring(state)]
		if v == nil then
			return true
		end
		return v
	end

	function methods:ChangeState(state)
		local props = rawget(self, "__props")
		local old = props.State
		props.State = tostring(state)
		-- StateChanged tembel üretilir; self üzerinden oku ki bağlantılar alsın
		local signal = self.StateChanged
		if signal and signal.Fire then
			signal:Fire(old, tostring(state))
		end
	end

	function methods:GetState()
		return rawget(self, "__props").State
	end

	-- Humanoid / Animator: oynayan AnimationTrack'ler. Gerçek Roblox'ta bir
	-- track oynarken Animator Motor6D.Transform'u her karede ezer; testler
	-- prosedürel pozun bu track'leri durdurduğunu ölçebilsin diye taklit edilir.
	function methods:GetPlayingAnimationTracks()
		return rawget(self, "__props").__playingTracks or {}
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
			-- BasePart.Position, CFrame'den türetilir (Roblox'ta da eşdeğerdir)
			if key == "Position" and props.CFrame ~= nil then
				local cf = props.CFrame
				if getmetatable(cf) == CFrameMeta then
					return rawget(cf, "pos")
				end
			end
			-- Sinyaller tembel üretilir (Humanoid.StateChanged, CharacterAdded...)
			local signals = rawget(t, "__signals")
			if signals and signals[key] then
				local signal = makeSignal()
				props[key] = signal
				return signal
			end
			if GENERIC_SIGNALS[key] then
				local signal = makeSignal()
				props[key] = signal
				return signal
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
					local added = rawget(value, "__props").ChildAdded
					if added and added.Fire then
						added:Fire(t)
					end
				end
				return
			end
			local props = rawget(t, "__props")
			props[key] = value
			-- BasePart.CFrame yazılınca Position da tutarlı kalsın
			if key == "CFrame" and getmetatable(value) == CFrameMeta then
				props.Position = rawget(value, "pos")
			elseif key == "Position" and getmetatable(value) == Vector3Meta then
				props.CFrame = makeCFrame(value)
			end
			local signal = props.Changed
			if signal and signal.Fire then
				signal:Fire(key)
			end
			local propSignals = props.__propSignals
			if propSignals and propSignals[key] then
				propSignals[key]:Fire()
			end
		end,
	})

	-- Sınıfa özel davranışlar
	if className == "RemoteEvent" or className == "RemoteFunction" then
		-- Ortamı ÜRETİM ANINDA yakala: birden fazla sahte dünya kurulduğunda
		-- (grup 8 / 10 / 12) remote'lar kendi dünyalarının oyuncusuna bağlansın.
		local myEnv = env
		obj.OnServerEvent = makeSignal()
		obj.OnClientEvent = makeSignal()
		obj.FireServer = function(self, ...)
			if myEnv then
				myEnv.recordRemote(self, "FireServer", ...)
				-- İstemci -> sunucu: sunucu tarafı (player, ...) alır
				self.OnServerEvent:Fire(myEnv.localPlayer, ...)
			end
		end
		obj.FireClient = function(self, _player, ...)
			if myEnv then
				myEnv.recordRemote(self, "FireClient", ...)
				self.OnClientEvent:Fire(...)
			end
		end
		obj.FireAllClients = function(self, ...)
			if myEnv then
				myEnv.recordRemote(self, "FireAllClients", ...)
				self.OnClientEvent:Fire(...)
			end
		end
	end

	return obj
end

-- ================================================================== Mock.install
--[[ Sahte ortamı kurar (globalleri değiştirir) ve tutamaçları döndürür.
	Çağıran taraf, işi bitince Mock.restore() ile globalleri temizlemelidir. ]]
function Mock.install()
	local saved = {}
	local function set(name, value)
		saved[name] = { value = _G[name], had = _G[name] ~= nil }
		_G[name] = value
	end

	-- Luau'da var, Lua 5.3'te yok (fengari): motor kodu Roblox'ta çalışsın diye
	local addedMath = {}
	local function polyfill(name, fn)
		if math[name] == nil then
			math[name] = fn
			addedMath[name] = true
		end
	end
	polyfill("clamp", function(v, lo, hi)
		if v < lo then
			return lo
		end
		if v > hi then
			return hi
		end
		return v
	end)
	polyfill("round", function(v)
		return math.floor(v + 0.5)
	end)
	polyfill("sign", function(v)
		if v > 0 then
			return 1
		elseif v < 0 then
			return -1
		end
		return 0
	end)

	local workspace = makeClass("Workspace", "Workspace")
	local lighting = makeClass("Lighting", "Lighting")
	local replicatedStorage = makeClass("ReplicatedStorage", "ReplicatedStorage")
	local serverScriptService = makeClass("ServerScriptService", "ServerScriptService")
	local serverStorage = makeClass("ServerStorage", "ServerStorage")
	local starterPlayer = makeClass("StarterPlayer", "StarterPlayer")
	local starterPlayerScripts = makeClass("StarterPlayerScripts", "StarterPlayerScripts")
	local starterGui = makeClass("StarterGui", "StarterGui")
	starterPlayerScripts.Parent = starterPlayer

	-- Ekran/fare modeli: gerçek Roblox'ta ViewportPointToRay, kameranın CFrame'i +
	-- FieldOfView + viewport boyutuyla bir ekran noktasını dünya ışınına çevirir.
	-- Aynı matematik burada da uygulanır; böylece BallView'un FARE ile nişan alma
	-- yolu test edilebilir olur (fare hareketi nişan noktasını değiştirmelidir).
	local viewportSize = makeVector2(1920, 1080)
	local mouseLocation = makeVector2(960, 540) -- ekran merkezi

	local camera = makeClass("Camera", "Camera")
	camera.CFrame = makeCFrame(makeVector3(0, 10, 0))
	camera.CameraType = "Enum.CameraType.Custom"
	camera.FieldOfView = 70
	camera.ViewportSize = viewportSize
	camera.Parent = workspace
	workspace.__props.CurrentCamera = camera

	camera.ViewportPointToRay = function(self, x, y, depth)
		depth = depth or 0
		local vp = viewportSize
		local fov = self.FieldOfView or 70
		local aspect = vp.X / vp.Y
		local halfH = math.tan(math.rad(fov) / 2) -- dikey yarı açının tanjantı
		local halfW = halfH * aspect
		local nx = (x / vp.X) * 2 - 1 -- -1..1, sağa pozitif
		local ny = 1 - (y / vp.Y) * 2 -- -1..1, yukarı pozitif (ekran y aşağı büyür)
		local cf = self.CFrame
		local dir = v3unit(cf.LookVector + cf.RightVector * (nx * halfW) + cf.UpVector * (ny * halfH))
		return {
			Origin = cf.Position + dir * depth,
			Direction = dir,
			Unit = dir,
		}
	end

	local runService = makeClass("RunService", "RunService")
	runService.Heartbeat = makeSignal()
	runService.RenderStepped = makeSignal()
	runService.PreSimulation = makeSignal() -- Motor6D/AnimationConstraint pozları
	runService.Stepped = makeSignal()
	runService.IsServer = function()
		return true
	end
	runService.IsClient = function()
		return true
	end
	runService.IsStudio = function()
		return true
	end

	local playersService = makeClass("Players", "Players")
	playersService.PlayerAdded = makeSignal()
	playersService.PlayerRemoving = makeSignal()
	local joinedPlayers = {}
	playersService.GetPlayers = function()
		local out = {}
		for i, p in ipairs(joinedPlayers) do
			out[i] = p
		end
		return out
	end

	local userInputService = makeClass("UserInputService", "UserInputService")
	userInputService.InputBegan = makeSignal()
	userInputService.InputEnded = makeSignal()
	userInputService.InputChanged = makeSignal()
	userInputService.TouchEnabled = false
	userInputService.GamepadEnabled = false
	userInputService.KeyboardEnabled = true
	-- GetMouseLocation: üst bar (topbar inset) hariç ekran pikseli; nişan ışını buradan kurulur
	userInputService.GetMouseLocation = function()
		return mouseLocation
	end

	local contextActionService = makeClass("ContextActionService", "ContextActionService")
	contextActionService.BindAction = function() end
	contextActionService.UnbindAction = function() end
	contextActionService.BindActionAtPriority = function() end

	local services = {
		Workspace = workspace,
		Lighting = lighting,
		ReplicatedStorage = replicatedStorage,
		ReplicatedFirst = makeClass("ReplicatedFirst", "ReplicatedFirst"),
		ServerScriptService = serverScriptService,
		ServerStorage = serverStorage,
		StarterPlayer = starterPlayer,
		StarterGui = starterGui,
		Players = playersService,
		RunService = runService,
		UserInputService = userInputService,
		ContextActionService = contextActionService,
		SoundService = makeClass("SoundService", "SoundService"),
		Debris = (function()
			local d = makeClass("Debris", "Debris")
			d.AddItem = function() end
			return d
		end)(),
	}

	local gameMock = {
		__robloxInstance = false,
		GetService = function(_, name)
			if not services[name] then
				services[name] = makeClass(name, name)
			end
			return services[name]
		end,
		FindFirstChild = function(_, name)
			return services[name]
		end,
	}

	local InstanceMock = {
		new = function(class, parent)
			local obj = makeClass(class)
			if parent then
				obj.Parent = parent
			end
			return obj
		end,
	}

	-- Yerel oyuncu (istemci tarafı) + sunucuya "katılmış" oyuncu listesi
	-- Gerçek R15 karakterdeki Motor6D adları (HumanoidPose.JOINTS ile aynı küme)
	local R15_JOINTS = {
		"Waist", "Neck", "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee",
		"RightAnkle", "LeftShoulder", "LeftElbow", "RightShoulder", "RightElbow",
	}

	local function makeCharacter(spawnPosition)
		local model = makeClass("Model", "Tester")
		local hrp = makeClass("Part", "HumanoidRootPart")
		hrp.Size = makeVector3(2, 2, 1)
		hrp.CFrame = makeCFrame(spawnPosition or makeVector3(0, 3, 0))
		hrp.Parent = model
		local head = makeClass("Part", "Head")
		head.Size = makeVector3(1.25, 1.25, 1.25)
		head.CFrame = makeCFrame((spawnPosition or makeVector3(0, 3, 0)) + makeVector3(0, 1.5, 0))
		head.Parent = model
		local humanoid = makeClass("Humanoid", "Humanoid")
		humanoid.RigType = "R15" -- HumanoidPose yalnız Motor6D adlarına bakar
		humanoid.Parent = model
		-- Gerçek karakterde Roblox'un varsayılan animasyon LocalScript'i vardır
		-- ve her karede Motor6D.Transform'a KENDİ pozunu yazar. İstemci prosedürel
		-- pozlama çalışıyorsa onu kapatmalı; bu davranış test edilebilsin diye
		-- mock karakter de aynı script'i taşır.
		local animate = makeClass("LocalScript", "Animate")
		animate.Disabled = false
		animate.Parent = model
		-- R15 eklem Motor6D'leri: gerçek karakterde HumanoidPose bunların
		-- Transform'una yazar. Mock'ta yoksa poz kodu sessizce atlanır ve
		-- "animasyon gerçekten uygulanıyor mu" test edilemez.
		for _, jointName in ipairs(R15_JOINTS) do
			local motor = makeClass("Motor6D", jointName)
			motor.Transform = makeCFrame()
			motor.Parent = model
		end
		model.PrimaryPart = hrp
		return model, hrp, humanoid
	end

	local function makePlayer(name, spawnPosition, opts)
		opts = opts or {}
		local player = makeClass("Player", name or "Tester")
		player.UserId = 1
		player.Name = name or "Tester"
		local playerGui = makeClass("Folder", "PlayerGui")
		playerGui.Parent = player
		local backpack = makeClass("Folder", "Backpack")
		backpack.Parent = player
		local character, hrp, humanoid = makeCharacter(spawnPosition)
		character.Parent = workspace
		player.__props.Character = character
		player.CharacterAdded = makeSignal()
		player.GetMouse = function()
			return makeClass("Mouse", "Mouse")
		end
		if opts.join ~= false then
			joinedPlayers[#joinedPlayers + 1] = player
		end
		return player, character, hrp, humanoid
	end

	local localPlayer = makePlayer("LocalTester", makeVector3(0, 3, 0), { join = false })
	-- LocalScript'ler Players.LocalPlayer bekler; sunucu tarafinda bu alan
	-- Roblox'ta nil'dir, burada istemci testleri icin doldurulur.
	playersService.__props.LocalPlayer = localPlayer
	playersService.__props.LocalPlayerReady = localPlayer

	-- Remote çağrı kaydı (istemci<->sunucu sözleşmesi testleri için)
	local remoteLog = {}
	local function recordRemote(instance, direction, ...)
		local args = { ... }
		remoteLog[#remoteLog + 1] = {
			name = instance.__props.Name,
			direction = direction,
			argCount = select("#", ...),
			args = args,
		}
	end

	env = {
		localPlayer = localPlayer,
		recordRemote = recordRemote,
		remoteLog = remoteLog,
		workspace = workspace,
	}

	-- Roblox global'leri: print/warn (bootstrap kurulum raporu bunlari kullanir)
	if _G.warn == nil then
		saved.warn = { value = nil, had = false }
		_G.warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring(select(i, ...))
			end
			io.stderr:write("[warn] " .. table.concat(parts, " ") .. "\n")
		end
	end

	set("game", gameMock)
	set("workspace", workspace)
	set("Instance", InstanceMock)
	set("Vector3", {
		new = makeVector3,
		zero = makeVector3(0, 0, 0),
		one = makeVector3(1, 1, 1),
		xAxis = makeVector3(1, 0, 0),
		yAxis = makeVector3(0, 1, 0),
		zAxis = makeVector3(0, 0, 1),
		magnitude = v3length,
		dot = v3dot,
		cross = v3cross,
		lerp = v3lerp,
	})
	set("Vector2", { new = makeVector2, zero = makeVector2(0, 0), one = makeVector2(1, 1) })
	set("CFrame", CFrameLib)
	set("Color3", {
		-- GERÇEK Roblox semantiği: fromRGB 0-255 alır, 0..1'e normalize eder.
		-- (Eskiden ham 0-255 saklanıyordu; Color bileşeni okuyan her kod/mock
		-- karşılaştırması yanlış ölçekle çalışıyordu.)
		fromRGB = function(r, g, b)
			return { R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255 }
		end,
		fromHSV = function(h, s, v)
			return { R = v, G = v, B = v, H = h, S = s, V = v }
		end,
		new = function(r, g, b)
			return { R = r or 0, G = g or 0, B = b or 0 }
		end,
	})
	set("Enum", EnumMock)
	set("UDim", {
		new = function(scale, offset)
			return { Scale = scale or 0, Offset = offset or 0 }
		end,
		fromScale = function(s)
			return { Scale = s, Offset = 0 }
		end,
		fromOffset = function(o)
			return { Scale = 0, Offset = o }
		end,
	})
	set("UDim2", {
		new = function(a, b, c, d)
			if type(a) == "table" then
				return { X = a, Y = b or a }
			end
			return {
				X = { Scale = a or 0, Offset = b or 0 },
				Y = { Scale = c or 0, Offset = d or 0 },
			}
		end,
		fromScale = function(x, y)
			return { X = { Scale = x, Offset = 0 }, Y = { Scale = y, Offset = 0 } }
		end,
		fromOffset = function(x, y)
			return { X = { Scale = 0, Offset = x }, Y = { Scale = 0, Offset = y } }
		end,
	})
	set("NumberSequence", {
		new = function(a)
			return { Keypoints = a }
		end,
	})
	set("NumberSequenceKeypoint", {
		new = function(time, value, envelope)
			return { Time = time, Value = value, Envelope = envelope or 0 }
		end,
	})
	set("ColorSequence", {
		new = function(a)
			return { Keypoints = a }
		end,
	})
	set("NumberRange", {
		new = function(a, b)
			return { Min = a, Max = b or a }
		end,
	})
	set("BrickColor", {
		new = function(name)
			return { Name = name }
		end,
	})
	set("task", {
		wait = function()
			return 0
		end,
		spawn = function(fn, ...)
			if fn then
				fn(...)
			end
		end,
		defer = function(fn, ...)
			if fn then
				fn(...)
			end
		end,
	})

	-- Testler döngüleri elle sürer
	local function stepSignal(signal, seconds, dt)
		dt = dt or 1 / 60
		local steps = math.floor(seconds / dt)
		for _ = 1, steps do
			signal:Fire(dt)
		end
		return steps
	end

	local function stepHeartbeat(seconds, dt)
		return stepSignal(runService.Heartbeat, seconds, dt)
	end

	local function stepRenderStepped(seconds, dt)
		return stepSignal(runService.RenderStepped, seconds, dt)
	end

	-- Tuş basma/bırakma (UserInputService)
	local function keyInput(keyCodeName, extra)
		local input = {
			KeyCode = "KeyCode." .. tostring(keyCodeName),
			UserInputType = "Enum.UserInputType.Keyboard",
			Position = makeVector3(0, 0, 0),
			Delta = makeVector3(0, 0, 0),
		}
		if extra then
			for k, v in pairs(extra) do
				input[k] = v
			end
		end
		return input
	end

	local function pressKey(keyCodeName, processed)
		userInputService.InputBegan:Fire(keyInput(keyCodeName), processed or false)
	end

	local function releaseKey(keyCodeName, processed)
		userInputService.InputEnded:Fire(keyInput(keyCodeName), processed or false)
	end

	local restoreFn = function()
		for name, info in pairs(saved) do
			if info.had then
				_G[name] = info.value
			else
				_G[name] = nil
			end
		end
		for name in pairs(addedMath) do
			math[name] = nil
		end
		env = nil
	end

	-- Test yardımcısı: fareyi ekran noktasına taşı (nişan testleri bunu sürer)
	local function setMouseLocation(x, y)
		mouseLocation = makeVector2(x, y)
		return mouseLocation
	end

	-- Test yardımcısı: karakterin Humanoid'inde oynayan bir track oluşturur.
	-- İstemci prosedürel pozlamaya geçince bu track durdurulmalıdır.
	local function addPlayingTrack(character, name)
		local humanoid = character and character:FindFirstChild("Humanoid", true)
		if not humanoid then
			return nil
		end
		local props = rawget(humanoid, "__props")
		props.__playingTracks = props.__playingTracks or {}
		local track = { Name = name or "RunAnim", stopped = false }
		function track:Stop(_fadeTime)
			self.stopped = true
		end
		props.__playingTracks[#props.__playingTracks + 1] = track
		return track
	end

	-- AvatarJointUpgrade taklidi: Motor6D yerine AnimationConstraint eklemleri.
	local function upgradeJoints(character)
		local names = {}
		for _, obj in ipairs(character:GetChildren()) do
			if obj:IsA("Motor6D") then
				names[#names + 1] = obj.Name
				obj:Destroy()
			end
		end
		for _, name in ipairs(names) do
			local joint = makeClass("AnimationConstraint", name)
			joint.Transform = makeCFrame()
			joint.Parent = character
		end
		return #names
	end

	return {
		workspace = workspace,
		runService = runService,
		players = playersService,
		camera = camera,
		userInputService = userInputService,
		viewportSize = viewportSize,
		setMouseLocation = setMouseLocation,
		addPlayingTrack = addPlayingTrack,
		upgradeJoints = upgradeJoints,
		getMouseLocation = function()
			return mouseLocation
		end,
		stepHeartbeat = stepHeartbeat,
		stepRenderStepped = stepRenderStepped,
		stepSignal = stepSignal,
		lighting = lighting,
		replicatedStorage = replicatedStorage,
		serverScriptService = serverScriptService,
		serverStorage = serverStorage,
		starterPlayerScripts = starterPlayerScripts,
		userInputService = userInputService,
		contextActionService = contextActionService,
		camera = camera,
		localPlayer = localPlayer,
		makePlayer = makePlayer,
		makeCharacter = makeCharacter,
		joinedPlayers = joinedPlayers,
		pressKey = pressKey,
		releaseKey = releaseKey,
		keyInput = keyInput,
		remoteLog = remoteLog,
		services = services,
		signal = makeSignal,
		restore = restoreFn,
	}
end

-- Sınıf hiyerarşisi dışarıdan da sorgulanabilsin (statik denetim araçları için)
Mock.classIsA = classIsA
Mock.makeSignal = makeSignal

return Mock
