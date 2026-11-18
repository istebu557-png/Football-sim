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

-- Kardeş adları BENZERSİZ olmalı. Roblox'ta aynı ada sahip iki çocuk yasaldir ama
-- `FindFirstChild("PenaltyAreaSide")` hangisini döndürdüğü belirsizdir ve Studio
-- ağacı okunmaz olur. Çizgilerde simetrik çiftler (kuzey/güney ceza sahası kenarı,
-- iki kale tarafı) aynı mantıksal adı paylaşır; çakışmaya sayaç eklenir.
-- build() eski FootballPitch'i yok ettiği için adlar her kurulumda deterministiktir.
local function uniqueName(parent, name)
	if parent == nil then
		return name
	end
	if parent:FindFirstChild(name) == nil then
		return name
	end
	local suffix = 2
	while parent:FindFirstChild(name .. tostring(suffix)) ~= nil do
		suffix = suffix + 1
	end
	return name .. tostring(suffix)
end

local function makePart(parent, name, sizeStuds, cframe, color, material, opts)
	local p = Instance.new("Part")
	p.Name = uniqueName(parent, name)
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
		Color3.fromRGB(42, 112, 60),
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
			-- Biçim şeritleri uzaktan da seçilsin diye kontrastlı (eski fark %4'tü,
			-- ekran görüntüsünde çim tek düz bir yeşil gibi görünüyordu)
			i % 2 == 0 and Color3.fromRGB(56, 138, 74) or Color3.fromRGB(38, 104, 56),
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
	-- Tam sahada iki taraf da aynı çizgileri çizer; ada taraf etiketi (East/West)
	-- ve simetri etiketi (North/South) eklenir ki hiçbir kardeş adı çakışmasın.
	for _, side in ipairs(sides) do
		local gl = side * HL
		local paX = gl - side * P.penaltyAreaLength
		local gaX = gl - side * P.goalAreaLength
		local sideTag = side > 0 and "East" or "West"

		drawLine(folder, "PenaltyAreaLine" .. sideTag, paX, -P.penaltyAreaHalfWidth, paX, P.penaltyAreaHalfWidth)
		drawLine(folder, "PenaltyAreaSide" .. sideTag .. "North", gl, -P.penaltyAreaHalfWidth, paX, -P.penaltyAreaHalfWidth)
		drawLine(folder, "PenaltyAreaSide" .. sideTag .. "South", gl, P.penaltyAreaHalfWidth, paX, P.penaltyAreaHalfWidth)

		drawLine(folder, "GoalAreaLine" .. sideTag, gaX, -P.goalAreaHalfWidth, gaX, P.goalAreaHalfWidth)
		drawLine(folder, "GoalAreaSide" .. sideTag .. "North", gl, -P.goalAreaHalfWidth, gaX, -P.goalAreaHalfWidth)
		drawLine(folder, "GoalAreaSide" .. sideTag .. "South", gl, P.goalAreaHalfWidth, gaX, P.goalAreaHalfWidth)

		-- Ceza yayı ("D"): penaltı noktası merkezli 9.15 m, yalnızca ceza sahası
		-- çizgisinin DIŞINDA kalan kavıs (gerçek saha işareti)
		local arcPhi = math.acos(5.5 / 9.15)
		local arcMid = side > 0 and math.pi or 0
		drawArc(folder, "PenaltyArc" .. sideTag, gl - side * P.penaltySpot, 0, 9.15,
			arcMid - arcPhi, arcMid + arcPhi, 14)

		makePart(
			folder,
			"PenaltySpot" .. sideTag,
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
	-- Adlar bilerek Kuzey/Güney: iki direk aynı mantıksal parçanın simetriği, ama
	-- aynı Name ile FindFirstChild belirsizleşirdi (bkz. uniqueName).
	for _, sz in ipairs({ -1, 1 }) do
		makePart(
			goalFolder,
			"Post" .. (sz < 0 and "North" or "South"),
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
			"NetSide" .. (sz < 0 and "North" or "South"),
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

	-- Turuncu forma: yeşil sahada kaleci ilk bakışta seçilsin (beyaz/gri kayboluyordu)
	local model = PartRig.build(folder, {
		name = "Rig",
		studsPerMeter = S,
		kitColor = Color3.fromRGB(255, 152, 28),
	})
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

-- Stadyum hissi: apron + tribün + reklam panosu + köşe flamaları + ışık kuleleri.
-- Hepsi prosedürel (asset yok); parça adları sayaçla benzersizleşir.
local BOARD_COLORS = {
	Color3.fromRGB(24, 58, 138),
	Color3.fromRGB(238, 242, 246),
	Color3.fromRGB(168, 32, 44),
	Color3.fromRGB(16, 104, 96),
}
local SEAT_COLORS = {
	Color3.fromRGB(132, 30, 38),
	Color3.fromRGB(30, 44, 74),
}

local function buildStand(parent, name, cx, cz, lengthStuds, alongZ, sideSign)
	-- 4 kademeli tribün + arka duvar + çatı bandı
	local concrete = Color3.fromRGB(92, 96, 104)
	for i = 1, 4 do
		local rise = i * 1.15
		local off = (3.2 + i * 1.5) * sideSign
		local size = alongZ
			and Vector3.new(6 * S, 1.15, lengthStuds)
			or Vector3.new(lengthStuds, 1.15, 6 * S)
		local px = alongZ and cx + off or cx
		local pz = alongZ and cz or cz + off
		makePart(
			parent,
			name .. "Tier" .. tostring(i),
			size,
			CFrame.new(px, rise * S * 0.5 - 0.5, pz),
			i % 2 == 1 and SEAT_COLORS[1] or SEAT_COLORS[2],
			Enum.Material.SmoothPlastic,
			{ castShadow = false }
		)
	end
	-- Arka duvar ve çatı: silüet tribünü stadyum gibi gösterir
	local wallOff = (3.2 + 5 * 1.5) * sideSign
	local wallSize = alongZ and Vector3.new(1.2 * S, 7.5 * S, lengthStuds) or Vector3.new(lengthStuds, 7.5 * S, 1.2 * S)
	makePart(
		parent,
		name .. "Wall",
		wallSize,
		CFrame.new(alongZ and cx + wallOff or cx, 3.2 * S, alongZ and cz or cz + wallOff),
		concrete,
		Enum.Material.Concrete,
		{ castShadow = false }
	)
	makePart(
		parent,
		name .. "Roof",
		alongZ and Vector3.new(8.5 * S, 0.35, lengthStuds) or Vector3.new(lengthStuds, 0.35, 8.5 * S),
		CFrame.new(alongZ and cx + wallOff * 0.7 or cx, 6.6 * S, alongZ and cz or cz + wallOff * 0.7),
		Color3.fromRGB(226, 230, 236),
		Enum.Material.Metal,
		{ castShadow = false }
	)
end

local function buildSurround(root, opts)
	local folder = Instance.new("Folder")
	folder.Name = "Surround"
	folder.Parent = root

	local HL, HW = P.halfLength, P.halfWidth
	local x0 = opts.half and 0 or -HL
	local lenX = HL - x0
	local cx = (x0 + HL) / 2

	-- Apron: sahanın dışındaki gri boşluğu kapatır (ekrandaki "hiçlik" hissi)
	makePart(
		folder,
		"Apron",
		Vector3.new((lenX + 90) * S, 1.6, (P.width + 90) * S),
		CFrame.new(cx * S, -1.05, 0),
		Color3.fromRGB(30, 62, 40),
		Enum.Material.Grass,
		{ collide = false, castShadow = false }
	)
	makePart(
		folder,
		"Concourse",
		Vector3.new((lenX + 46) * S, 1.2, (P.width + 46) * S),
		CFrame.new(cx * S, -0.62, 0),
		Color3.fromRGB(74, 78, 86),
		Enum.Material.Concrete,
		{ collide = false, castShadow = false }
	)

	-- Tribünler: kuzey/güney kenarları + kale arkası
	buildStand(folder, "StandNorth", cx * S, -(HW + 12) * S, (lenX + 24) * S, false, -1)
	buildStand(folder, "StandSouth", cx * S, (HW + 12) * S, (lenX + 24) * S, false, 1)
	buildStand(folder, "StandEast", (HL + 14) * S, 0, (P.width + 24) * S, true, 1)
	if not opts.half then
		buildStand(folder, "StandWest", (-HL - 14) * S, 0, (P.width + 24) * S, true, -1)
	end

	-- Reklam panoları: saha çevresinde renkli bant (ölçek hissi verir)
	local boardIndex = 0
	local function board(name, cxm, czm, sxm, szm, rotY)
		boardIndex = boardIndex + 1
		local color = BOARD_COLORS[(boardIndex % #BOARD_COLORS) + 1]
		makePart(
			folder,
			name .. tostring(boardIndex),
			Vector3.new(sxm * S, 0.95, szm * S),
			CFrame.new(cxm * S, 0.5, czm * S) * CFrame.Angles(0, rotY or 0, 0),
			color,
			Enum.Material.SmoothPlastic,
			{ castShadow = false }
		)
	end
	local longBoards = 10
	for i = 1, longBoards do
		local bx = x0 + lenX * ((i - 0.5) / longBoards)
		board("AdBoardTouchN", bx, -(HW + 2.2), lenX / longBoards - 0.4, 0.14, 0)
		board("AdBoardTouchS", bx, HW + 2.2, lenX / longBoards - 0.4, 0.14, 0)
	end
	local endBoards = 8
	for i = 1, endBoards do
		local bz = -HW + P.width * ((i - 0.5) / endBoards)
		board("AdBoardEast", HL + 2.6, bz, 0.14, P.width / endBoards - 0.4, 0)
		if not opts.half then
			board("AdBoardWest", -HL - 2.6, bz, 0.14, P.width / endBoards - 0.4, 0)
		else
			board("AdBoardWest", x0 - 2.6, bz, 0.14, P.width / endBoards - 0.4, 0)
		end
	end

	-- Köşe flamaları (yarım sahada 4 köşe)
	local corners = {
		{ x = x0, z = -HW, tag = "NW" },
		{ x = x0, z = HW, tag = "SW" },
		{ x = HL, z = -HW, tag = "NE" },
		{ x = HL, z = HW, tag = "SE" },
	}
	if not opts.half then
		corners[#corners + 1] = { x = -HL, z = -HW, tag = "WN" }
		corners[#corners + 1] = { x = -HL, z = HW, tag = "WS" }
	end
	for _, c in ipairs(corners) do
		makePart(
			folder,
			"FlagPole" .. c.tag,
			Vector3.new(0.06 * S, 1.5, 0.06 * S),
			CFrame.new(c.x * S, 0.75 * S, c.z * S),
			Color3.fromRGB(244, 246, 250),
			Enum.Material.SmoothPlastic,
			{ castShadow = false }
		)
		makePart(
			folder,
			"Flag" .. c.tag,
			Vector3.new(0.42, 0.3, 0.03),
			CFrame.new(c.x * S + 0.21, 1.35 * S, c.z * S),
			Color3.fromRGB(255, 214, 64),
			Enum.Material.Neon,
			{ castShadow = false }
		)
	end

	-- Işık kuleleri: gökyüzüne silüet verir, gece modunda sahneyi taşır
	local pylons = {
		{ x = x0 - 8, z = -(HW + 9), tag = "NW" },
		{ x = x0 - 8, z = HW + 9, tag = "SW" },
		{ x = HL + 9, z = -(HW + 9), tag = "NE" },
		{ x = HL + 9, z = HW + 9, tag = "SE" },
	}
	for _, py in ipairs(pylons) do
		makePart(
			folder,
			"LightPole" .. py.tag,
			Vector3.new(0.9, 16 * S, 0.9),
			CFrame.new(py.x * S, 8 * S, py.z * S),
			Color3.fromRGB(58, 62, 70),
			Enum.Material.Metal,
			{ castShadow = false }
		)
		makePart(
			folder,
			"LightHead" .. py.tag,
			Vector3.new(4.5 * S, 2.2 * S, 0.5),
			CFrame.new(py.x * S, 16.4 * S, py.z * S) * CFrame.Angles(0, 0, 0),
			Color3.fromRGB(255, 246, 214),
			Enum.Material.Neon,
			{ castShadow = false }
		)
	end

	return folder
end

local function setupLighting()
	local Lighting = game:GetService("Lighting")
	pcall(function()
		-- Altın saat: çim doygun, gölgeler uzun, ufuk sıcak (15.5 düz öğle ışığı
		-- ekran görüntüsünde soluk ve gri duruyordu)
		Lighting.ClockTime = 16.8
		Lighting.Brightness = 2.6
		Lighting.Ambient = Color3.fromRGB(84, 86, 92)
		Lighting.OutdoorAmbient = Color3.fromRGB(142, 148, 156)
		Lighting.EnvironmentDiffuseScale = 0.55
		Lighting.EnvironmentSpecularScale = 0.35
		Lighting.GlobalShadows = true
		Lighting.ExposureCompensation = 0.15
		Lighting.FogEnd = 900
		Lighting.FogColor = Color3.fromRGB(186, 199, 212)
	end)

	-- Gökyüzü: varsayılan gri ufuk yerine bulutlu mavi (Sky yoksa stüdyo boşluğu görünür)
	if not Lighting:FindFirstChildOfClass("Sky") then
		local sky = Instance.new("Sky")
		sky.Name = "StadiumSky"
		sky.Parent = Lighting
	end

	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atm = Instance.new("Atmosphere")
		atm.Density = 0.32
		atm.Haze = 1.1
		atm.Glare = 0.1
		atm.Color = Color3.fromRGB(199, 212, 224)
		atm.Parent = Lighting
	end

	-- Hafif sunum efektleri: güneş ışınları + bloom + doygunluk
	if not Lighting:FindFirstChildOfClass("SunRaysEffect") then
		local rays = Instance.new("SunRaysEffect")
		rays.Intensity = 0.32
		rays.Spread = 0.7
		rays.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.35
		bloom.Size = 24
		bloom.Threshold = 2.2
		bloom.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("ColorCorrectionEffect") then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Saturation = 0.18
		cc.Contrast = 0.06
		cc.Brightness = 0.02
		cc.Parent = Lighting
	end
end

local function buildSpawn(root, x)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PitchSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	-- Oyuncu sahaya sırtı dönük doğmasın: -Z öne baktığı için -90° yaw ile +X'e
	-- (kaleye) çeviriyoruz; ilk karede top ve kale kadrajda olur.
	spawn.CFrame = CFrame.new(x * S, 0.5, 0) * CFrame.Angles(0, -math.rad(90), 0)
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

	buildSurround(root, { half = half })

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
	-- Şutçu NPC kapalıysa sahaya MANKEN koymuyoruz: donuk duran bir oyuncu
	-- "oynayan biri var" hissi verip kafa karıştırır. Sahada şutu atan sizsiniz.
	local striker = nil
	if Config.ANIM.strikerEnabled then
		striker = buildStriker(root, goalSide, strikerStart)
	end
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
-- NOT: Burada daha önce `SceneBuilder.keeperHands` vardı: eldiven dünya
-- konumlarını döndürüyordu ama HİÇBİR yerden çağrılmıyordu ve her çağrıda tüm
-- kaleci pozunu yeniden çözüyordu (updateKeeperModel zaten aynı işi yapıyor ve
-- eldivenleri yerleştiriyor). Ölü dışa aktarım olarak kaldırıldı; eldiven
-- konumları PartRig + updateKeeperModel üzerinden tek yoldan gelir.

return SceneBuilder
