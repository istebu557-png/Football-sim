--[[
	SceneBuilder — Roblox sahnesini kodla kurar (Adım 2).

	Hiçbir şeyi elle yerleştirmeye gerek yok: çim, çizgiler, kaleler, direkler, ağ,
	top, ışık ve doğma noktası burada üretilir. Tek kurulum dosyası da bunu çağırır.

	Tüm ölçüler metreden stud'a çevrilir (Config.STUDS_PER_METER):
	gerçek bir saha 105 m = 375 stud uzunluğundadır, yani Roblox karakteri (~6 stud)
	gerçek ölçekte kalır. "Dev saha" hissi oluşmaz.

	Önemli: top dışındaki hiçbir parça fizik motoruna bırakılmaz; hepsi Anchored.
]]

local Config = require(script.Parent.Parent.Config)

local SceneBuilder = {}

-- Lua 5.3: math.atan(y, x) | Luau: math.atan2(y, x)
local atan2 = math.atan2 or math.atan

local S = Config.STUDS_PER_METER
local P = Config.PITCH
local LINE = 0.12 -- çizgi kalınlığı (metre)
local LINE_Y = 0.03 -- çim üstünden yükseklik (stud)

local function makePart(parent, name, sizeStuds, cframe, color, material, opts)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = sizeStuds
	p.CFrame = cframe
	p.Color = color or Color3.fromRGB(240, 244, 248)
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	if opts then
		if opts.shape then
			p.Shape = opts.shape
		end
		if opts.transparency then
			p.Transparency = opts.transparency
		end
		if opts.collide ~= nil then
			p.CanCollide = opts.collide
		end
		if opts.castShadow ~= nil then
			p.CastShadow = opts.castShadow
		end
	end
	p.Parent = parent
	return p
end

-- Metre koordinatını stud'a çevirir (yükseklik: y=0 çim yüzeyi)
local function v3(x, y, z)
	return Vector3.new(x * S, y * S, z * S)
end

-- Eksen hizalı çizgi: iki uç nokta (metre) arasında
local function drawLine(parent, name, x1, z1, x2, z2)
	local cx, cz = (x1 + x2) / 2, (z1 + z2) / 2
	local dx, dz = math.abs(x2 - x1), math.abs(z2 - z1)
	local size = Vector3.new(math.max(dx, LINE) * S, 0.04, math.max(dz, LINE) * S)
	return makePart(
		parent,
		name,
		size,
		CFrame.new(v3(cx, LINE_Y / S, cz)),
		Color3.fromRGB(246, 250, 252),
		Enum.Material.SmoothPlastic,
		{ castShadow = false }
	)
end

-- Yay çizimi (orta yuvarlak / korner yayları): küçük segmentlerden
local function drawArc(parent, name, cx, cz, radius, startAngle, endAngle, segments)
	segments = segments or 24
	for i = 1, segments do
		local a1 = startAngle + (endAngle - startAngle) * ((i - 1) / segments)
		local a2 = startAngle + (endAngle - startAngle) * (i / segments)
		local x1, z1 = cx + math.cos(a1) * radius, cz + math.sin(a1) * radius
		local x2, z2 = cx + math.cos(a2) * radius, cz + math.sin(a2) * radius
		local seg = drawLine(parent, name .. "_" .. tostring(i), x1, z1, x2, z2)
		-- Segmenti iki uç arasında döndür
		local mid = Vector3.new((x1 + x2) / 2 * S, LINE_Y, (z1 + z2) / 2 * S)
		local len = math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2) * S
		local angle = atan2(z2 - z1, x2 - x1)
		seg.CFrame = CFrame.new(mid) * CFrame.Angles(0, -angle, 0)
		seg.Size = Vector3.new(math.max(len, LINE * S), 0.04, LINE * S)
	end
end

local function buildSurface(root)
	local folder = Instance.new("Folder")
	folder.Name = "Surface"
	folder.Parent = root

	-- Çim: 105 x 68 m, üst yüzü y = 0
	local grass = makePart(
		folder,
		"Grass",
		Vector3.new(P.length * S, 2, P.width * S),
		CFrame.new(0, -1, 0),
		Color3.fromRGB(38, 104, 56),
		Enum.Material.Grass,
		{ collide = true }
	)
	grass.CastShadow = false

	-- Biçme şeritleri (görsel derinlik)
	local stripes = 10
	for i = 0, stripes - 1 do
		local w = P.length / stripes
		local x = -P.length / 2 + w * (i + 0.5)
		makePart(
			folder,
			"Stripe" .. tostring(i),
			Vector3.new(w * S, 0.02, P.width * S),
			CFrame.new(v3(x, 0.001, 0)),
			i % 2 == 0 and Color3.fromRGB(44, 116, 62) or Color3.fromRGB(40, 108, 58),
			Enum.Material.Grass,
			{ castShadow = false }
		)
	end

	return grass
end

local function buildLines(root)
	local folder = Instance.new("Folder")
	folder.Name = "Lines"
	folder.Parent = root

	local HL, HW = P.halfLength, P.halfWidth

	-- Dış çizgiler
	drawLine(folder, "TouchlineNorth", -HL, -HW, HL, -HW)
	drawLine(folder, "TouchlineSouth", -HL, HW, HL, HW)
	drawLine(folder, "GoalLineWest", -HL, -HW, -HL, HW)
	drawLine(folder, "GoalLineEast", HL, -HW, HL, HW)

	-- Orta çizgi + orta yuvarlak + santra noktası
	drawLine(folder, "HalfwayLine", 0, -HW, 0, HW)
	drawArc(folder, "CenterCircle", 0, 0, P.centerCircleRadius, 0, math.pi * 2, 40)
	makePart(
		folder,
		"CenterSpot",
		Vector3.new(0.24 * S, 0.05, 0.24 * S),
		CFrame.new(v3(0, LINE_Y / S, 0)),
		Color3.fromRGB(246, 250, 252),
		nil,
		{ shape = Enum.PartType.Cylinder, castShadow = false }
	)

	-- Ceza sahası, kale sahası, penaltı noktası (iki kale)
	for _, side in ipairs({ -1, 1 }) do
		local gl = side * HL
		local paX = gl - side * P.penaltyAreaLength
		local gaX = gl - side * P.goalAreaLength

		drawLine(folder, "PenaltyAreaLine", paX, -P.penaltyAreaHalfWidth, paX, P.penaltyAreaHalfWidth)
		drawLine(folder, "PenaltyAreaSide", gl, -P.penaltyAreaHalfWidth, paX, -P.penaltyAreaHalfWidth)
		drawLine(folder, "PenaltyAreaSide", gl, P.penaltyAreaHalfWidth, paX, P.penaltyAreaHalfWidth)

		drawLine(folder, "GoalAreaLine", gaX, -P.goalAreaHalfWidth, gaX, P.goalAreaHalfWidth)
		drawLine(folder, "GoalAreaSide", gl, -P.goalAreaHalfWidth, gaX, -P.goalAreaHalfWidth)
		drawLine(folder, "GoalAreaSide", gl, P.goalAreaHalfWidth, gaX, P.goalAreaHalfWidth)

		makePart(
			folder,
			"PenaltySpot",
			Vector3.new(0.22 * S, 0.05, 0.22 * S),
			CFrame.new(v3(gl - side * P.penaltySpot, LINE_Y / S, 0)),
			Color3.fromRGB(246, 250, 252),
			nil,
			{ shape = Enum.PartType.Cylinder, castShadow = false }
		)
	end
end

local function buildGoals(root)
	local folder = Instance.new("Folder")
	folder.Name = "Goals"
	folder.Parent = root

	local frameColor = Color3.fromRGB(248, 250, 252)
	local postDia = P.postRadius * 2
	local barDia = P.crossbarRadius * 2

	for _, side in ipairs({ -1, 1 }) do
		local gl = side * P.halfLength
		local tag = side > 0 and "East" or "West"
		local goalFolder = Instance.new("Folder")
		goalFolder.Name = "Goal" .. tag
		goalFolder.Parent = folder

		-- Yan direkler: silindir ekseni X'tir; dikey yapmak için Z ekseninde 90° döndür
		for _, sz in ipairs({ -1, 1 }) do
			makePart(
				goalFolder,
				"Post",
				Vector3.new(P.goalHeight * S, postDia * S, postDia * S),
				CFrame.new(v3(gl, P.goalHeight / 2, sz * P.goalHalfWidth)) * CFrame.Angles(0, 0, math.rad(90)),
				frameColor,
				Enum.Material.Metal,
				{ shape = Enum.PartType.Cylinder }
			)
		end

		-- Üst direk: ekseni Z'ye çevir
		makePart(
			goalFolder,
			"Crossbar",
			Vector3.new(P.goalHalfWidth * 2 * S, barDia * S, barDia * S),
			CFrame.new(v3(gl, P.goalHeight, 0)) * CFrame.Angles(0, math.rad(90), 0),
			frameColor,
			Enum.Material.Metal,
			{ shape = Enum.PartType.Cylinder }
		)

		-- Ağ: arka, iki yan, üst (yarı saydam)
		local netColor = Color3.fromRGB(230, 238, 244)
		local netOpts = { transparency = 0.45, castShadow = false }
		local depthX = gl + side * P.goalDepth

		makePart(
			goalFolder,
			"NetBack",
			Vector3.new(0.05 * S, P.goalHeight * S, P.goalHalfWidth * 2 * S),
			CFrame.new((depthX) * S, (P.goalHeight / 2) * S, 0),
			netColor,
			Enum.Material.Fabric,
			netOpts
		)
		for _, sz in ipairs({ -1, 1 }) do
			makePart(
				goalFolder,
				"NetSide",
				Vector3.new(P.goalDepth * S, P.goalHeight * S, 0.05 * S),
				CFrame.new(((gl + depthX) / 2) * S, (P.goalHeight / 2) * S, sz * P.goalHalfWidth * S),
				netColor,
				Enum.Material.Fabric,
				netOpts
			)
		end
		makePart(
			goalFolder,
			"NetTop",
			Vector3.new(P.goalDepth * S, 0.05 * S, P.goalHalfWidth * 2 * S),
			CFrame.new(((gl + depthX) / 2) * S, P.goalHeight * S, 0),
			netColor,
			Enum.Material.Fabric,
			netOpts
		)
	end
end

-- Top Workspace köküne konur: sunucu ve istemci onu Workspace.MatchBall olarak arar.
local function buildBall(root)
	local ball = makePart(
		root,
		"MatchBall",
		Vector3.new(Config.BALL.radius * 2 * S, Config.BALL.radius * 2 * S, Config.BALL.radius * 2 * S),
		CFrame.new(0, Config.BALL.radius * S, 0),
		Color3.fromRGB(248, 250, 252),
		Enum.Material.SmoothPlastic,
		{ shape = Enum.PartType.Ball }
	)
	ball.CastShadow = true
	return ball
end

local function setupLighting()
	local Lighting = game:GetService("Lighting")
	local ok = pcall(function()
		Lighting.ClockTime = 15.5
		Lighting.Brightness = 2.3
		Lighting.Ambient = Color3.fromRGB(72, 82, 92)
		Lighting.OutdoorAmbient = Color3.fromRGB(126, 136, 146)
		Lighting.EnvironmentDiffuseScale = 0.45
		Lighting.EnvironmentSpecularScale = 0.3
		Lighting.GlobalShadows = true
		Lighting.ExposureCompensation = 0.1
	end)

	if ok and not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atm = Instance.new("Atmosphere")
		atm.Density = 0.32
		atm.Haze = 1.1
		atm.Glare = 0.1
		atm.Color = Color3.fromRGB(199, 212, 224)
		atm.Parent = Lighting
	end
end

local function buildSpawn(root)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PitchSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(0, 0.5, -(P.halfWidth + 12) * S)
	spawn.Color = Color3.fromRGB(60, 120, 200)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = root
	return spawn
end

--[[ Sahneyi kurar. Var olan FootballPitch klasörünü silip yeniden oluşturur
	(idempotent). Dönüş: { root = Folder, ball = BasePart } ]]
function SceneBuilder.build()
	local existing = workspace:FindFirstChild("FootballPitch")
	if existing then
		existing:Destroy()
	end
	local oldBall = workspace:FindFirstChild("MatchBall")
	if oldBall then
		oldBall:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "FootballPitch"
	root.Parent = workspace

	buildSurface(root)
	buildLines(root)
	buildGoals(root)
	local ball = buildBall(workspace) -- kök altında değil, Workspace.MatchBall
	setupLighting()
	buildSpawn(root)

	-- Doğma noktasından düşen oyuncular çimin içine girmesin: zemin y=0.
	return { root = root, ball = ball }
end

-- Topu merkeze alır (gol sonrası / demo sıfırlama)
function SceneBuilder.resetBallPosition()
	local ball = workspace:FindFirstChild("MatchBall")
	if ball then
		ball.CFrame = CFrame.new(0, Config.BALL.radius * S, 0)
	end
end

return SceneBuilder
