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
local ANIM_CFG = (Config and Config.ANIM) or {}
-- Config.ANIM.poseHumanoid = false -> prosedürel pozu tamamen kapat, Roblox'un
-- varsayılan animasyonlarına dön (kaçış kapağı; sunucu da aynı bayrağı okur).
local POSE_HUMANOID = ANIM_CFG.poseHumanoid ~= false

local BC = (Config and Config.BALL_CONTROL) or {}
local KICK_REACH = BC.kickReach or 2.0
-- Sunucuyla AYNI kural: top sürerken dokunuş topu öne ittiği için şut menzili
-- "sahiplik" bandına kadar geniştir; o bandın dışında da istek tampona alınır.
-- İstemci dar eşiği (kickReach) kullandığında oyuncu sürüşte yanlış uyarı görür.
local POSSESSION_REACH = BC.possessionReach or 3.2
local BUFFER_REACH = BC.shotBufferReach or 6.0

-- ---------------------------------------------------------------- prosedürel oyuncu animasyonu
-- Asset yok: karakterin R15 eklemleri her karede KODLA pozlanır. Bu istemcide
-- çalışır çünkü kendi karakterinin ağ sahipliği istemcide. Sunucu yalnızca şut
-- beklerken poz yazdığı için, yürüyüş/duruş burada oynatılır -> "animasyonlar
-- çalışmıyor" şikayetinin kaynağı buydu.
local Shared = ReplicatedStorage:WaitForChild("Shared", 20)
local function loadSharedAnim(name)
	if not Shared then
		return nil
	end
	local animFolder = Shared:FindFirstChild("Anim")
	local mod = animFolder and animFolder:FindFirstChild(name)
	if not mod then
		return nil
	end
	local ok, res = pcall(require, mod)
	if ok and type(res) == "table" then
		return res
	end
	return nil
end
local HumanoidPose = loadSharedAnim("HumanoidPose")
local PlayerPose = loadSharedAnim("PlayerPose")
local KickAnim = loadSharedAnim("KickAnim")
local animClock = 0 -- sürekli saat: adım fazı ve nefes için
-- Adım fazı ve genlik BİRİKTİRİLİR (mutlak saat * anlık hız değil): hız
-- değiştiğinde poz sıçramaz. Sunucuda her oyuncu için ayrı state tutulur.
local poseWalkState = PlayerPose and PlayerPose.newState and PlayerPose.newState() or nil
-- Vuruş pozu için TEK YAZAR kuralı: sunucu şutu beklerken (pending) pozu o
-- yazar; istemci aynı anda yazarsa iki kaynak aynı eklem için yarışır ve bacak
-- titrer. İstemci yalnızca iki durumda kendi pozunu yazar:
--   1) SPACE basılıyken (hazırlık pozu — anında geri bildirim)
--   2) sunucunun vuruş penceresi kapandıktan sonra (yürüyüş/duruş devralır)
local serverKickUntil = 0 -- animClock cinsinden: bu ana kadar pozu sunucu yazar
local windupPose = nil -- basılı tutarken üretilecek hazırlık pozu

-- ---------------------------------------------------------------- vuruş türü / ayak seçimi (profesyonel biomekanik)
local SHOT = Config and Config.SHOT or { types = { "instep" }, labels = { instep = "Düz ayak" } }
local shotTypes = SHOT.types or { "instep" }
local shotIndex = 1
local currentFoot = "R" -- "L" | "R"

local HINT_FORMAT = "WASD → topa yaklaş  ·  SPACE basılı tut → güç  ·  bırak → şut   |   T → vuruş türü (%s)   |   C → kamera: %s   |   F → ayak   |   V → izleme   |   R → sıfırla"

-- ÖNEMLİ: `hint` etiketi aşağıda (HUD bölümünde) oluşturuluyor. Lua'da bir
-- local'in kapsamı bildiriminden SONRA başlar; bu yüzden `local hint` burada
-- bildirilmezse fonksiyonların içindeki `hint` GLOBAL sayılır ve T/F'ye
-- basıldığında "attempt to index a nil value (global 'hint')" hatası verir.
local hint

local function shotLabel()
	local st = shotTypes[shotIndex] or "instep"
	return (SHOT.labels and SHOT.labels[st] or st) .. "  |  ayak: " .. currentFoot
end

-- KAMERA KİPLERİ
--   first      : 1. ŞAHIS (varsayılan). Kamerayı Roblox sürer (baş kilitli),
--                biz CFrame yazmayız; karakterin gövdesi aşağı bakınca görünür.
--   third      : 3. şahıs, omuz üstü ve YAKIN (kendi animasyonunu görmek için).
--   spectator  : izleme — topun arkasına geçip kaleyi çerçeveler (V).
-- C: 1. şahıs <-> 3. şahıs. V: izleme aç/kapa (eski davranış korunur).
local CAMERA_LABEL = { first = "1. şahıs (C)", third = "3. şahıs (C)", spectator = "izleme (V)" }
local cameraMode = "first"
local nonSpectatorMode = "first" -- V'den çıkınca dönülecek kip
local appliedCameraMode = nil -- kip değişince bir kez yaz (her karede değil)

local function cameraLabel()
	return CAMERA_LABEL[cameraMode] or cameraMode
end

-- Sunucunun şutu SESSİZCE reddettiği durum (top menzil dışında) istemcide
-- görünür olmalı: yoksa oyuncu "şut çekemiyorum" der. reachState her karede
-- onFrame tarafından güncellenir; metin buradan okunur.
local reachState = nil -- nil (menzilde) | sayı: topun metre cinsinden uzaklığı

-- Sunucunun gönderdiği şut geri bildirimi (tampona alındı / reddedildi / çıktı).
-- Sunucu otoriter taraf olduğu için asıl doğru bilgi budur; istemcideki mesafe
-- ölçümü yalnızca anlık ipucudur.
local serverHint = nil
local serverHintUntil = 0
-- Top katı menzil içindeyse HUD "ŞUT HAZIR" der: oyuncu SPACE'in boşa
-- gitmeyeceğini görür (sahiplik bandında da şut çıkar, ama kesin olan bu).
local inStrictReach = false

local function updateHint()
	if not hint then
		return
	end
	if serverHint and animClock < serverHintUntil then
		-- Sunucunun verdiği neden her şeyden önce gelir (otoriter bilgi).
		hint.Text = serverHint .. "   |   " .. shotLabel() .. "   |   " .. cameraLabel()
		hint.TextColor3 = Color3.fromRGB(255, 226, 140)
		return
	end
	if reachState then
		-- Uyarı, vuruş türü/ayak bilgisini SİLMEZ: oyuncu o anda T/F ile
		-- hazırlık yapıyor olabilir, ikisi birlikte görünmeli.
		local verdict = (reachState > BUFFER_REACH) and "şut çıkmaz" or "koşunca şut çıkar"
		hint.Text = "TOPA YAKLAŞ → " .. string.format("%.1f", reachState)
			.. " m önde  ·  menzil " .. string.format("%.1f", POSSESSION_REACH)
			.. " m  ·  " .. verdict .. "  ·  WASD ile koş   |   " .. shotLabel()
			.. "   |   " .. cameraLabel()
		hint.TextColor3 = Color3.fromRGB(255, 206, 110)
		return
	end
	hint.Text = (inStrictReach and "ŞUT HAZIR  ·  " or "")
		.. string.format(HINT_FORMAT, shotLabel(), cameraLabel())
	hint.TextColor3 = inStrictReach and Color3.fromRGB(150, 255, 190) or Color3.fromRGB(232, 240, 246)
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

local poseOk = false -- karakter pozlanabiliyor mu (R15 ya da R6)?
local poseConn = nil -- eklemler/Animate sonradan gelirse yeniden denemek için
local poseCheckClock = 0 -- periyodik uygunluk kontrolü (geç yüklenen R6/R15)
local poseSuppressed = false -- poz yazımı bir kez bozulduysa otomatik geri açma

--[[ Roblox'un varsayılan karakter animasyonu (`Animate` LocalScript) her karede
     Motor6D.Transform'a KENDİ pozunu yazar ve bizim prosedürel pozumuzu EZER.
     SCRIPT'i KAPATMAK YETERLİ DEĞİL: zaten oynayan AnimationTrack'ler Animator
     içinde yaşamaya devam eder ve her karede Transform'u yeniden yazar. Bu
     yüzden çalışan track'leri de durduruyoruz. ]]
local function stopDefaultTracks(char)
	local hum = char and char:FindFirstChild("Humanoid", true)
	local animator = hum and hum:FindFirstChild("Animator", true)
	local function stopTracks(obj)
		if not obj or not obj.GetPlayingAnimationTracks then
			return
		end
		local ok, tracks = pcall(function()
			return obj:GetPlayingAnimationTracks()
		end)
		if not ok or type(tracks) ~= "table" then
			return
		end
		for _, track in ipairs(tracks) do
			pcall(function()
				track:Stop(0)
			end)
		end
	end
	stopTracks(hum)
	stopTracks(animator)
end

local function setDefaultAnimateEnabled(char, enabled)
	if not char then
		return
	end
	-- CharacterAdded sırasında Animate bazen biraz sonra eklenir; recursive
	-- arama ve sonraki ChildAdded/periyodik kontrol bunu yakalar.
	local animate = char:FindFirstChild("Animate", true)
	if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
		animate.Disabled = not enabled
	end
	if not enabled then
		stopDefaultTracks(char)
	end
end

-- Motor6D'ler CharacterAdded anında henüz mevcut olmayabilir: pozu yalnızca
-- bir kez kontrol etmek "animasyon çalışmıyor" şikâyetinin ikinci sebebidir.
local function refreshPoseSupport(char)
	char = char or character
	if not char or poseSuppressed then
		return
	end
	if POSE_HUMANOID and HumanoidPose and PlayerPose then
		local ok, supported = pcall(HumanoidPose.supported, char)
		poseOk = ok and supported == true
	else
		poseOk = false
	end
	setDefaultAnimateEnabled(char, not poseOk)
end

local function bindCharacter(char)
	character = char
	hrp = char:WaitForChild("HumanoidRootPart", 10)
	humanoid = char:WaitForChild("Humanoid", 10)
	setJumpEnabled(false)
	if poseConn then
		poseConn:Disconnect()
		poseConn = nil
	end
	poseOk = false
	poseSuppressed = false
	poseCheckClock = 0
	refreshPoseSupport(char)
	poseConn = char.ChildAdded:Connect(function(child)
		if child:IsA("Motor6D") or child:IsA("AnimationConstraint") or child:IsA("Animator") or child.Name == "Animate" then
			refreshPoseSupport(char)
		end
	end)
	-- Yeni karakterde Humanoid de yeni: kamera kipi (1. şahıs kilidi) yeniden
	-- uygulanmalı, aksi halde respawn sonrası 3. şahısta kalır.
	appliedCameraMode = nil
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
		-- Şut geri bildirimi: sunucu bir şutu reddetti/tampona aldı/çıkardı ise
		-- NEDENİ HUD'da kısa süre gösterilir (sessiz red yok).
		if type(payload.hint) == "string" and payload.hint ~= "" then
			serverHint = payload.hint
			serverHintUntil = animClock + 2.4
			updateHint()
		elseif payload.event == "shotFired" then
			serverHint = nil
		end
	end)
end

-- ------------------------------------------------------------ şut / nişan
local charging = false
local charge = 0
-- (kamera kipi durumu yukarıda, HUD bölümünün yanında tanımlı: Lua'da bir local
--  bildiriminden ÖNCE görünmez, bu yüzden cameraLabel()'den önce gelmeli.)

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

--[[ Karakterin baktığı yönden nişan ışını (baş yüksekliğinden).
     1. şahısta kamera başa kilitli ve fare ekranın ortasında olduğu için
     nişan = karakterin yönü. Ayrıca kameraya erişilemediği durumlarda SON
     ÇARE olarak kullanılır: şut hiçbir zaman sessizce yutulmaz. ]]
local function characterAim()
	if not hrp or not hrp.Parent then
		return nil, nil
	end
	return hrp.Position + Vector3.new(0, 1.2, 0), hrp.CFrame.LookVector
end

local function computeAim()
	-- 1. ŞAHIS: fare ışını bu kipte anlamlı değil (fare merkezde kilitli);
	-- nişan karakterin baktığı yerdir.
	if cameraMode == "first" then
		local origin, dir = characterAim()
		if origin then
			local aim = projectToGoalPlane(origin, dir)
			if aim then
				return aim
			end
		end
	end
	if not camera then
		local origin, dir = characterAim()
		return origin and projectToGoalPlane(origin, dir) or nil
	end
	local ray = mouseRay(camera)
	if ray then
		local aim = projectToGoalPlane(ray.Origin, ray.Direction)
		if aim then
			return aim
		end
	end
	local fromCamera = projectToGoalPlane(camera.CFrame.Position, camera.CFrame.LookVector)
	if fromCamera then
		return fromCamera
	end
	-- Kamera bakışı da kaleyi önden kesmiyorsa karakterin yönüne düş.
	local origin, dir = characterAim()
	if origin then
		local fromCharacter = projectToGoalPlane(origin, dir)
		if fromCharacter then
			return fromCharacter
		end
	end
	-- SON ÇARE: hiçbir ışın kaleyi ÖNDEN kesmiyorsa (ör. karakterin sırtı
	-- kaleye dönük) nişan KALE ORTASINA düşer. computeAim nil dönerse fireKick
	-- hiç FireServer çağırmaz ve şut SESSİZCE yutulur — bu kabul edilemez.
	return Vector3.new(GOAL_PLANE, 1.0 * S, 0)
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
	-- Sunucunun vuruş penceresi: CONTACT_TIME (0.24 s) + DURATION (0.62 s) +
	-- bir kare payı. Bu aralıkta KickAnim pozunu sunucu yazar (temas anı topun
	-- gerçek ayrılış anıyla birebir aynı kalsın diye); istemci karışmaz.
	if KickAnim then
		serverKickUntil = animClock + KickAnim.CONTACT_TIME + KickAnim.DURATION + 0.15
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Space then
		charging = true
		charge = 0
		barBack.Visible = true
		-- Hazırlık pozu: bacak hafifçe geriye, gövde döner. Güç barıyla birlikte
		-- ANINDA görsel geri bildirim verir (sunucuya henüz bir şey gitmedi).
		if KickAnim then
			windupPose = KickAnim.new({
				charge = 0.35,
				foot = currentFoot,
				shotType = shotTypes[shotIndex] or "instep",
			}):sample(0.14).pose
		end
	elseif input.KeyCode == Enum.KeyCode.R and resetRemote then
		resetRemote:FireServer()
	elseif input.KeyCode == Enum.KeyCode.V then
		if cameraMode == "spectator" then
			cameraMode = nonSpectatorMode
		else
			cameraMode = "spectator"
		end
		updateHint()
	elseif input.KeyCode == Enum.KeyCode.C then
		-- 1. şahıs <-> 3. şahıs (izlemeden de çıkarır)
		cameraMode = (cameraMode == "first") and "third" or "first"
		nonSpectatorMode = cameraMode
		updateHint()
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
	windupPose = nil
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
	animClock = animClock + dt

	-- Top: sunucu konumunu yumuşat + hız tahmini
	local target = serverBall.Position
	local k = 1 - math.exp(-16 * dt)
	ballVel = ballVel:Lerp((target - lastTarget) / math.max(dt, 1e-3), 1 - math.exp(-7 * dt))
	lastTarget = target
	local predicted = target + ballVel * 0.03
	renderPos = renderPos:Lerp(predicted, k)
	visual.CFrame = CFrame.new(renderPos)

	-- Kamera kipi: yalnızca kip DEĞİŞTİĞİNDE yaz (her karede CameraType/CameraMode
	-- yazmak Roblox'un kendi kamera güncellemesiyle yarışır).
	local cam = resolveCamera()
	if cam and appliedCameraMode ~= cameraMode then
		appliedCameraMode = cameraMode
		camera = cam
		camInit = false -- yeni kipe geçerken yumuşatma sıfırlansın (teleport hissi olmasın)
		if cameraMode == "first" then
			-- 1. ŞAHIS: kamerayı Roblox sürer (Humanoid.CameraMode = LockFirstPerson
			-- başı kilitler ve Head'i gizler). Biz CFrame YAZMAYIZ; yazsak
			-- Roblox ile kavga eder ve görüntü titrer.
			if humanoid then
				humanoid.CameraMode = Enum.CameraMode.LockFirstPerson
			end
			cam.CameraType = Enum.CameraType.Custom
		else
			if humanoid then
				humanoid.CameraMode = Enum.CameraMode.Classic
			end
			cam.CameraType = Enum.CameraType.Scriptable
		end
	end

	-- 3. şahıs / izleme: kamerayı biz süreriz
	if cam and camera and cameraMode ~= "first" then
		local focus = renderPos
		local desiredPos, desiredLook
		if cameraMode == "spectator" then
			-- Top neredeyse oraya yerleş, kaleyi çerçevele
			desiredPos = focus + Vector3.new(-26, 15, 7)
			desiredLook = Vector3.new(GOAL_PLANE, 1.2 * S, 0)
		else
			-- 3. ŞAHIS: omuz üstü ve YAKIN. Eskiden 30 stud geride / 20 stud
			-- yukarıdaydı; karakter ekranda birkaç piksel kaldığı için
			-- animasyonlar "çalışmıyor" gibi görünüyordu.
			if hrp and hrp.Parent then
				focus = hrp.Position
			end
			desiredPos = focus + Vector3.new(-8.5, 4.0, 0)
			desiredLook = focus + Vector3.new(12, -0.8, 0)
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
	end

	-- Menzil geri bildirimi: sunucu top uzaktayken şutu sessizce reddeder;
	-- istemci aynı kapıyı okuyup oyuncuya NEDENİNİ söyler (sessiz red yok).
	if hrp and hrp.Parent then
		local dx = hrp.Position.X - serverBall.Position.X
		local dz = hrp.Position.Z - serverBall.Position.Z
		local distM = math.sqrt(dx * dx + dz * dz) / S
		if distM > POSSESSION_REACH then
			reachState = distM
		else
			reachState = nil
		end
		inStrictReach = distM <= KICK_REACH
	else
		reachState = nil
		inStrictReach = false
	end
	updateHint()

	-- Motor6D'ler geç yüklenebilir (CharacterAdded ≠ karakter hazır). Arada bir
	-- yeniden dene; aksi hâlde prosedürel poz hiç açılmadan kalır.
	poseCheckClock = poseCheckClock + dt
	if poseCheckClock >= 0.25 then
		poseCheckClock = 0
		refreshPoseSupport()
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

--[[ KRİTİK ZAMANLAMA: Roblox'un Animator'ı her karede eklem Transform'unu
     PreAnimation sonrası / PreSimulation öncesinde kendi pozlarıyla EZER.
     RenderStepped'de yazılan prosedürel poz bu yüzden ekrana hiç yansımıyordu.
     Resmî öneri pozu PRE-SIMULATION içinde yazmaktır (Stepped'in yerini aldı);
     eski oyunlarda olay yoksa Stepped'e düşeriz. Kamera, HUD ve top yumuşatma
     RenderStepped'de kalır. ]]
local poseSignal = RunService.PreSimulation or RunService.Stepped

local function onStepped(dt)
	if not poseOk or not character or not character.Parent or not hrp or not hrp.Parent then
		return
	end
	-- Hız iki kaynaktan: MoveDirection (girdi niyeti) ve kökün gerçek
	-- hızı (itme/taşınma). Büyük olanı alınır; tek kaynak hızı 0
	-- gösterdiğinde koşu animasyonu duruşa düşüp "donmuş" görünüyordu.
	local moveVel = humanoid and humanoid.MoveDirection or Vector3.zero
	local rootVel = hrp.AssemblyLinearVelocity or Vector3.zero
	local speed = math.max(moveVel.Magnitude, rootVel.Magnitude) / S -- stud/s -> m/s
	-- State, şut penceresinde de ilerler: sunucu vuruş pozunu yazarken istemci
	-- poz uygulamasa bile faz birikmeye devam eder; pencere kapanınca yürüyüş
	-- pozu kaldığı yerden (sıçramadan) devralır.
	local walkPose = nil
	if poseWalkState then
		walkPose = PlayerPose.step(poseWalkState, dt, animClock, speed)
	end
	-- Şut penceresi açıkken sunucu yazar (tek yazar kuralı); istemci karışmaz.
	if animClock >= serverKickUntil then
		local pose = windupPose or walkPose
		if pose then
			local ok = pcall(HumanoidPose.apply, character, pose)
			if not ok then
				-- Pozlama bozuldu: karakteri T-pozda DONMUŞ bırakma — varsayılan
				-- Roblox animasyonunu geri aç ve otomatik yeniden denemeyi bırak.
				poseOk = false
				poseSuppressed = true
				setDefaultAnimateEnabled(character, true)
			end
		end
	end
end

poseSignal:Connect(onStepped)
RunService.RenderStepped:Connect(onFrame)
