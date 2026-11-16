--[[
	BallView — istemci görselleştirme (Adım 2).

	Sunucu topun gerçek konumunu ~ağ hızında gönderir (Roblox anchored parça
	replikasyonu). Bu script:

	  1) Sunucudan gelen topu lokal olarak gizler,
	  2) Kendi yumuşatılmış kopyasını çizer (60-144 FPS akıcılık),
	  3) İz (Trail) efekti ekler,
	  4) Yayın kamerasını topa doğru kaydırır,
	  5) SPACE ile şut isteği gönderir.

	Neden sunucu topunu gizliyoruz? Replikasyon 20-30 Hz gelir; 27 m/s'lik bir şut
	bu hızda 1.3 m sıçrayarak görünür. İstemci, hedefe üstel yaklaşma + hız tahmini
	ile aradaki hareketi doldurur. (Adım 7'de gerçek gecikme telafisi + prediction.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Yapılandırma (sunucudaki ile aynı olmalı; Config modülünde tutuluyor)
local Config
do
	local Shared = ReplicatedStorage:WaitForChild("Shared", 20)
	if Shared then
		local ok, mod = pcall(require, Shared:WaitForChild("Config", 10))
		if ok and mod then
			Config = mod
		end
	end
end
local S = Config and Config.STUDS_PER_METER or 3.5714
local R = Config and Config.BALL.radius or 0.11

local serverBall = Workspace:WaitForChild("MatchBall", 30)
if not serverBall then
	return
end
serverBall.LocalTransparencyModifier = 1

-- Lokal görsel top
local visual = serverBall:Clone()
visual.Name = "MatchBallVisual"
visual.Anchored = true
visual.CanCollide = false
visual.CanQuery = false
visual.LocalTransparencyModifier = 0
visual.Transparency = 0
visual.Parent = Workspace

-- İz efekti
local trail = Instance.new("Trail")
trail.Attachment0 = Instance.new("Attachment")
trail.Attachment1 = Instance.new("Attachment")
trail.Attachment0.Parent = visual
trail.Attachment1.Parent = visual
trail.Attachment1.Position = Vector3.new(0.05, 0, 0)
trail.Lifetime = 0.35
trail.MinLength = 0
trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
trail.Color = ColorSequence.new(Color3.fromRGB(180, 230, 255))
trail.Enabled = true
trail.Parent = visual

-- Kamera: yüksek yayın açısı, topa doğru yumuşak takip
if camera then
	camera.CameraType = Enum.CameraType.Scriptable
end

local renderPos = serverBall.Position
local lastTarget = serverBall.Position
local velocity = Vector3.zero
local camPos = Vector3.new(0, 320, 420)
local camLook = Vector3.zero
local camInit = false

local function onFrame(dt)
	local target = serverBall.Position

	-- Üstel yumuşatma + hız tahmini (replikasyon aralığını doldurur)
	local k = 1 - math.exp(-14 * dt)
	velocity = velocity:Lerp((target - lastTarget) / math.max(dt, 1e-3), 1 - math.exp(-6 * dt))
	lastTarget = target

	local predicted = target + velocity * 0.035
	renderPos = renderPos:Lerp(predicted, k)
	visual.CFrame = CFrame.new(renderPos)

	-- Kamera takibi
	if camera then
		local desiredPos = Vector3.new(renderPos.X * 0.22, 300, 400)
		local desiredLook = Vector3.new(renderPos.X * 0.55, renderPos.Y, renderPos.Z * 0.6)
		if not camInit then
			camPos = desiredPos
			camLook = desiredLook
			camInit = true
		else
			local ck = 1 - math.exp(-3.2 * dt)
			camPos = camPos:Lerp(desiredPos, ck)
			camLook = camLook:Lerp(desiredLook, ck)
		end
		camera.CFrame = CFrame.lookAt(camPos, camLook)
		camera.CameraType = Enum.CameraType.Scriptable
	end
end

RunService.RenderStepped:Connect(onFrame)

-- SPACE: şut isteği
local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
local kickRemote = remotes and remotes:WaitForChild("Kick", 10)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Space and kickRemote then
		kickRemote:FireServer()
	end
end)

-- Basit HUD
local gui = Instance.new("ScreenGui")
gui.Name = "FootballHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -24)
hint.Size = UDim2.new(0, 460, 0, 34)
hint.BackgroundColor3 = Color3.fromRGB(10, 16, 20)
hint.BackgroundTransparency = 0.25
hint.BorderSizePixel = 0
hint.TextColor3 = Color3.fromRGB(232, 240, 246)
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 15
hint.Text = "SPACE — şut çek   ·   top fiziği: 240 Hz, kendi motorumuz"
hint.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = hint
