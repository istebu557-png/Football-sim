--[[
	SceneBuilder — Roblox sahnesini kodla kurar (Adım 2 + Adım 3).

	Adım 3 kapsamı (kullanıcı isteği): YARIM SAHA, 1 kale, 1 kaleci, 1 şutçu.
	`SceneBuilder.build({ half = true })` yarım sahayı kurar; `half = false` tam
	sahayı (ileride 11v11 için) kurar.

	Tüm ölçüler metreden stud'a çevrilir (Config.STUDS_PER_METER): gerçek bir saha
	105 m = 375 stud. Roblox karakteri ~5.5 stud olduğu için ölçek gerçekçi kalır.

	Top dışındaki hiçbir parça fizik motoruna bırakılmaz; hepsi Anchored.
]]

local Config = require(script.Parent.Parent.Config)
local Vec3 = require(script.Parent.Parent.Core.Vec3)
local PartRig = require(script.Parent.Parent.Anim.PartRig)
local Rig = require(script.Parent.Parent.Anim.Rig)

local SceneBuilder = {}

local S = Config.STUDS_PER_METER
local P = Config.PITCH
local LINE = 0.12 -- çizgi kalınlığı (metre)
local LINE_Y = 0.03 -- çim üstünden yükseklik (stud)

-- Lua 5.3: math.atan(y, x) | Luau: math.atan2(y, x)
local atan2 = math.atan2 or math.atan

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

-- Metre -> stud (yükseklik: y=0 çim yüzeyi)
local function v3(x, y, z)
	return Vector3.new(x * S, y * S, z * S)
end

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

-- Yay çizimi (orta yuvarlak / korner): küçük segmentlerden
local function drawArc(parent, name, cx, cz, radius, startAngle, endAngle, segments)
	segments = segments or 24
	for i = 1, segments do
		local a1 = startAngle + (endAngle - startAngle) * ((i - 1) / segments)
		local a2 = startAngle + (endAngle - startAngle) * (i / segments)
		local x1, z1 = cx + math.cos(a1) * radius, cz + math.sin(a1) * radius
		local x2, z2 = cx + math.cos(a2) * radius, cz + math.sin(a2) * radius
		local seg = drawLine(parent, name .. "_" .. tostring(i), x1, z1, x2, z2)
		local mid = Vector3.new((x1 + x2) / 2 * S, LINE_Y, (z1 + z2) / 2 * S)
		local len = math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2) * S
		local angle = atan2(z2 - z1, x2 - x1)
		seg.CFrame = CFrame.new(mid) * CFrame.Angles(0, -angle, 0)
		seg.Size = Vector3.new(math.max(len, LINE * S), 0.04, LINE * S)
	end
end

local function buildSurface(root, opts)
	local folder = Instance.new("Folder")
	folder.Name = "Surface"
	folder.Parent = root

	-- Yarım sahada çim x ∈ [0, halfLength]; tam sahada [-halfLength, halfLength]
	local x0 = opts.half and 0 or -P.halfLength
	local x1 = P.halfLength
	local width = x1 - x0
	local centerX = (x0 + x1) / 2

	local grass = makePart(
		folder,
		"Grass",
		Vector3.new(width * S, 2, P.width * S),
		CFrame.new(centerX * S, -0.98, 0), -- üst yüz y=0.02: varsayılan Baseplate ile z-fighting olmaz
		Color3.fromRGB(38, 104, 56),
		Enum.Material.Grass,
		{ collide = true }
	)
	grass.CastShadow = false

	local stripes = opts.half and 6 or 10
	for i = 0, stripes - 1 do
		local w = width / stripes
		local x = x0 + w * (i + 0.5)
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

local function buildLines(root, opts)
	local folder = Instance.new("Folder")
	folder.Name = "Lines"
	folder.Parent = root

	local HL, HW = P.halfLength, P.halfWidth
	local x0 = opts.half and 0 or -HL

	-- Yan çizgiler
	drawLine(folder, "TouchlineNorth", x0, -HW, HL, -HW)
	drawLine(folder, "TouchlineSouth", x0, HW, HL, HW)
	-- Kale çizgisi (hücum edilen kale)
	drawLine(folder, "GoalLineEast", HL, -HW, HL, HW)
	-- Orta çizgi / arka çizgi
	if opts.half then
		drawLine(folder, "HalfwayLine", 0, -HW, 0, HW)
	else
		drawLine(folder, "GoalLineWest", -HL, -HW, -HL, HW)
		drawLine(folder, "HalfwayLine", 0, -HW, 0, HW)
	end

	-- Orta yuvarlak: yarım sahada yalnızca saha içindeki yay
	if opts.half then
		drawArc(folder, "CenterCircle", 0, 0, P.centerCircleRadius, -math.pi / 2, math.pi / 2, 24)
	else
		drawArc(folder, "CenterCircle", 0, 0, P.centerCircleRadius, 0, math.pi * 2, 40)
	end
	makePart(
		folder,
		"CenterSpot",
		Vector3.new(0.24 * S, 0.05, 0.24 * S),
		CFrame.new(v3(0, LINE_Y / S, 0)),
		Color3.fromRGB(246, 250, 252),
		nil,
		{ shape = Enum.PartType.Cylinder, castShadow = false }
	)

	-- Ceza sahası / kale sahası / penaltı noktası
	local sides = opts.half and { 1 } or { -1, 1 }
	for _, side in ipairs(sides) do
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

local function buildGoal(parent, side)
	local frameColor = Color3.fromRGB(248, 250, 252)
	local postDia = P.postRadius * 2
	local barDia = P.crossbarRadius * 2
	local gl = side * P.halfLength
	local tag = side > 0 and "East" or "West"

	local goalFolder = Instance.new("Folder")
	goalFolder.Name = "Goal" .. tag
	goalFolder.Parent = parent

	-- Yan direkler (silindir ekseni X'tir; dikey yapmak için Z'de 90°)
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

	-- Üst direk (ekseni Z'ye çevir)
	makePart(
		goalFolder,
		"Crossbar",
		Vector3.new(P.goalHalfWidth * 2 * S, barDia * S, barDia * S),
		CFrame.new(v3(gl, P.goalHeight, 0)) * CFrame.Angles(0, math.rad(90), 0),
		frameColor,
		Enum.Material.Metal,
		{ shape = Enum.PartType.Cylinder }
	)

	-- Ağ: arka, iki yan, üst
	local netColor = Color3.fromRGB(230, 238, 244)
	local netOpts = { transparency = 0.45, castShadow = false }
	local backX = gl + side * P.goalDepth

	local backNet = makePart(
		goalFolder,
		"NetBack",
		Vector3.new(0.05 * S, P.goalHeight * S, P.goalHalfWidth * 2 * S),
		CFrame.new(backX * S, (P.goalHeight / 2) * S, 0),
		netColor,
		Enum.Material.Fabric,
		netOpts
	)

	for _, sz in ipairs({ -1, 1 }) do
		makePart(
			goalFolder,
			"NetSide",
			Vector3.new(P.goalDepth * S, P.goalHeight * S, 0.05 * S),
			CFrame.new(((gl + backX) / 2) * S, (P.goalHeight / 2) * S, sz * P.goalHalfWidth * S),
			netColor,
			Enum.Material.Fabric,
			netOpts
		)
	end

	makePart(
		goalFolder,
		"NetTop",
		Vector3.new(P.goalDepth * S, 0.05 * S, P.goalHalfWidth * 2 * S),
		CFrame.new(((gl + backX) / 2) * S, P.goalHeight * S, 0),
		netColor,
		Enum.Material.Fabric,
		netOpts
	)

	return goalFolder, backNet, backX
end

local function buildBall()
	local ball = makePart(
		workspace,
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

--[[ Kaleci görseli: TAMAMEN prosedürel iskelet (13 parça + 2 eldiven).
	Hiçbir model/animasyon asset'i yok; parçalar sunucuda FK ile pozlanır.
	Kaleci sahaya dönük durur: ileri = -side * x̂. ]]
local function keeperYaw(side)
	-- forward = (-side, 0, 0) -> yaw = atan2(fz, fx)
	return atan2(0, -side)
end

local function buildKeeper(root, side)
	local K = Config.KEEPER
	local folder = Instance.new("Folder")
	folder.Name = "Goalkeeper"
	folder.Parent = root

	local model = PartRig.build(folder, { name = "Rig", studsPerMeter = S })
	local x = side * (P.halfLength - K.lineOffset)
	model.x = x
	model.side = side
	model.yaw = keeperYaw(side)
	PartRig.apply(model, nil, Vec3.new(x * S, 0, 0), model.yaw, S)
	return model
end

--[[ Şutçu NPC'si: kaleci ile aynı prosedürel iskelet, farklı forma rengi. ]]
local function buildStriker(root, side, startPos)
	local folder = Instance.new("Folder")
	folder.Name = "Striker"
	folder.Parent = root

	local model = PartRig.build(folder, {
		name = "Rig",
		studsPerMeter = S,
		kitColor = Color3.fromRGB(228, 68, 82),
	})
	model.side = side
	model.pos = startPos
	PartRig.apply(model, nil, Vec3.new(startPos.x * S, 0, startPos.z * S), 0, S)
	return model
end

local function setupLighting()
	local Lighting = game:GetService("Lighting")
	pcall(function()
		Lighting.ClockTime = 15.5
		Lighting.Brightness = 2.3
		Lighting.Ambient = Color3.fromRGB(72, 82, 92)
		Lighting.OutdoorAmbient = Color3.fromRGB(126, 136, 146)
		Lighting.EnvironmentDiffuseScale = 0.45
		Lighting.EnvironmentSpecularScale = 0.3
		Lighting.GlobalShadows = true
		Lighting.ExposureCompensation = 0.1
	end)

	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atm = Instance.new("Atmosphere")
		atm.Density = 0.32
		atm.Haze = 1.1
		atm.Glare = 0.1
		atm.Color = Color3.fromRGB(199, 212, 224)
		atm.Parent = Lighting
	end
end

local function buildSpawn(root, x)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PitchSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(x * S, 0.5, 0)
	spawn.Color = Color3.fromRGB(60, 120, 200)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = root
	return spawn
end

--[[ Sahneyi kurar. opts = { half = true } -> yarım saha, tek kale (Adım 3).
	Dönüş: { root, ball, keeper, backNet, ballStart, half, goalSide } ]]
function SceneBuilder.build(opts)
	opts = opts or {}
	local half = opts.half ~= false
	local goalSide = opts.goalSide or 1

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

	buildSurface(root, { half = half })

	buildLines(root, { half = half })

	local goalsFolder = Instance.new("Folder")
	goalsFolder.Name = "Goals"
	goalsFolder.Parent = root

	local backNet, backX
	local _, netPart, netX = buildGoal(goalsFolder, goalSide)
	backNet, backX = netPart, netX

	if not half then
		buildGoal(goalsFolder, -goalSide)
	end

	local ball = buildBall()
	local keeper = buildKeeper(root, goalSide)

	local ballStart = half and Vector3.new((P.halfLength * 0.40) * S, Config.BALL.radius * S, 0)
		or Vector3.new(0, Config.BALL.radius * S, 0)
	local strikerStart = Vec3.new(ballStart.X / S - 1.45, 0, 0.75)
	local striker = buildStriker(root, goalSide, strikerStart)
	setupLighting()

	-- Doğma noktası: yarım sahada topun gerisinde (animasyonlar görüş alanında)
	local spawnX = half and (P.halfLength * 0.18) or 0
	buildSpawn(root, spawnX)

	ball.CFrame = CFrame.new(ballStart)

	return {
		root = root,
		ball = ball,
		keeper = keeper,
		striker = striker,
		strikerStart = strikerStart,
		backNet = backNet,
		backX = backX,
		ballStart = ballStart,
		half = half,
		goalSide = goalSide,
	}
end

-- Topu başlangıç noktasına alır
function SceneBuilder.resetBallPosition(positionStuds)
	local ball = workspace:FindFirstChild("MatchBall")
	if ball then
		ball.CFrame = CFrame.new(positionStuds or Vector3.new(0, Config.BALL.radius * S, 0))
	end
end

--[[ Kaleci modelini poza göre konumlandırır (sunucu her karede çağırır).
	pose: KeeperAnim:sample(t) çıktısı (veya nil = duruş)
	pos : kaleci AI'sinin konumu (METRE, Vec3) ]]
function SceneBuilder.updateKeeperModel(keeperModel, pose, pos, studsPerMeter)
	if not keeperModel then
		return
	end
	local s = studsPerMeter or S
	local side = keeperModel.side or 1
	local origin = Vec3.new(pos.x * s, 0, pos.z * s)
	return PartRig.apply(keeperModel, pose, origin, keeperYaw(side), s)
end

--[[ Şutçu modelini poza göre konumlandırır. pos: metre Vec3, yaw: baktığı yön ]]
function SceneBuilder.updateStrikerModel(strikerModel, pose, pos, yaw, studsPerMeter)
	if not strikerModel then
		return
	end
	local s = studsPerMeter or S
	local origin = Vec3.new(pos.x * s, 0, pos.z * s)
	return PartRig.apply(strikerModel, pose, origin, yaw, s)
end

--[[ Kaleci görselinin dünya uzayındaki el noktaları (hata ayıklama/teşhis). ]]
function SceneBuilder.keeperHands(keeperModel, pose, pos, studsPerMeter)
	if not keeperModel then
		return nil
	end
	local s = studsPerMeter or S
	local solved = SceneBuilder.updateKeeperModel(keeperModel, pose, pos, s)
	local out = {}
	for _, side in ipairs({ "L", "R" }) do
		local hand, forward, right, up = Rig.toWorld(solved.pos["hand" .. side], Vec3.new(pos.x * s, 0, pos.z * s), keeperYaw(keeperModel.side or 1), s)
		out[side] = hand
	end
	return out
end

return SceneBuilder
