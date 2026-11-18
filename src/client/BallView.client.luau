--[[
	BallView — istemci (Adım 3): üçüncü şahıs kamera, nişan, güç barı, top görseli.

	  * Sunucu topunu lokal olarak gizler, yumuşatılmış kopyasını çizer
	    (replikasyon 20-30 Hz, top 27 m/s -> aradaki hareket doldurulur).
	  * Kamera karakterin arkasında, kaleye bakacak şekilde konumlanır.
	  * Ekranın ortasındaki ışın kale düzlemini keser -> nişan noktası.
	  * SPACE basılı tut = şut gücü, bırak = şut. Sunucu sadece isteği alır;
	    gücü/nişanı doğrular ve şutu kendi uygular.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
-- CurrentCamera, LocalScript çok erken çalışırsa nil olabilir; kare döngüsünde
-- tekrar denenir (aşağıda resolveCamera).
local camera = Workspace.CurrentCamera

-- Config (varsa gerçek değerler, yoksa makul varsayılanlar)
local Config
do
	local Shared = ReplicatedStorage:WaitForChild("Shared", 20)
	if Shared then
		local ok, mod = pcall(require, Shared:WaitForChild("Config", 10))
		if ok then
			Config = mod
		end
	end
end
local S = Config and Config.STUDS_PER_METER or 3.5714
local PITCH = Config and Config.PITCH
local HALF_LENGTH = PITCH and PITCH.halfLength or 52.5
local GOAL_PLANE = HALF_LENGTH * S
local CHARGE_TIME = (Config and Config.BALL_CONTROL and Config.BALL_CONTROL.chargeTime) or 0.9

-- ---------------------------------------------------------------- vuruş türü / ayak seçimi (profesyonel biomekanik)
local SHOT = Config and Config.SHOT or { types = { "instep" }, labels = { instep = "Düz ayak" } }
local shotTypes = SHOT.types or { "instep" }
local shotIndex = 1
local currentFoot = "R" -- "L" | "R"

local HINT_FORMAT = "SPACE basılı tut → güç  ·  bırak → şut   |   T → vuruş türü (%s)   |   F → ayak değiştir   |   V → izleme kipi   |   R → topu sıfırla"

-- ÖNEMLİ: `hint` etiketi aşağıda (HUD bölümünde) oluşturuluyor. Lua'da bir
-- local'in kapsamı bildiriminden SONRA başlar; bu yüzden `local hint` burada
-- bildirilmezse fonksiyonların içindeki `hint` GLOBAL sayılır ve T/F'ye
-- basıldığında "attempt to index a nil value (global 'hint')" hatası verir.
local hint

local function shotLabel()
	local st = shotTypes[shotIndex] or "instep"
	return (SHOT.labels and SHOT.labels[st] or st) .. "  |  ayak: " .. currentFoot
end

local function updateHint()
	if hint then
		hint.Text = string.format(HINT_FORMAT, shotLabel())
	end
end

local function cycleShotType()
	shotIndex = shotIndex % #shotTypes + 1
	updateHint()
end

local function toggleFoot()
	currentFoot = (currentFoot == "R") and "L" or "R"
	updateHint()
end

-- ---------------------------------------------------------------- karakter
local character, hrp
local humanoid

-- Zıplamayı aç/kapat. SPACE şut gücü için kullanıldığından karakterin
-- zıplamaması gerekir.
-- NOT: `Humanoid.Jump = false` zıplamayı KAPATMAZ; Jump yalnızca "şimdi zıpla"
-- isteğidir. Doğru API `SetStateEnabled(HumanoidStateType.Jumping, false)`.
local jumpConn
local function setJumpEnabled(enabled)
	if not humanoid then
		return
	end
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, enabled)
	end)
	if jumpConn then
		jumpConn:Disconnect()
		jumpConn = nil
	end
	if not enabled then
		-- Yedek: bir şekilde Jumping durumuna girerse hemen geri kalk
		jumpConn = humanoid.StateChanged:Connect(function(_, newState)
			if newState == Enum.HumanoidStateType.Jumping then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
	end
end

local function bindCharacter(char)
	character = char
	hrp = char:WaitForChild("HumanoidRootPart", 10)
	humanoid = char:WaitForChild("Humanoid", 10)
	setJumpEnabled(false)
end
if player.Character then
	bindCharacter(player.Character)
end
player.CharacterAdded:Connect(bindCharacter)

-- -------------------------------------------------------------------- top
local serverBall = Workspace:WaitForChild("MatchBall", 30)
if not serverBall then
	return
end
serverBall.LocalTransparencyModifier = 1

local visual = serverBall:Clone()
visual.Name = "MatchBallVisual"
visual.Anchored = true
visual.CanCollide = false
visual.CanQuery = false
visual.Transparency = 0
visual.LocalTransparencyModifier = 0
visual.Parent = Workspace

local trail = Instance.new("Trail")
trail.Attachment0 = Instance.new("Attachment")
trail.Attachment1 = Instance.new("Attachment")
trail.Attachment0.Parent = visual
trail.Attachment1.Parent = visual
trail.Attachment1.Position = Vector3.new(0.05, 0, 0)
trail.Lifetime = 0.3
trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
trail.Color = ColorSequence.new(Color3.fromRGB(180, 230, 255))
trail.Parent = visual

-- -------------------------------------------------------------- nişan işareti
local marker = Instance.new("Part")
marker.Name = "AimMarker"
marker.Shape = Enum.PartType.Cylinder
marker.Size = Vector3.new(0.12 * S, 0.55 * S, 0.55 * S)
marker.Anchored = true
marker.CanCollide = false
marker.CanQuery = false
marker.Material = Enum.Material.Neon
marker.Color = Color3.fromRGB(90, 255, 160)
marker.Transparency = 0.35
marker.Parent = Workspace

-- -------------------------------------------------------------------- HUD
local gui = Instance.new("ScreenGui")
gui.Name = "FootballHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

-- `hint` yukarıda BİLDİRİLDİ (local hint), burada yalnızca ATANIR: yeni bir
-- `local` açarsak updateHint() eski (nil) upvalue'yu görmeye devam eder.
hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -26)
hint.Size = UDim2.new(0, 560, 0, 34)
hint.BackgroundColor3 = Color3.fromRGB(10, 16, 20)
hint.BackgroundTransparency = 0.25
hint.BorderSizePixel = 0
hint.TextColor3 = Color3.fromRGB(232, 240, 246)
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 15
updateHint()
hint.Parent = gui

local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 8)
hintCorner.Parent = hint

-- Güç barı
local barBack = Instance.new("Frame")
barBack.Name = "ChargeBar"
barBack.AnchorPoint = Vector2.new(0.5, 1)
barBack.Position = UDim2.new(0.5, 0, 1, -68)
barBack.Size = UDim2.new(0, 320, 0, 14)
barBack.BackgroundColor3 = Color3.fromRGB(24, 32, 40)
barBack.BorderSizePixel = 0
barBack.Visible = false
barBack.Parent = gui

local barBackCorner = Instance.new("UICorner")
barBackCorner.CornerRadius = UDim.new(0, 7)
barBackCorner.Parent = barBack

local barFill = Instance.new("Frame")
barFill.Name = "ChargeFill"
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(61, 220, 132)
barFill.BorderSizePixel = 0
barFill.Parent = barBack

local barFillCorner = Instance.new("UICorner")
barFillCorner.CornerRadius = UDim.new(0, 7)
barFillCorner.Parent = barFill

-- Skor / duyuru
local scoreLabel = Instance.new("TextLabel")
scoreLabel.Name = "Score"
scoreLabel.AnchorPoint = Vector2.new(0.5, 0)
scoreLabel.Position = UDim2.new(0.5, 0, 0, 14)
scoreLabel.Size = UDim2.new(0, 420, 0, 28)
scoreLabel.BackgroundTransparency = 1
scoreLabel.TextColor3 = Color3.fromRGB(240, 246, 250)
scoreLabel.Font = Enum.Font.GothamBold
scoreLabel.TextSize = 17
scoreLabel.Text = "GOL 0  ·  KURTARIŞ 0  ·  ŞUT 0"
scoreLabel.Parent = gui

-- ---------------------------------------------------------------- remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes", 25)
local kickRemote = remotes and remotes:WaitForChild("Kick", 10)
local resetRemote = remotes and remotes:WaitForChild("ResetBall", 10)
local stateRemote = remotes and remotes:WaitForChild("MatchState", 10)

if stateRemote then
	stateRemote.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		scoreLabel.Text = string.format(
			"GOL %d  ·  KURTARIŞ %d  ·  ŞUT %d",
			payload.goals or 0,
			payload.saves or 0,
			(payload.kicks or 0) + (payload.shots or 0)
		)
		if payload.event == "goal" then
			scoreLabel.TextColor3 = Color3.fromRGB(120, 255, 160)
		elseif payload.event == "save" then
			scoreLabel.TextColor3 = Color3.fromRGB(255, 210, 110)
		end
	end)
end

-- ------------------------------------------------------------ şut / nişan
local charging = false
local charge = 0
-- İzleme kipi (V): kamera topun arkasına geçip kaleyi çerçeveler.
-- Animasyonları (adaptif şut / kaleci dalışı) yakından izlemek için.
local spectator = false

-- Kamera Scriptable ve sabit bir konumda durduğu için (aşağıda updateCamera)
-- kameranın LookVector'ü oyuncunun baktığı yer DEĞİLDİR: nişan fareyle alınır.
-- Sıra: (1) fare ekran noktasından dünya ışını, (2) ışın kale düzlemini önden
-- kesmiyorsa kamera bakışı. Böylece gökyüzüne nişan alınca şut sessizce yutulmaz.
local function mouseRay(cam)
	local ok, loc = pcall(function()
		return UserInputService:GetMouseLocation()
	end)
	if not ok or not loc then
		return nil
	end
	local okRay, ray = pcall(function()
		return cam:ViewportPointToRay(loc.X, loc.Y)
	end)
	if not okRay or not ray or not ray.Direction then
		return nil
	end
	return ray
end

-- Bir ışını kale düzlemine (X = GOAL_PLANE) izdüşürür; önden kesmiyorsa nil.
local function projectToGoalPlane(origin, dir)
	if not origin or not dir then
		return nil
	end
	if dir.X <= 0.05 then
		return nil
	end
	local t = (GOAL_PLANE - origin.X) / dir.X
	if t <= 0 then
		return nil
	end
	local hit = origin + dir * t
	local z = math.clamp(hit.Z, -3.3 * S, 3.3 * S)
	local y = math.clamp(hit.Y, 0.25 * S, 2.3 * S)
	return Vector3.new(GOAL_PLANE, y, z)
end

local function computeAim()
	if not camera then
		return nil
	end
	local ray = mouseRay(camera)
	if ray then
		local aim = projectToGoalPlane(ray.Origin, ray.Direction)
		if aim then
			return aim
		end
	end
	return projectToGoalPlane(camera.CFrame.Position, camera.CFrame.LookVector)
end

local function fireKick()
	if not kickRemote then
		return
	end
	local aim = computeAim()
	if not aim then
		return
	end
	kickRemote:FireServer(charge, aim.Z / S, aim.Y / S, shotTypes[shotIndex] or "instep", currentFoot)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Space then
		charging = true
		charge = 0
		barBack.Visible = true
	elseif input.KeyCode == Enum.KeyCode.R and resetRemote then
		resetRemote:FireServer()
	elseif input.KeyCode == Enum.KeyCode.V then
		spectator = not spectator
	elseif input.KeyCode == Enum.KeyCode.T then
		cycleShotType()
	elseif input.KeyCode == Enum.KeyCode.F then
		toggleFoot()
	end
end)

-- BIRAKMA = ŞUT. Güç barı basılı tutarken dolar; tuş bırakıldığında şut
-- sunucuya gönderilir (sunucu gücü/nişanı doğrular, şutu kendi uygular).
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode ~= Enum.KeyCode.Space then
		return
	end
	if not charging then
		return
	end
	charging = false
	barBack.Visible = false
	barFill.Size = UDim2.new(0, 0, 1, 0)
	fireKick()
	charge = 0
end)

-- ------------------------------------------------------------- kare döngüsü
local renderPos = serverBall.Position
local lastTarget = serverBall.Position
local ballVel = Vector3.zero
local camPos = Vector3.new(-90, 60, 25)
local camLook = Vector3.zero
local camInit = false

-- CurrentCamera, LocalScript ilk karelerden önce hazır değilse nil kalabilir.
local function resolveCamera()
	if not camera then
		camera = Workspace.CurrentCamera
	end
	return camera
end

local function onFrame(dt)
	-- Top: sunucu konumunu yumuşat + hız tahmini
	local target = serverBall.Position
	local k = 1 - math.exp(-16 * dt)
	ballVel = ballVel:Lerp((target - lastTarget) / math.max(dt, 1e-3), 1 - math.exp(-7 * dt))
	lastTarget = target
	local predicted = target + ballVel * 0.03
	renderPos = renderPos:Lerp(predicted, k)
	visual.CFrame = CFrame.new(renderPos)

	-- Kamera: karakterin arkasında (ya da izleme kipinde topun arkasında)
	local cam = resolveCamera()
	if cam then
		camera = cam
		local focus = renderPos
		local desiredPos, desiredLook
		if spectator then
			-- Top neredeyse oraya yerleş, kaleyi çerçevele
			desiredPos = focus + Vector3.new(-26, 15, 7)
			desiredLook = Vector3.new(GOAL_PLANE, 1.2 * S, 0)
		else
			if hrp and hrp.Parent then
				focus = hrp.Position
			end
			desiredPos = focus + Vector3.new(-30, 20, 9)
			desiredLook = focus + Vector3.new(34, -3, 0)
		end
		if not camInit then
			camPos = desiredPos
			camLook = desiredLook
			camInit = true
		else
			local ck = 1 - math.exp(-6 * dt)
			camPos = camPos:Lerp(desiredPos, ck)
			camLook = camLook:Lerp(desiredLook, ck)
		end
		camera.CFrame = CFrame.lookAt(camPos, camLook)
		camera.CameraType = Enum.CameraType.Scriptable
	end

	-- Nişan işareti
	local aim = computeAim()
	if aim then
		marker.CFrame = CFrame.new(aim) * CFrame.Angles(0, 0, math.rad(90))
		marker.Transparency = charging and 0.15 or 0.45
		marker.Color = charging and Color3.fromRGB(255, 220, 90) or Color3.fromRGB(90, 255, 160)
	else
		marker.Transparency = 1
	end

	-- Güç barı
	if charging then
		charge = math.min(1, charge + dt / CHARGE_TIME)
		barFill.Size = UDim2.new(charge, 0, 1, 0)
		barFill.BackgroundColor3 = Color3.fromRGB(
			61 + math.floor(194 * charge),
			220 - math.floor(120 * charge),
			132 - math.floor(60 * charge)
		)
	end
end

RunService.RenderStepped:Connect(onFrame)
