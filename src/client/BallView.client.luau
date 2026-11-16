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
local R = Config and Config.BALL.radius or 0.11
local PITCH = Config and Config.PITCH
local HALF_LENGTH = PITCH and PITCH.halfLength or 52.5
local GOAL_PLANE = HALF_LENGTH * S
local CHARGE_TIME = (Config and Config.BALL_CONTROL and Config.BALL_CONTROL.chargeTime) or 0.9

-- ---------------------------------------------------------------- karakter
local character, hrp
local function bindCharacter(char)
	character = char
	hrp = char:WaitForChild("HumanoidRootPart", 10)
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

local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -26)
hint.Size = UDim2.new(0, 560, 0, 34)
hint.BackgroundColor3 = Color3.fromRGB(10, 16, 20)
hint.BackgroundTransparency = 0.25
hint.BorderSizePixel = 0
hint.TextColor3 = Color3.fromRGB(232, 240, 246)
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 15
hint.Text = "SPACE basılı tut → güç  ·  bırak → şut   |   R → topu sıfırla"
hint.Parent = gui

local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 8)
hintCorner.Parent = hint

-- Güç barı
local barBack = Instance.new("Frame")
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
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(61, 220, 132)
barFill.BorderSizePixel = 0
barFill.Parent = barBack

local barFillCorner = Instance.new("UICorner")
barFillCorner.CornerRadius = UDim.new(0, 7)
barFillCorner.Parent = barFill

-- Skor / duyuru
local scoreLabel = Instance.new("TextLabel")
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
			payload.kicks or 0
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

local function computeAim()
	local origin = camera.CFrame.Position
	local dir = camera.CFrame.LookVector
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

local function fireKick()
	if not kickRemote then
		return
	end
	local aim = computeAim()
	if not aim then
		return
	end
	kickRemote:FireServer(charge, aim.Z / S, aim.Y / S)
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
	end
end)

UserInputService.InputEnded:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.Space and charging then
		charging = false
		barBack.Visible = false
		fireKick()
		charge = 0
		barFill.Size = UDim2.new(0, 0, 1, 0)
	end
end)

-- ------------------------------------------------------------- kare döngüsü
local renderPos = serverBall.Position
local lastTarget = serverBall.Position
local ballVel = Vector3.zero
local camPos = Vector3.new(-90, 60, 25)
local camLook = Vector3.zero
local camInit = false
local stats = { goals = 0, saves = 0, kicks = 0 }

local function onFrame(dt)
	-- Top: sunucu konumunu yumuşat + hız tahmini
	local target = serverBall.Position
	local k = 1 - math.exp(-16 * dt)
	ballVel = ballVel:Lerp((target - lastTarget) / math.max(dt, 1e-3), 1 - math.exp(-7 * dt))
	lastTarget = target
	local predicted = target + ballVel * 0.03
	renderPos = renderPos:Lerp(predicted, k)
	visual.CFrame = CFrame.new(renderPos)

	-- Kamera: karakterin arkasında, kaleye bakacak şekilde
	if camera then
		local focus = renderPos
		if hrp and hrp.Parent then
			focus = hrp.Position
		end
		local desiredPos = focus + Vector3.new(-30, 20, 9)
		local desiredLook = focus + Vector3.new(34, -3, 0)
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
