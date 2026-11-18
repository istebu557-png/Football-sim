--[[
	FootballSim — TEK KURULUM DOSYASI (otomatik üretilir, elle düzenlemeyin).

	KULLANIM
	  1) Roblox Studio'da oyunu aç.
	  2) View > Command Bar (komut çubuğu) aç.
	  3) Bu dosyanın TAMAMINI kopyalayıp komut çubuğuna yapıştır, Enter.
	  4) Sahne kurulur, scriptler yerleşir. Play'e bas: SPACE ile şut çek.

	Yeniden üretmek için: npm run install:build
	Kaynak: src/ (28 modül)
]]

local SOURCES = {
	["client/BallView"] = { class = "LocalScript", source = [=[
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
local BC = (Config and Config.BALL_CONTROL) or {}
local KICK_REACH = BC.kickReach or 2.0

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

local HINT_FORMAT = "WASD → topa yaklaş  ·  SPACE basılı tut → güç  ·  bırak → şut   |   T → vuruş türü (%s)   |   F → ayak   |   V → izleme   |   R → sıfırla"

-- ÖNEMLİ: `hint` etiketi aşağıda (HUD bölümünde) oluşturuluyor. Lua'da bir
-- local'in kapsamı bildiriminden SONRA başlar; bu yüzden `local hint` burada
-- bildirilmezse fonksiyonların içindeki `hint` GLOBAL sayılır ve T/F'ye
-- basıldığında "attempt to index a nil value (global 'hint')" hatası verir.
local hint

local function shotLabel()
	local st = shotTypes[shotIndex] or "instep"
	return (SHOT.labels and SHOT.labels[st] or st) .. "  |  ayak: " .. currentFoot
end

-- Sunucunun şutu SESSİZCE reddettiği durum (top menzil dışında) istemcide
-- görünür olmalı: yoksa oyuncu "şut çekemiyorum" der. reachState her karede
-- onFrame tarafından güncellenir; metin buradan okunur.
local reachState = nil -- nil (menzilde) | "far:<metre>"

local function updateHint()
	if not hint then
		return
	end
	if reachState then
		-- Uyarı, vuruş türü/ayak bilgisini SİLMEZ: oyuncu o anda T/F ile
		-- hazırlık yapıyor olabilir, ikisi birlikte görünmeli.
		local meters = reachState:sub(5)
		hint.Text = "TOPA YAKLAŞ → " .. meters .. " m uzakta  ·  şut menzili "
			.. string.format("%.1f", KICK_REACH) .. " m  ·  WASD ile koş   |   "
			.. shotLabel()
		hint.TextColor3 = Color3.fromRGB(255, 206, 110)
		return
	end
	hint.Text = string.format(HINT_FORMAT, shotLabel())
	hint.TextColor3 = Color3.fromRGB(232, 240, 246)
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

local poseOk = false -- karakter R15 mi (pozlanabiliyor mu)?

local function bindCharacter(char)
	character = char
	hrp = char:WaitForChild("HumanoidRootPart", 10)
	humanoid = char:WaitForChild("Humanoid", 10)
	setJumpEnabled(false)
	poseOk = false
	if HumanoidPose and PlayerPose then
		local ok, supported = pcall(HumanoidPose.supported, char)
		poseOk = ok and supported == true
	end
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

	-- Menzil geri bildirimi: sunucu top uzaktayken şutu sessizce reddeder;
	-- istemci aynı kapıyı okuyup oyuncuya NEDENİNİ söyler (sessiz red yok).
	if hrp and hrp.Parent then
		local dx = hrp.Position.X - serverBall.Position.X
		local dz = hrp.Position.Z - serverBall.Position.Z
		local distM = math.sqrt(dx * dx + dz * dz) / S
		if distM > KICK_REACH then
			reachState = "far:" .. string.format("%.1f", distM)
		else
			reachState = nil
		end
	else
		reachState = nil
	end
	updateHint()

	-- Karakter pozu (istemci): yürürken koşu döngüsü, dururken nefes alan
	-- duruş, SPACE basılıyken hazırlık pozu. Şut penceresi açıkken YAZMAZ:
	-- KickAnim'i temas anıyla birebir eşleşsin diye sunucu uygular (tek yazar).
	if poseOk and character and character.Parent and hrp and hrp.Parent then
		if animClock >= serverKickUntil then
			-- Hız iki kaynaktan: MoveDirection (girdi niyeti) ve kökün gerçek
			-- hızı (itme/taşınma). Büyük olanı alınır; tek kaynak hızı 0
			-- gösterdiğinde koşu animasyonu duruşa düşüp "donmuş" görünüyordu.
			local moveVel = humanoid and humanoid.MoveDirection or Vector3.zero
			local rootVel = hrp.AssemblyLinearVelocity or Vector3.zero
			local speed = math.max(moveVel.Magnitude, rootVel.Magnitude) / S -- stud/s -> m/s
			local pose = windupPose or PlayerPose.walk(animClock, speed)
			local ok = pcall(HumanoidPose.apply, character, pose)
			if not ok then
				poseOk = false
			end
		end
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
]=] },
	["server/SimLoop"] = { class = "Script", source = [=[
--[[
	SimLoop — sunucu otoritesi (yarım saha, 1 kaleci, 1 şutçu).

	Akış (her Heartbeat):
	  1) Kaleci AI'sı bir adım atar: topun kale düzlemine varacağı noktayı ve
	     yüksekliğini tahmin eder, dalış hedefini kilitler.
	  2) Şutçu NPC'si topa yürür, ayak mesafesine gelince topun gerçek konumuna
	     göre adaptif şut pozisyonu seçer.
	  3) Oyuncuların top-oyuncu ilişkisi işlenir (dokunuş, kapatma, gövde).
	  4) Gövdeler simülasyona verilir; top 240 Hz'de ilerler, direklere/gövdelere
	     çarpar, kaleye girerse FILE takılır (Net).
	  5) ANİMASYON (tamamen kodla, asset yok): kaleci dalışı, şutçu şutu ve
	     oyuncunun R15 eklemleri sunucuda FK ile pozlanır.
	  6) Görseller güncellenir; gol olursa skor + santra.

	Animasyon nedenseldir: şutun topu bıraktığı an, animasyonun TEMAS anıdır
	(0.24 s). Oyuncu şut tuşuna bastığında top hemen ayrılmaz; savurma tamamlanır.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Vec3 = require(Shared.Core.Vec3)
local Validate = require(Shared.Core.Validate)
local Rng = require(Shared.Core.Rng)
local Ballistics = require(Shared.Core.Ballistics)
local Sim = require(Shared.Sim)
local SceneBuilder = require(Shared.World.SceneBuilder)
local Net = require(Shared.Physics.Net)
local BallControl = require(Shared.Player.BallControl)
local Keeper = require(Shared.Player.Keeper)
local Striker = require(Shared.Player.Striker)
local KeeperAnim = require(Shared.Anim.KeeperAnim)
local KickAnim = require(Shared.Anim.KickAnim)
local HumanoidPose = require(Shared.Anim.HumanoidPose)
local PlayerPose = require(Shared.Anim.PlayerPose)

local S = Config.STUDS_PER_METER
local P = Config.PITCH
local ANIM = Config.ANIM or {}

-- Lua 5.3: math.atan(y, x) | Luau: math.atan2(y, x). Ikisi de desteklensin
-- (Vec3 ve SceneBuilder ile ayni desen; test kosucusu Lua 5.3 kullanir).
local atan2 = math.atan2 or math.atan

-- ---------------------------------------------------------------- 1) Sahne
local scene = SceneBuilder.build({ half = true, goalSide = 1 })
local ballPart = scene.ball
local keeperModel = scene.keeper
local strikerModel = scene.striker
local backNet = scene.backNet
local backNetX = scene.backX -- metre

-- ------------------------------------------------------------ 2) Simülasyon
local sim = Sim.new({ seed = 2026 })
local goalNet = Net.new(Config, scene.goalSide)
sim.nets[1] = goalNet

local keeper = Keeper.new(Config, scene.goalSide)
local striker = Striker.new(Config, { side = scene.goalSide, pos = scene.strikerStart })
local rng = Rng.new(4242)

local controls = {}
local function getControl(player)
	local c = controls[player]
	if not c then
		c = BallControl.new(Config)
		controls[player] = c
	end
	return c
end

local stats = { goals = 0, saves = 0, kicks = 0, shots = 0 }

-- -------------------------------------------------------------- 3) Remotes
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local function ensureRemote(name)
	local ev = remotes:FindFirstChild(name)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = remotes
	end
	return ev
end

local kickRemote = ensureRemote("Kick")
local resetRemote = ensureRemote("ResetBall")
local stateRemote = ensureRemote("MatchState") -- sunucu -> istemci: skor/olay

-- ------------------------------------------------------- 4) Oyuncu durumu
local function playerState(player)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	local look = hrp.CFrame.LookVector
	local facing = atan2(look.Z, look.X) -- +x'ten +z'ye (Vec3.yaw ile aynı)
	return BallControl.playerState(
		Vector3.new(hrp.Position.X, 0, hrp.Position.Z),
		hrp.AssemblyLinearVelocity,
		facing,
		S
	)
end

local function resetBall()
	local start = scene.ballStart
	sim.ball:setState(
		Vec3.new(start.X / S, start.Y / S, start.Z / S),
		Vec3.new(0, 0, 0),
		Vec3.new(0, 0, 0)
	)
	goalNet:resetSag()
	-- Şutçu da başlangıç noktasına döner
	striker.pos = scene.strikerStart
	striker.vel = Vec3.new(0, 0, 0)
	striker.kick = nil
	striker.kickT = 0
	striker.cooldown = 0.6
	striker.walkPhase = 0
end

resetBall()

-- --------------------------------------------------------------- 5) Şut
-- Oyuncunun şutu: tuşa basıldığında pozisyon seçilir, top TEMAS anında ayrılır.
local lastKickAt = {}
-- Oyuncu karakterlerinin prosedürel animasyon saati (yürüyüş fazı + nefes).
-- Şut beklemede OLMASA da karakter pozlanır: eskiden yalnızca şut sırasında
-- poz yazıldığı için oyuncu "animasyonlar çalışmıyor" diyordu.
local playerAnimClock = 0
local pending = {} -- player -> { t, kick, speed, aimY, aimZ, spin, fired }

--[[ İstemciden gelen HER değer güvenilmezdir (exploiter arbitrary tablo/string
	gönderebilir). KickAnim, `SHOT[shotType]` ve `"hip" .. foot` kullandığı için
	doğrulanmamış girdi sunucu handler'ını patlatır (ör. shotType = "labels" ->
	sp.power = nil -> aritmetik hatası; foot = {} -> concatenate hatası).
	Bu yüzden beyaz liste: listede yoksa varsayılana düş. ]]
-- Politika: BEYAZ LİSTE + VARSAYILANA DÜŞ. Kurallar src/shared/Core/Validate.luau
-- içinde (birim testli); burada yalnızca bu dosyanın kullandığı kısa adlar bağlanır.
-- Çağrı yerleri (isFiniteVec3/sanitize*) bilerek aynı isimde kalır:
-- tools/verify.js "her launch bölgesi isFiniteVec3 ile korunmuş mu?" diye statik
-- denetim yapar.
local VALID_SHOT_TYPES = Validate.shotTypeSet(Config.SHOT)

local function sanitizeShotType(value)
	return Validate.shotType(value, VALID_SHOT_TYPES)
end

local function sanitizeFoot(value)
	return Validate.foot(value)
end

-- NaN/inf istemciden gelebilir: math.min(1, NaN) = NaN olduğu için clamp yetmez,
-- sonlu sayı denetimi şart. Bu yüzden güç/nişan Validate.clamp'ten geçer (önce
-- sonluluk, sonra aralık); topa yazılacak hız ise aşağıdaki isFiniteVec3'ten.
-- Topa YAZILACAK hız için son savunma hattı: Ballistics.solveLaunch ulaşılamayan
-- hedefte NaN üretebilir ve NaN hız simülasyonun geri kalanını kalıcı bozar.
local function isFiniteVec3(v)
	return Validate.vec3(v)
end

kickRemote.OnServerEvent:Connect(function(player, charge, aimZ, aimY, shotType, foot)
	local now = os.clock()
	if lastKickAt[player] and now - lastKickAt[player] < 0.35 then
		return
	end

	local state = playerState(player)
	if not state then
		return
	end

	local control = getControl(player)
	if not control:canKick(sim.ball, state) then
		return
	end
	if pending[player] then
		return
	end

	lastKickAt[player] = now

	local c = Validate.clamp(charge, 0, 1, 0.5)
	local targetZ = Validate.clamp(aimZ, -3.3, 3.3, 0)
	local targetY = Validate.clamp(aimY, 0.2, 2.3, 1.0)

	-- Nişan hatası: yanal sapma (deterministik RNG)
	local errRad = rng:normal(0, math.rad(Config.BALL_CONTROL.aimErrorDeg))
	local dx = P.halfLength - sim.ball.pos.x
	local dz = targetZ - sim.ball.pos.z
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist < 0.5 then
		return
	end
	local lateral = math.tan(errRad) * dist

	-- Topun oyuncuya göre konumu -> adaptif şut pozisyonu (vuruş türü + ayak)
	local toBall = Vec3.withY(Vec3.sub(sim.ball.pos, state.pos), 0)
	local forward = Vec3.new(math.cos(state.facing), 0, math.sin(state.facing))
	local right = Vec3.cross(forward, Vec3.new(0, 1, 0))
	local kick = KickAnim.new({
		ballHeight = sim.ball.pos.y,
		ballLateral = Vec3.dot(toBall, right),
		ballForward = Vec3.dot(toBall, forward),
		charge = c,
		shotType = sanitizeShotType(shotType),
		foot = sanitizeFoot(foot), -- nil -> otomatik (topun yanına göre)
	})

	local speed = control:speedForCharge(c)
	-- Falso: alçak şut topspin, yüksek köşe backspin (Ballistics.shotSpin)
	local spin = Ballistics.shotSpin(speed, targetY, targetZ)

	pending[player] = {
		t = 0,
		kick = kick,
		speed = speed,
		aimY = targetY,
		aimZ = targetZ + lateral,
		spin = Vec3.add(spin, Vec3.new(0, rng:symmetric(10), 0)),
		fired = false,
	}
end)

-- Sıfırlama da hız sınırlı: herhangi bir istemci bunu spamleyip maçı
-- kilitleyemesin (sunucu otoritesi).
local lastResetAt = 0
resetRemote.OnServerEvent:Connect(function()
	local now = os.clock()
	if now - lastResetAt < 0.5 then
		return
	end
	lastResetAt = now
	resetBall()
end)

-- ------------------------------------------------------- 6) Ana döngü
local resetTimer = 0
local lastKeeperHits = 0

local keeperAnim = nil
local keeperAnimT = 0
local keeperDiveRef = nil

local keeperClock = 0 -- kaleci idle animasyonunun saati (nefes/salinim)

-- Kaleci pozu: yeni dalış hedefi geldiğinde animasyon başlar; süresi bittiğinde canlı idle pozuna (nefes + salınım) döner.
local function keeperPose(dt)
	if not ANIM.keeperPoseEnabled then
		return nil
	end
	keeperClock = keeperClock + dt
	local target = keeper.diveTarget
	if target and (not keeperAnim or keeperAnimT >= keeperAnim:duration()) then
		keeperAnim = KeeperAnim.new({
			dz = target.dz,
			height = target.height,
			speed = target.speed,
		})
		keeperAnimT = 0
	end
	if keeperAnim then
		keeperAnimT = keeperAnimT + dt
		if keeperAnimT < keeperAnim:duration() then
			return keeperAnim:sample(keeperAnimT).pose
		end
		keeperAnim = nil
	end
	-- Dalış yoksa heykel değil: nefes + ağırlık salınımı (sahne canlı kalır)
	return KeeperAnim.idle(keeperClock)
end

local function broadcastState(event, extra)
	if stateRemote then
		stateRemote:FireAllClients({
			goals = stats.goals,
			saves = stats.saves,
			kicks = stats.kicks,
			shots = stats.shots,
			sag = goalNet.sag,
			event = event,
			extra = extra,
		})
	end
end

RunService.Heartbeat:Connect(function(frameDt)
	if resetTimer > 0 then
		resetTimer = resetTimer - frameDt
		if resetTimer <= 0 then
			resetBall()
		end
	end

	-- 1) Kaleci
	local keeperBody = keeper:step(sim.ball, frameDt)

	-- 2) Şutçu NPC: yürü -> şut pozisyonu -> TEMAS anında top ayrılır
	if ANIM.strikerEnabled and strikerModel then
		local shot = striker:step(frameDt, sim.ball, keeper)
		if shot and shot.type == "shoot" then
			local velocity = Ballistics.solveLaunch(sim.ball.pos, shot.target, shot.speed, Config.GRAVITY)
			if isFiniteVec3(velocity) then
				sim.ball.vel = velocity
				sim.ball.spin = Ballistics.shotSpin(shot.speed, shot.target.y, shot.target.z)
				sim.ball.mode = "air"
				stats.shots = stats.shots + 1
			end
		end
		SceneBuilder.updateStrikerModel(strikerModel, striker:pose(), striker.pos, striker.facing, S)
	end

	-- 3) Oyuncuların şutları: savurma tamamlanınca top ayrılır
	for player, shot in pairs(pending) do
		shot.t = shot.t + frameDt
		if not shot.fired and shot.t >= KickAnim.CONTACT_TIME then
			shot.fired = true
			local velocity = Ballistics.solveLaunch(
				sim.ball.pos,
				Vec3.new(P.halfLength, shot.aimY, shot.aimZ),
				shot.speed,
				Config.GRAVITY
			)
			if isFiniteVec3(velocity) then
				getControl(player):kick(sim.ball, nil, velocity, shot.spin, sim.time)
				stats.kicks = stats.kicks + 1
			end
		end
		-- Sunucu tarafı R15 pozu (deneysel; Config.ANIM.poseHumanoid ile kapanır)
		local character = player.Character
		if ANIM.poseHumanoid and character and HumanoidPose.supported(character) then
			HumanoidPose.apply(character, shot.kick:sample(shot.t).pose)
		end
		if shot.t >= shot.kick:duration() then
			-- clear() çağırmıyoruz: vuruş biter bitmez eklemleri kimliğe
			-- sıfırlamak karakteri bir kare "donmuş" gösteriyordu. Bunun
			-- yerine 3b'deki yürüyüş pozu devralır (geçiş sürekli).
			pending[player] = nil
		end
	end

	-- 3b) Oyuncu karakterleri: yürüyüş/duruş pozu her karede yazılır.
	-- Şut bekleyen oyuncunun pozu yukarıdaki döngüde KickAnim'den gelir;
	-- burada yalnızca şut beklemeyenler pozlanır (KickAnim önceliği korunsun).
	if ANIM.poseHumanoid then
		playerAnimClock = playerAnimClock + frameDt
		for _, player in ipairs(Players:GetPlayers()) do
			if not pending[player] then
				local character = player.Character
				if character and HumanoidPose.supported(character) then
					local state = playerState(player)
					local speed = (state and state.speed) or 0 -- m/s (yatay)
					HumanoidPose.apply(character, PlayerPose.walk(playerAnimClock, speed))
				end
			end
		end
	end

	-- 4) Oyuncular: dokunuş / kapatma / gövde
	for _, player in ipairs(Players:GetPlayers()) do
		local state = playerState(player)
		if state then
			getControl(player):update(sim.ball, state, sim.time)
		end
	end

	-- 5) Gövdeleri simülasyona ver (240 Hz çarpışma için)
	local bodies = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local state = playerState(player)
		if state then
			bodies[#bodies + 1] = {
				pos = state.pos,
				vel = state.vel,
				radius = Config.BALL_CONTROL.bodyRadius,
				height = Config.BALL_CONTROL.bodyHeight,
				restitution = 0.35,
				friction = 0.25,
			}
		end
	end
	bodies[#bodies + 1] = keeperBody
	sim.bodies = bodies

	-- 6) Simülasyon (240 Hz sabit adım)
	sim:update(frameDt)

	-- 7) Görseller + animasyon
	local bp = sim.ball.pos
	ballPart.CFrame = CFrame.new(bp.x * S, bp.y * S, bp.z * S)

	SceneBuilder.updateKeeperModel(keeperModel, keeperPose(frameDt), keeper.pos, S)
	backNet.CFrame = CFrame.new((backNetX + goalNet.sag) * S, (P.goalHeight / 2) * S, 0)

	-- Kurtarış sayacı
	if (keeperBody.hits or 0) > lastKeeperHits then
		stats.saves = stats.saves + (keeperBody.hits - lastKeeperHits)
		broadcastState("save")
	end
	lastKeeperHits = keeperBody.hits or 0

	-- 8) Gol
	if sim.lastGoal then
		local goal = sim.lastGoal
		sim.lastGoal = nil
		stats.goals = stats.goals + 1
		resetTimer = 2.4
		broadcastState("goal", { side = goal.side, speed = sim.ball:speed() })
		print(string.format(
			"[MAC] GOL | toplam %d gol, %d kurtaris, %d sut | ag esnemesi %.2f m",
			stats.goals, stats.saves, stats.kicks + stats.shots, goalNet.sag
		))
		return
	end

end)

Players.PlayerRemoving:Connect(function(player)
	controls[player] = nil
	lastKickAt[player] = nil
	pending[player] = nil
end)

-- Banner gerçegi soylesin: sutu kim atiyor?
print(string.format(
	"[FootballSim] Hazir | yarim saha | 1 kaleci (AI) + %s | top fizigi %d Hz | %d direk engeli",
	Config.ANIM.strikerEnabled and "1 sutcu NPC (demo)" or "sut: oynayan oyuncu",
	Config.SIM_HZ,
	#sim.obstacles
))
]=] },
	["shared/Anim/Ease"] = { class = "ModuleScript", source = [=[
--[[
	Ease — animasyon eğrileri.

	Gerçek hareketler sabit hızda olmaz: kaslar hızlanır, eklemler yumuşar.
	Buradaki eğriler, "takvim" tabanlı animasyonların temel taşı.
]]

local Ease = {}

function Ease.clamp01(v)
	if v < 0 then
		return 0
	elseif v > 1 then
		return 1
	end
	return v
end

-- t'yi [a,b] aralığından [0,1]'e normalize eder (dışarısı kırpılır)
function Ease.segment(t, a, b)
	if b <= a then
		return t >= b and 1 or 0
	end
	return Ease.clamp01((t - a) / (b - a))
end

-- Yumuşak başlangıç/bitiş (3t² - 2t³)
function Ease.smoothstep(x)
	local t = Ease.clamp01(x)
	return t * t * (3 - 2 * t)
end

-- Hızlı başlar, yavaş biter
function Ease.outCubic(x)
	local t = Ease.clamp01(x)
	return 1 - (1 - t) ^ 3
end

-- Yavaş başlar, hızlanır (vuruş öncesi savurma)
function Ease.inCubic(x)
	local t = Ease.clamp01(x)
	return t * t * t
end

-- 0 -> 1 -> 0 (darbe/uzanma eğrisi)
function Ease.pulse(x)
	local t = Ease.clamp01(x)
	return math.sin(t * math.pi)
end

function Ease.lerp(a, b, t)
	return a + (b - a) * t
end

--[[ Aşamalı geçiş: verilen zaman noktalarında (keys) değerleri tutar,
	aralarda yumuşak geçiş yapar. keys = { {t=0, v=0}, {t=0.2, v=1}, ... } ]]
function Ease.track(t, keys)
	if #keys == 0 then
		return 0
	end
	if t <= keys[1].t then
		return keys[1].v
	end
	for i = 2, #keys do
		local a, b = keys[i - 1], keys[i]
		if t <= b.t then
			local f = Ease.smoothstep(Ease.segment(t, a.t, b.t))
			return Ease.lerp(a.v, b.v, f)
		end
	end
	return keys[#keys].v
end

return Ease
]=] },
	["shared/Anim/HumanoidPose"] = { class = "ModuleScript", source = [=[
--[[
	HumanoidPose — R15 karakterinin eklemlerini sunucudan, kodla sürmek.

	Roblox'ta bir karakterin hareketi normalde yayınlanmış Animation asset'leriyle
	oynar. Burada asset yok: Motor6D.Transform her karede yazılıyor. Bu, Animator
	sisteminin kullandığı mekanizmanın aynısı (C0 * Transform * C1^-1), yani
	kemik hiyerarşisi ve kemik uzunlukları korunur.

	Eksen dönüşümü (Rig -> Roblox karakteri):
		Rig: +x sağ, +y yukarı, +z İLERİ
		Roblox karakteri: +x sağ, +y yukarı, -z ileri (LookVector = -Z)
		Ayna dönüşümü olduğu için Euler işaretleri: (x, y, z) -> (-x, -y, +z)

	Bu modül yalnızca R15 karakterlerde çalışır (R6'da sessizce hiçbir şey yapmaz).
	Karakterin kendi Animate script'i de Transform yazdığı için görsel çakışma
	olabilir: Config.ANIM.poseHumanoid = false ile kapatılabilir.
]]

local HumanoidPose = {}

-- Motor6D adı -> Rig eklemi
local JOINTS = {
	{ motor = "Waist", joint = "spine" },
	{ motor = "Neck", joint = "neck" },
	{ motor = "LeftHip", joint = "hipL" },
	{ motor = "LeftKnee", joint = "kneeL" },
	{ motor = "LeftAnkle", joint = "ankleL" },
	{ motor = "RightHip", joint = "hipR" },
	{ motor = "RightKnee", joint = "kneeR" },
	{ motor = "RightAnkle", joint = "ankleR" },
	{ motor = "LeftShoulder", joint = "shoulderL" },
	{ motor = "LeftElbow", joint = "elbowL" },
	{ motor = "RightShoulder", joint = "shoulderR" },
	{ motor = "RightElbow", joint = "elbowR" },
}

-- karakter -> { {motor, joint} ... } (zayıf önbellek)
local cache = setmetatable({}, { __mode = "k" })

local function collect(character)
	local found = cache[character]
	if found then
		return found
	end
	found = {}
	for _, map in ipairs(JOINTS) do
		local motor = character:FindFirstChild(map.motor, true)
		if motor and motor:IsA("Motor6D") then
			found[#found + 1] = { motor = motor, joint = map.joint }
		end
	end
	cache[character] = found
	return found
end

--[[ Karakterin R15 eklemleri var mı? (yoksa sessizce false) ]]
function HumanoidPose.supported(character)
	if not character then
		return false
	end
	return #collect(character) >= 8
end

local function anglesFor(pose, jointName)
	local a = pose and pose[jointName]
	if not a then
		return nil
	end
	local x, y, z = a.x or 0, a.y or 0, a.z or 0
	if x == 0 and y == 0 and z == 0 then
		return nil
	end
	return -x, -y, z
end

--[[ Pozu uygular. pose = KickAnim:sample(t).pose (veya nil = dinlenme) ]]
function HumanoidPose.apply(character, pose)
	local joints = collect(character)
	if #joints == 0 then
		return false
	end
	for _, entry in ipairs(joints) do
		local x, y, z = anglesFor(pose, entry.joint)
		if x then
			entry.motor.Transform = CFrame.Angles(x, y, z)
		else
			entry.motor.Transform = CFrame.new()
		end
	end
	return true
end

--[[ Karakteri motorun kendi animasyonuna bırakır ]]
function HumanoidPose.clear(character)
	local joints = collect(character)
	for _, entry in ipairs(joints) do
		entry.motor.Transform = CFrame.new()
	end
	cache[character] = nil
end

HumanoidPose.JOINTS = JOINTS

return HumanoidPose
]=] },
	["shared/Anim/KeeperAnim"] = { class = "ModuleScript", source = [=[
--[[
	KeeperAnim — topa göre değişen adaptif kaleci hareketi.

	Kaleci "hangi topa nasıl atlayacağını" kendisi seçer; poz her kurtarışta
	topun tahmini varış noktasından yeniden üretilir:

	  |dz| < 0.5 m ve alçak  -> "block" : ayakta kalır, kollar öne, dizler kırık
	  yüksek top (>1.45 m)   -> "jump"  : zıplar, kollar yukarı, bacaklar toplanır
	  yana uzak top          -> "dive"  : gövde yana devrilir, kollar o tarafa uzanır
	  yan + yüksek           -> "jumpDive": zıplayarak yana uzanır

	Uzanma miktarı topun ne kadar uzağa gideceğine bağlı (0.35-1.0 m). Bu öteleme
	sunucuda KALECİNİN FİZİKSEL GÖVDESİNE de uygulanır; yani dalış yapan kaleci
	gerçekten daha uzağa uzanır (görsel ile fizik ayrışmaz).

	Zaman çizelgesi:
	  0.00-0.10  hazırlık (hafif çömelme, ters yöne ağırlık)
	  0.10-0.35  fırlama/uzanma
	  0.35-0.62  zirve (havada/zemin temas)
	  0.62-0.95  toparlanma

	sample(t) -> { pose = <poz>, contact = false }
	(KickAnim ile aynı sözleşme: her aksiyon animasyonu poz tablosu döndürür.)
]]

local Ease = require(script.Parent.Ease)
local Pose = require(script.Parent.Pose)
local Vec3 = require(script.Parent.Parent.Core.Vec3)

local KeeperAnim = {}
KeeperAnim.__index = KeeperAnim

KeeperAnim.DURATION = 0.95

local clamp01 = Ease.clamp01

--[[ opts:
	dz     : topun kaleciye göre yanal varış noktası (m, + = kaleci sağı)
	height : varış noktasındaki yükseklik (m)
	speed  : topun hızı (m/s) — sertlik/tepki ayarı
]]
function KeeperAnim.new(opts)
	opts = opts or {}
	local dz = opts.dz or 0
	local height = opts.height or 0.5
	local absDz = math.abs(dz)
	local dir = (dz >= 0) and 1 or -1
	local speed = opts.speed or 15

	local kind
	if height >= 1.45 and absDz < 0.55 then
		kind = "jump"
	elseif height >= 1.45 then
		kind = "jumpDive"
	elseif absDz < 0.5 then
		kind = "block"
	else
		kind = "dive"
	end

	-- Uzanma: ne kadar uzağa gidecekse o kadar uzanır (0.30-1.0 m)
	-- Yüksek topda daha az yana uzanır (el yerine göz/topu takip eder)
	local reach = math.max(0.30, math.min(1.0, absDz / 1.15))
	-- Hızlı topa daha sert/çabuk tepki
	local urgency = clamp01((speed - 10) / 20)

	return setmetatable({
		kind = kind,
		dz = dz,
		height = height,
		dir = dir,
		absDz = absDz,
		reach = reach,
		urgency = urgency,
	}, KeeperAnim)
end

function KeeperAnim:duration()
	return KeeperAnim.DURATION
end

--[[ Dalış yokken kaleci HEYKEL gibi durmasın: yavaş nefes + ağırlık salınımı.
     sample() gibi poz tablosu döndürür; sunucu her karede bunu uygular.
     t = saniye (sunucu saati). ]]
function KeeperAnim.idle(t)
	local pose = Pose.new()
	local breath = math.sin(t * 1.7) * 0.5 + 0.5 -- 0..1, ~3.7 s dönem
	local sway = math.sin(t * 0.9) -- yana ağırlık aktarımı
	pose.rootOffset = Vec3.new(sway * 0.06, -0.10 - 0.035 * breath, 0)
	pose.root = Pose.joint(0, 0, sway * 0.05)
	pose.spine = Pose.joint(0.16, sway * 0.06, 0)
	pose.neck = Pose.joint(-0.10, -sway * 0.08, 0)
	pose.shoulderL = Pose.joint(-1.10 - 0.06 * breath, 0, -0.35)
	pose.shoulderR = Pose.joint(-1.10 - 0.06 * breath, 0, 0.35)
	pose.elbowL = Pose.joint(-0.45, 0, 0)
	pose.elbowR = Pose.joint(-0.45, 0, 0)
	pose.hipL = Pose.joint(-0.35 - 0.06 * breath, 0, -0.10)
	pose.hipR = Pose.joint(-0.35 - 0.06 * breath, 0, 0.10)
	pose.kneeL = Pose.joint(0.70, 0, 0)
	pose.kneeR = Pose.joint(0.70, 0, 0)
	return pose
end

-- Uzanma eğrisi: daha yumuşak hazırlık, sert uzanma, yavaş toparlanma
local function extensionAt(t)
	return Ease.track(t, {
		{ t = 0.00, v = 0 },
		{ t = 0.08, v = -0.10 }, -- erken hafif çökme
		{ t = 0.16, v = 0.45 },  -- hızlı fırlama
		{ t = 0.38, v = 1 },     -- zirve
		{ t = 0.68, v = 0.75 },  -- hafif geri çekilme
		{ t = 0.95, v = 0 },
	})
end

function KeeperAnim:sample(t)
	local ext = extensionAt(t)
	local pose = Pose.new()
	local kind = self.kind
	local dir = self.dir
	local reach = self.reach

	-- Hazırlık: daha belirgin çömelme (enerji toplanışı)
	local crouch = Ease.track(t, {
		{ t = 0.00, v = 0 },
		{ t = 0.10, v = 0.14 },
		{ t = 0.25, v = 0.08 },
		{ t = 0.95, v = 0 },
	})

	if kind == "block" then
		-- Ayakta blok: dizler kırık, kollar öne, ağırlık merkezi alçak
		local guard = Ease.track(t, {
			{ t = 0.00, v = 0 },
			{ t = 0.14, v = 1 },
			{ t = 0.68, v = 1 },
			{ t = 0.95, v = 0 },
		})
		pose.rootOffset = Vec3.new(0, -0.18 * guard - 0.06 * crouch, 0)
		pose.spine = Pose.joint(0.20 * guard, -dir * 0.14 * guard, 0)
		pose.hipL = Pose.joint(-0.45 * guard, 0, -0.12 * guard)
		pose.hipR = Pose.joint(-0.45 * guard, 0, 0.12 * guard)
		pose.kneeL = Pose.joint(0.90 * guard, 0, 0)
		pose.kneeR = Pose.joint(0.90 * guard, 0, 0)
		pose.shoulderL = Pose.joint(-1.20 * guard, 0, -0.40 * guard)
		pose.shoulderR = Pose.joint(-1.20 * guard, 0, 0.40 * guard)
		pose.elbowL = Pose.joint(-0.50 * guard, 0, 0)
		pose.elbowR = Pose.joint(-0.50 * guard, 0, 0)
		pose.neck = Pose.joint(-0.12 * guard, 0, 0)
		return { pose = pose }
	end

	if kind == "jump" then
		-- Yüksek top: güçlü zıpla, kollar düz yukarı, bacaklar toplanır
		local air = Ease.track(t, {
			{ t = 0.00, v = 0 },
			{ t = 0.08, v = -0.10 },
			{ t = 0.30, v = 0.60 },
			{ t = 0.55, v = 0.45 },
			{ t = 0.95, v = 0 },
		})
		pose.rootOffset = Vec3.new(0, air, 0)
		pose.spine = Pose.joint(0.12, 0, 0)
		pose.hipL = Pose.joint(-0.60 * ext, 0, -0.10)
		pose.hipR = Pose.joint(-0.60 * ext, 0, 0.10)
		pose.kneeL = Pose.joint(1.10 * math.abs(ext), 0, 0)
		pose.kneeR = Pose.joint(1.10 * math.abs(ext), 0, 0)
		-- Kollar düz yukarı (negatif shoulder.x)
		pose.shoulderL = Pose.joint(-2.60 * ext, 0, -0.20)
		pose.shoulderR = Pose.joint(-2.60 * ext, 0, 0.20)
		pose.elbowL = Pose.joint(-0.20, 0, 0)
		pose.elbowR = Pose.joint(-0.20, 0, 0)
		pose.neck = Pose.joint(-0.30 * ext, 0, 0)
		return { pose = pose }
	end

	-- Yana dalış (dive / jumpDive)
	local isJump = kind == "jumpDive"
	local lateral = dir * reach * ext
	local vertical
	if isJump then
		-- Zıplamalı dalış: daha yüksek, daha geniş uzanma
		vertical = math.max(0, Ease.track(t, {
			{ t = 0.00, v = 0 },
			{ t = 0.08, v = -0.08 },
			{ t = 0.30, v = 0.52 },
			{ t = 0.55, v = 0.35 },
			{ t = 0.95, v = 0 },
		}))
	else
		-- Alçak/düz dalış: gövde daha çok yere doğru
		vertical = -0.35 * math.max(0, ext)
	end

	pose.rootOffset = Vec3.new(lateral, vertical - 0.10 * crouch, 0)

	-- Gövde daha çok devrilir (daha geniş dalış görünümü)
	pose.root = Pose.joint(0, 0, -dir * (isJump and 0.65 or 1.15) * math.max(0, ext))
	pose.spine = Pose.joint(0.14, -dir * 0.30 * ext, -dir * 0.25 * ext)
	pose.neck = Pose.joint(-0.20 * ext, dir * 0.40 * ext, 0)

	-- Kollar: top yüksekliğine göre daha hassas
	-- Alçak top: yana yatay. Yüksek top: neredeyse düz yukarı.
	local aimUp = clamp01((self.height - 0.9) / 1.0)
	local armUp = (isJump and 2.30 or 2.05) + 0.95 * aimUp
	pose.shoulderL = Pose.joint(-0.45 * ext, 0, dir * (armUp + 0.12) * ext)
	pose.shoulderR = Pose.joint(-0.45 * ext, 0, dir * (armUp + 0.12) * ext)
	pose.elbowL = Pose.joint(-0.20 * ext, 0, 0)
	pose.elbowR = Pose.joint(-0.12 * ext, 0, 0)

	-- Bacaklar: dalış yönünün tersine daha çok uzanır (denge)
	pose.hipL = Pose.joint(-0.30 * ext, 0, -dir * 0.35 * ext)
	pose.hipR = Pose.joint(-0.50 * ext, 0, -dir * 0.18 * ext)
	pose.kneeL = Pose.joint(0.70 * ext, 0, 0)
	pose.kneeR = Pose.joint(0.40 * ext, 0, 0)

	return { pose = pose }
end

return KeeperAnim
]=] },
	["shared/Anim/KickAnim"] = { class = "ModuleScript", source = [=[
--[[
	KickAnim — TOPA GÖRE DEĞİŞEN adaptif şut hareketi.

	Yayınlanmış animasyon yok: poz, topun oyuncuya göre konumundan ve şut gücünden
	her seferinde yeniden hesaplanıyor.

	Top nerede?
	  * yerde (0-0.4 m)     -> "sürükleyici" düz vuruş; ayak kalça hizasından geçer
	  * bel/bacak (0.4-1.2) -> yarım vole; savurma düzlemi yükselir, gövde geriye yatar
	  * göğüs/üstü (>1.2)   -> vole; ayak göğüs hizasına kadar çıkar, gövde iyice yatar
	  * yanda (lateral)     -> o tarafın ayağı, kalça abduksiyonu ile uzanır
	  * güç (charge)        -> savurma genliği ve takip (follow-through) yüksekliği

	Zaman çizelgesi (saniye):
		0.00-0.13  hazırlık: arka ayak geriye, diz kırılır, gövde ters döner
		0.13-0.24  savurma: kalça öne fırlar, diz kontakt anında düzleşir
		0.24       TEMAS (top bu anda ayrılır)
		0.24-0.40  takip: bacak yukarıda kalır, gövde döner
		0.40-0.62  toparlanma: başlangıç pozisyonuna dönüş

	Ölçü birimi radyan; işaretler Rig'in yerel çerçevesine göre:
		+hip.x  bacağı GERİYE savurur (pozitif dönüş -Y'yi -Z'ye götürür)
]]

local Ease = require(script.Parent.Ease)
local Pose = require(script.Parent.Pose)
local Vec3 = require(script.Parent.Parent.Core.Vec3)
local Config = require(script.Parent.Parent.Config)

local KickAnim = {}
KickAnim.__index = KickAnim

KickAnim.DURATION = 0.62
KickAnim.CONTACT_TIME = 0.24

local clamp01 = Ease.clamp01

--[[ opts:
	ballHeight  : topun yerden yüksekliği (m)
	ballLateral : topun oyuncunun sağına (+) / soluna (-) uzaklığı (m)
	ballForward : topun önde (+) / arkada (-) olması (m)
	charge      : 0..1 şut gücü
	foot        : "L" | "R" (verilmezse topun yanına göre seçilir)
	shotType    : "place" | "instep" | "drive" | "outside" (verilmezse "instep")
]]
function KickAnim.new(opts)
	opts = opts or {}

	local SHOT = Config.SHOT

	local charge = clamp01(opts.charge or 0.7)
	local height = math.max(0, opts.ballHeight or 0.11)
	local lateral = opts.ballLateral or 0
	local forward = opts.ballForward or 0.8

	local foot = opts.foot
	if not foot then
		foot = (lateral >= 0) and "R" or "L"
	end

	local shotType = opts.shotType or "instep"
	local sp = SHOT.types and SHOT[shotType] or SHOT.instep

	-- Yüksek top -> vole: savurma düzlemi yükselir
	local tall = clamp01((height - 0.45) / 1.1)
	-- Genlik: güç + vuruş türü baz çarpanı
	local amp = (0.82 + 0.42 * charge) * sp.power
	-- Yana uzanma (kalça abduksiyonu)
	local reach = math.max(-1, math.min(1, lateral / 0.55))
	-- Top çok gerideyse daha kısa, daha kontrollü vuruş
	local behind = math.max(-1, math.min(0, forward / 0.6))

	-- Elle seçilen mi? (otomatikse topun yanına göre ayak seçilmiş olur)
	local manualFoot = opts.foot ~= nil

	return setmetatable({
		charge = charge,
		height = height,
		lateral = lateral,
		forward = forward,
		foot = foot,
		otherFoot = foot == "R" and "L" or "R",
		shotType = shotType,
		sp = sp,
		manualFoot = manualFoot,
		tall = tall,
		amp = amp,
		reach = reach,
		behind = behind,
	}, KickAnim)
end

function KickAnim:duration()
	return KickAnim.DURATION
end

function KickAnim:contactTime()
	return KickAnim.CONTACT_TIME
end

--[[ Verilen an için poz ü retir. Dönüş: { pose = <poz>, contact = bool } ]]
function KickAnim:sample(t)
	local amp = self.amp
	local tall = self.tall
	local reach = self.reach
	local contact = t >= KickAnim.CONTACT_TIME
	local sp = self.sp

	-- Yüksek topta bacak daha yukarı çıkar (negatif hip = öne)
	-- Yüksek top: kalça daha çok bükülür, savurma düzlemi yükselir
	local swingHigh = 0.55 + 1.35 * tall
	local backAngle = 0.90 * amp
	local contactAngle = -(swingHigh * amp)
	-- Takip yüksekliği vuruş türüne göre (drive yüksek, place kısa)
	local followAngle = -((swingHigh + 0.50) * amp) * sp.followY

	-- Hip: daha yumuşak hazırlık, sert savurma, geniş takip
	local hipX = Ease.track(t, {
		{ t = 0.00, v = 0 },
		{ t = 0.10, v = backAngle * 0.6 }, -- erken hafif geri
		{ t = 0.16, v = backAngle },       -- tam geri (maksimum gevşeme)
		{ t = 0.24, v = contactAngle },    -- temas: kalça önde, bacak uzanır
		{ t = 0.38, v = followAngle },     -- takip: bacak yukarıda
		{ t = 0.62, v = 0 },
	})

	local kneeX = Ease.track(t, {
		{ t = 0.00, v = 0.08 },
		{ t = 0.13, v = 1.30 * amp },      -- güçlü diz kırılma
		{ t = 0.24, v = 0.10 + 0.12 * tall }, -- temas anında düz
		{ t = 0.40, v = 0.65 },            -- takip: diz yüksek
		{ t = 0.62, v = 0.08 },
	})

	-- Temas anında ayak bileği: vuruş türüne göre (drive sıkı kilit, place açık)
	local ankleContact = (0.35 + 0.15 * tall) * sp.ankleMult
	local ankleX = Ease.track(t, {
		{ t = 0.00, v = 0.10 },
		{ t = 0.13, v = -0.30 },
		{ t = 0.24, v = ankleContact },
		{ t = 0.40, v = 0.10 },
		{ t = 0.62, v = 0.10 },
	})

	-- Destek bacağı: yüksek topta daha çok kırılır, ağırlık merkezi alçak
	local supportHip = -(0.12 + 0.28 * tall)
	local supportKnee = 0.20 + 0.42 * tall + 0.18 * math.abs(reach)

	-- Gövde: savurmada ters, temasta öne, yüksek topta güçlü geriye
	-- outside (trivela): gövde hafif geri (bodyLeanBack), az ileri eğim
	local spineLeanMult = sp.bodyLeanBack and 0.6 or 1.0
	local spineY = Ease.track(t, {
		{ t = 0.00, v = 0 },
		{ t = 0.13, v = 0.38 * amp },
		{ t = 0.24, v = -0.34 * amp * spineLeanMult },
		{ t = 0.40, v = -0.48 * amp * spineLeanMult },
		{ t = 0.62, v = 0 },
	})
	-- Gövde ileri eğimi vuruş türüne göre (drive çok öne, place daha dik)
	local spineX = (0.12 + 0.50 * tall) * sp.spineXMult
	local spineZ = -0.25 * reach

	-- Kollar: karşı kol daha çok açılır (denge), vuran kol daha sığ
	local shoulderSwing = Ease.track(t, {
		{ t = 0.00, v = 0 },
		{ t = 0.13, v = -0.50 },
		{ t = 0.24, v = 0.60 },
		{ t = 0.40, v = 0.75 },
		{ t = 0.62, v = 0 },
	})

	-- Gövde salınımı: temas anında hafif Titreşim (realistik)
	local bob = Ease.track(t, {
		{ t = 0.00, v = 0 },
		{ t = 0.13, v = -0.050 },
		{ t = 0.28, v = -0.020 },
		{ t = 0.62, v = 0 },
	})

	local pose = Pose.new()
	pose.rootOffset = Vec3.new(0, bob, 0)

	-- Gövde ve baş
	pose.spine = Pose.joint(spineX, spineY, spineZ)
	pose.neck = Pose.joint(0.12 + 0.12 * (1 - tall), -spineY * 0.5, 0)
	pose.head = Pose.joint(0.06, 0, 0)

	-- Kalça abduksiyonu (hipZ): vuruş türüne ve ayak yönüne göre
	-- place: geniş abduksiyon (iç ayakla vurmak için kalça dışa), outside: ters abduksiyon
	-- Elle seçilen ayakta yön o ayağın dışına doğru; otomatikte topun yanına doğru.
	local hipZDir, hipZMag
	if self.foot == "R" then
		hipZDir = 1
	else
		hipZDir = -1
	end
	if self.shotType == "outside" then
		hipZDir = -hipZDir -- ayak dışı vuruşunda kalça ters yönlü açılır
	end
	if self.manualFoot then
		hipZMag = self.charge -- elle seçilmişse güçle arttır
	else
		hipZMag = math.abs(self.reach) -- otomatikse topun yanına göre
	end
	local hipZ = hipZDir * hipZMag * 0.25 * sp.hipZMult

	-- Vuran bacak: daha geniş kalça açısı, topa göre hizalı
	local kickHip = pose["hip" .. self.foot]
	kickHip = Pose.joint(hipX, 0.14 * self.reach, hipZ)
	pose["hip" .. self.foot] = kickHip
	pose["knee" .. self.foot] = Pose.joint(kneeX, 0, 0)
	pose["ankle" .. self.foot] = Pose.joint(ankleX, 0, 0)

	-- Destek bacağı: ağırlık merkezi dengeleme
	pose["hip" .. self.otherFoot] = Pose.joint(supportHip, 0, 0)
	pose["knee" .. self.otherFoot] = Pose.joint(supportKnee, 0, 0)
	pose["ankle" .. self.otherFoot] = Pose.joint(-0.14 - 0.25 * tall, 0, 0)

	-- Kollar: karşı kol güçlü denge, vuran kol sığ takip
	local otherArm = (self.foot == "R") and "L" or "R"
	local kickArm = (self.foot == "R") and "R" or "L"
	pose["shoulder" .. otherArm] = Pose.joint(-0.28 + shoulderSwing, 0.18, 0.60 + 0.30 * tall)
	pose["elbow" .. otherArm] = Pose.joint(-0.40 - 0.25 * math.abs(shoulderSwing), 0, 0)
	pose["shoulder" .. kickArm] = Pose.joint(0.35 - shoulderSwing * 0.75, 0, -0.32)
	pose["elbow" .. kickArm] = Pose.joint(-0.50, 0, 0)

	return { pose = pose, contact = contact }
end

return KickAnim
]=] },
	["shared/Anim/PartRig"] = { class = "ModuleScript", source = [=[
--[[
	PartRig — prosedürel iskeleti gerçek Roblox parçalarına çevirir.

	Kaleci (ve gerektiğinde herhangi bir NPC) için tek bir model asset'i
	kullanılmaz: 13 parça `Instance.new("Part")` ile kodla üretilir, her karede
	sunucuda FK ile konumlandırılır. Motor6D / Animation / asset ID YOKTUR.
	Parçalar Anchored olduğu için CFrame yazmak yeterli; istemciye sadece
	parçaların CFrame'i replike olur.

	Yerleşim (Rig.toWorld):
		rig +x -> oyuncunun SAĞI
		rig +y -> yukarı
		rig +z -> oyuncunun İLERİSİ (baktığı yön)

	Aynı iskelet (Rig.luau) hem ölçüm testlerinde hem görselde kullanıldığı için
	"görünen" hareket ile "hesaplanan" hareket birebir aynıdır.
]]

local Rig = require(script.Parent.Rig)
local Vec3 = require(script.Parent.Parent.Core.Vec3)

local PartRig = {}

local KIT = Color3.fromRGB(250, 214, 60)
local KIT_DARK = Color3.fromRGB(30, 44, 66)
local SKIN = Color3.fromRGB(232, 190, 160)
local SOCK = Color3.fromRGB(240, 244, 250)
local BOOT = Color3.fromRGB(24, 24, 28)
local GLOVE = Color3.fromRGB(245, 245, 250)

-- bone -> görsel stil
local STYLE = {
	pelvis = { base = KIT_DARK, fat = 1.20, torso = true },
	torso = { base = KIT, fat = 1.10, torso = true },
	head = { base = SKIN, fat = 1.00, ball = true },
	upperArmL = { base = KIT, fat = 1.00 },
	forearmL = { base = SKIN, fat = 1.00 },
	upperArmR = { base = KIT, fat = 1.00 },
	forearmR = { base = SKIN, fat = 1.00 },
	thighL = { base = KIT_DARK, fat = 1.10 },
	shinL = { base = SOCK, fat = 1.00 },
	thighR = { base = KIT_DARK, fat = 1.10 },
	shinR = { base = SOCK, fat = 1.00 },
	footL = { base = BOOT, fat = 1.00 },
	footR = { base = BOOT, fat = 1.00 },
}

local function makePart(parent, name, size, color, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.CFrame = CFrame.new(0, 0, 0)
	p.Parent = parent
	return p
end

local function bonePartName(boneName)
	return boneName:sub(1, 1):upper() .. boneName:sub(2)
end

--[[ Model kur.
	parent: Folder | Model | Workspace
	opts = { name, studsPerMeter, kitColor }
	Dönüş: { folder, parts = {bone -> Part}, gloves = {L, R}, studsPerMeter } ]]
function PartRig.build(parent, opts)
	opts = opts or {}
	local s = opts.studsPerMeter or 1
	local kitColor = opts.kitColor or KIT
	local lengths = Rig.boneLengths()

	local folder = Instance.new("Folder")
	folder.Name = opts.name or "Rig"
	folder.Parent = parent

	local parts = {}
	for _, bone in ipairs(Rig.bones) do
		local style = STYLE[bone.name] or { base = kitColor, fat = 1 }
		local thickness = bone.radius * 2 * (style.fat or 1)
		local len = lengths[bone.name] or 0.3
		local color = style.base
		if style.torso or bone.name:find("Arm") == 1 then
			color = kitColor
			if bone.name == "pelvis" then
				color = KIT_DARK
			end
		end
		parts[bone.name] = makePart(
			folder,
			bonePartName(bone.name),
			Vector3.new(thickness * s, thickness * s, len * s),
			color,
			style.ball and Enum.PartType.Ball or nil
		)
	end

	local gloves = {}
	for _, side in ipairs({ "L", "R" }) do
		gloves[side] = makePart(
			folder,
			"Glove" .. side,
			Vector3.new(0.16 * s, 0.16 * s, 0.16 * s),
			GLOVE,
			Enum.PartType.Ball
		)
	end

	return {
		folder = folder,
		parts = parts,
		gloves = gloves,
		studsPerMeter = s,
		lengths = lengths,
	}
end

--[[ Modeli poza göre konumlandırır.
	pose   : Rig.solve'un beklediği tablo (KickAnim / KeeperAnim çıktısı)
	origin : ayakların bastığı dünya noktası (STUD, Vector3) veya metre Vec3 + s
	yaw    : modelin baktığı yön (Vec3.yaw ölçeği: +x'ten +z'ye)
	s      : stud/metre ]]
function PartRig.apply(model, pose, origin, yaw, studsPerMeter)
	if not model then
		return
	end
	local s = studsPerMeter or model.studsPerMeter or 1
	local solved = Rig.solve(pose)

	local function toStuds(point)
		return Rig.toWorld(point, origin, yaw, s)
	end

	for _, bone in ipairs(Rig.bones) do
		local part = model.parts[bone.name]
		if part then
			local a = toStuds(solved.pos[bone.a])
			local b = toStuds(solved.pos[bone.b])
			local mid = Vec3.lerp(a, b, 0.5)
			local style = STYLE[bone.name]
			if style and style.ball then
				-- Kafa: kemik ortası değil, eklemden yukarı doğru yarım çap
				local dir = Vec3.unit(Vec3.sub(b, a))
				local center = Vec3.add(a, Vec3.scale(dir, bone.radius * 0.55))
				part.CFrame = CFrame.new(center.x, center.y, center.z)
			else
				local dir = Vec3.sub(b, a)
				if Vec3.length(dir) < 1e-6 then
					part.CFrame = CFrame.new(mid.x, mid.y, mid.z)
				else
					part.CFrame = CFrame.new(Vector3.new(mid.x, mid.y, mid.z), Vector3.new(b.x, b.y, b.z))
				end
			end
		end
	end

	-- Eldivenler: el eklemlerinin olduğu yerde
	for _, side in ipairs({ "L", "R" }) do
		local glove = model.gloves and model.gloves[side]
		local hand = solved.pos["hand" .. side]
		if glove and hand then
			local w = toStuds(hand)
			local wrist = toStuds(solved.pos["elbow" .. side])
			local dir = Vec3.unit(Vec3.sub(w, wrist))
			local center = Vec3.add(w, Vec3.scale(dir, 0.06))
			glove.CFrame = CFrame.new(center.x, center.y, center.z)
		end
	end

	return solved
end

return PartRig
]=] },
	["shared/Anim/PlayerPose"] = { class = "ModuleScript", source = [=[
--[[
	PlayerPose — SAHADA OYNAYAN OYUNCUNUN prosedürel hareket animasyonu.

	Neden var: şut pozunu (KickAnim) sunucu yalnızca vuruş beklerken uyguluyordu;
	geri kalan zamanda karakter ya Roblox'un varsayılan Animator'üne kalıyor ya da
	donmuş görünüyordu. Kullanıcı bunu "oyuncu animasyonları çalışmıyor" diye
	yaşıyordu. Bu modül her karede pozlanacak bir tablo verir.

	İki kaynak:
	  WalkCycle.sample(hız, faz, zaman) — koşu/duruş döngüsünün kendisi (fiziksel
	    adım uzunluğuna bağlı, kayma yok). Bu modül onu SARAR: zamanı hıza göre
	    faza çevirir, böylece çağıran tarafın adım uzunluğuyla uğraşması gerekmez.
	  ready — dururken atletik bekleyiş (WalkCycle'ın duruş dalı).

	Kullanım (istemci, kendi karakteri — en güvenilir yol, ağ sahipliği istemcide):
		HumanoidPose.apply(hrp.Parent, PlayerPose.walk(t, hiz))
	Kullanım (sunucu, kendi kontrolündeki karakterler):
		HumanoidPose.apply(model, PlayerPose.walk(t, hiz))

	Poz sözleşmesi KeeperAnim/KickAnim/WalkCycle ile aynıdır:
	{ eklemAdı = { x = , y = , z = }, rootOffset = Vec3 }  (Rig uzayı, +z ileri;
	 Roblox karakterine aynalamayı HumanoidPose yapar.)
]]

local WalkCycle = require(script.Parent.WalkCycle)

local PlayerPose = {}

-- Tam salınım genliğine ulaşan hız (m/s). WalkCycle içerde speed/7.6 ile
-- ölçekler; bu sabit yalnızca dışarıya "koşu ne zaman tam koşu olur" bilgisini
-- vermek ve testlerin eşiğini tek yerden okuması için tutulur.
PlayerPose.FULL_STRIDE_SPEED = 7.6

--[[ Hız -> salınım oranı (0..1). Dururken 0, FULL_STRIDE_SPEED'de 1.
     speed : m/s (işaretli olabilir; büyüklüğü kullanılır) ]]
function PlayerPose.strideAmp(speed)
	local s = math.abs(speed or 0)
	if s <= 0 then
		return 0
	end
	if s >= PlayerPose.FULL_STRIDE_SPEED then
		return 1
	end
	return s / PlayerPose.FULL_STRIDE_SPEED
end

--[[ Zamandan adım fazı üretir (0..1, döner). Faz MESAFEYE bağlıdır: hızlı
     koşan oyuncu adımlarını sıklaştırır, yavaş yürüyen seyreltir — böylece
     ayaklar yerde kaymaz.
     t     : saniye (kesintili olmasın diye sürekli bir saat verilmeli)
     speed : m/s ]]
function PlayerPose.phaseAt(t, speed)
	local s = math.max(0, speed or 0)
	if s <= 0 then
		return 0
	end
	local traveled = (t or 0) * s -- metre
	-- WalkCycle.STRIDE metre = bir tam döngü
	return (traveled / WalkCycle.STRIDE) % 1
end

--[[ Yürüyüş/koşu pozunu üret. Hız ~0 ise duruşa döner (WalkCycle'ın duruş dalı).
     t     : saniye
     speed : m/s
     Dönüş : poz tablosu ]]
function PlayerPose.walk(t, speed)
	local time = t or 0
	local s = math.max(0, speed or 0)
	return WalkCycle.sample(s, PlayerPose.phaseAt(time, s), time)
end

--[[ Duruş pozunu üret (atletik bekleyiş + nefes). Hız verilirse ve yürüyüş
     eşiğini geçiyorsa walk'a düşer: çağıran tarafın "duruyor mu" diye
     düşünmesi gerekmez.
     t     : saniye (nefes fazı)
     speed : m/s (isteğe bağlı) ]]
function PlayerPose.ready(t, speed)
	if PlayerPose.strideAmp(speed) > 0.05 then
		return PlayerPose.walk(t, speed)
	end
	return WalkCycle.sample(0, 0, t or 0)
end

return PlayerPose
]=] },
	["shared/Anim/Pose"] = { class = "ModuleScript", source = [=[
--[[
	Pose — eklem açılarının (radyan) aritmetiği.

	Bir poz: { jointName = {x=, y=, z=}, rootOffset = Vec3 }
	Animasyonlar poz üretir, motor bunları karıştırır (yürüme + şut gibi).
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)

local Pose = {}

function Pose.new()
	return { rootOffset = Vec3.new(0, 0, 0) }
end

local function jointOf(pose, name)
	local j = pose[name]
	if not j then
		j = { x = 0, y = 0, z = 0 }
		pose[name] = j
	end
	return j
end

-- a'ya b'yi ekler (açılar toplanır, öteler vektörel toplanır)
function Pose.add(a, b)
	local out = {}
	for name, j in pairs(a) do
		if name ~= "rootOffset" then
			out[name] = { x = j.x or 0, y = j.y or 0, z = j.z or 0 }
		end
	end
	for name, j in pairs(b) do
		if name ~= "rootOffset" then
			local target = jointOf(out, name)
			target.x = target.x + (j.x or 0)
			target.y = target.y + (j.y or 0)
			target.z = target.z + (j.z or 0)
		end
	end
	local ao = a.rootOffset or Vec3.ZERO
	local bo = b.rootOffset or Vec3.ZERO
	out.rootOffset = Vec3.add(ao, bo)
	return out
end

-- a'dan b'ye t oranında geçiş
function Pose.blend(a, b, t)
	local out = {}
	local names = {}
	for name in pairs(a) do
		if name ~= "rootOffset" then
			names[name] = true
		end
	end
	for name in pairs(b) do
		if name ~= "rootOffset" then
			names[name] = true
		end
	end
	for name in pairs(names) do
		local ja = a[name] or { x = 0, y = 0, z = 0 }
		local jb = b[name] or { x = 0, y = 0, z = 0 }
		out[name] = {
			x = (ja.x or 0) + ((jb.x or 0) - (ja.x or 0)) * t,
			y = (ja.y or 0) + ((jb.y or 0) - (ja.y or 0)) * t,
			z = (ja.z or 0) + ((jb.z or 0) - (ja.z or 0)) * t,
		}
	end
	out.rootOffset = Vec3.lerp(a.rootOffset or Vec3.ZERO, b.rootOffset or Vec3.ZERO, t)
	return out
end

-- Değerleri k ile çarpar (şiddet ölçekleme)
function Pose.scale(a, k)
	local out = {}
	for name, j in pairs(a) do
		if name ~= "rootOffset" then
			out[name] = { x = (j.x or 0) * k, y = (j.y or 0) * k, z = (j.z or 0) * k }
		end
	end
	out.rootOffset = Vec3.scale(a.rootOffset or Vec3.ZERO, k)
	return out
end

-- Tek eklem için küçük yardımcı
function Pose.joint(x, y, z)
	return { x = x or 0, y = y or 0, z = z or 0 }
end

return Pose
]=] },
	["shared/Anim/Rig"] = { class = "ModuleScript", source = [=[
--[[
	Rig — prosedürel iskelet ve ileri kinematik (FK).

	Neden? Roblox'ta animasyon normalde yayınlanmış bir Animation asset'i (ID) ile
	oynatılır. Biz asset YAYINLAMIYORUZ: iskelet tamamen kodla, sunucuda çözülüyor.
	Böylece poz, topun konumuna/hızına göre milimetre düzeyinde değiştirilebiliyor.

	Yerel koordinat sistemi (sağ el):
		+x : sağ
		+y : yukarı
		+z : ileri (oyuncunun baktığı yön)
		Tüm ölçüler metre. Köken (0,0,0) = ayakların yere bastığı nokta.

	FK: her eklem, ebeveynine göre bir ofset ve bir Euler dönüşü taşır.
		worldRot[j] = worldRot[parent] * localRot[j]
		pos[j]      = pos[parent] + worldRot[parent] * offset[j]

	Dönüş matrisi 3 eksen vektörüyle temsil edilir (kolonlar = yerel eksenlerin
	görüntüsü). Böylece Lua'da determinant/tuhaflık derdi olmadan çarpım yapılır.

	Rig.solve(pose) -> { pos = {eklem -> Vec3}, bones = { {a, b, radius, name} } }

	Bu modül Roblox API'si kullanmaz: animasyonlar testte ölçülebilir.
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)

local Rig = {}

local cos, sin = math.cos, math.sin

-- ---------------------------------------------------------------- matrisler
local IDENTITY = {
	x = Vec3.new(1, 0, 0),
	y = Vec3.new(0, 1, 0),
	z = Vec3.new(0, 0, 1),
}

local function matVec(m, v)
	return Vec3.new(
		m.x.x * v.x + m.y.x * v.y + m.z.x * v.z,
		m.x.y * v.x + m.y.y * v.y + m.z.y * v.z,
		m.x.z * v.x + m.y.z * v.y + m.z.z * v.z
	)
end

local function matMul(a, b)
	return {
		x = matVec(a, b.x),
		y = matVec(a, b.y),
		z = matVec(a, b.z),
	}
end

local function rotX(a)
	local c, s = cos(a), sin(a)
	return { x = Vec3.new(1, 0, 0), y = Vec3.new(0, c, s), z = Vec3.new(0, -s, c) }
end

local function rotY(a)
	local c, s = cos(a), sin(a)
	return { x = Vec3.new(c, 0, -s), y = Vec3.new(0, 1, 0), z = Vec3.new(s, 0, c) }
end

local function rotZ(a)
	local c, s = cos(a), sin(a)
	return { x = Vec3.new(c, s, 0), y = Vec3.new(-s, c, 0), z = Vec3.new(0, 0, 1) }
end

-- Euler: önce Z (roll), sonra Y (yaw), en son X (pitch) uygulanır.
function Rig.matFromEuler(angles)
	if not angles
		or ((angles.x or 0) == 0 and (angles.y or 0) == 0 and (angles.z or 0) == 0)
	then
		return IDENTITY
	end
	local m = IDENTITY
	if angles.z and angles.z ~= 0 then
		m = matMul(m, rotZ(angles.z))
	end
	if angles.y and angles.y ~= 0 then
		m = matMul(m, rotY(angles.y))
	end
	if angles.x and angles.x ~= 0 then
		m = matMul(m, rotX(angles.x))
	end
	return m
end

Rig.matVec = matVec
Rig.matMul = matMul

-- --------------------------------------------------------------- iskelet
-- parent = ebeveyn eklem, offset = ebeveyne göre konum (metre)
Rig.joints = {
	{ name = "root", parent = nil, offset = Vec3.new(0, 1.00, 0) },
	{ name = "spine", parent = "root", offset = Vec3.new(0, 0.14, 0) },
	{ name = "neck", parent = "spine", offset = Vec3.new(0, 0.30, 0) },
	{ name = "head", parent = "neck", offset = Vec3.new(0, 0.12, 0) },

	{ name = "shoulderL", parent = "spine", offset = Vec3.new(-0.20, 0.24, 0) },
	{ name = "elbowL", parent = "shoulderL", offset = Vec3.new(0, -0.28, 0) },
	{ name = "handL", parent = "elbowL", offset = Vec3.new(0, -0.26, 0) },

	{ name = "shoulderR", parent = "spine", offset = Vec3.new(0.20, 0.24, 0) },
	{ name = "elbowR", parent = "shoulderR", offset = Vec3.new(0, -0.28, 0) },
	{ name = "handR", parent = "elbowR", offset = Vec3.new(0, -0.26, 0) },

	{ name = "hipL", parent = "root", offset = Vec3.new(-0.11, -0.05, 0) },
	{ name = "kneeL", parent = "hipL", offset = Vec3.new(0, -0.45, 0) },
	{ name = "ankleL", parent = "kneeL", offset = Vec3.new(0, -0.44, 0) },
	{ name = "toeL", parent = "ankleL", offset = Vec3.new(0, -0.06, 0.13) },

	{ name = "hipR", parent = "root", offset = Vec3.new(0.11, -0.05, 0) },
	{ name = "kneeR", parent = "hipR", offset = Vec3.new(0, -0.45, 0) },
	{ name = "ankleR", parent = "kneeR", offset = Vec3.new(0, -0.44, 0) },
	{ name = "toeR", parent = "ankleR", offset = Vec3.new(0, -0.06, 0.13) },
}

-- Görsel parçalar: iki eklem arasındaki segmentler
Rig.bones = {
	{ name = "pelvis", a = "root", b = "spine", radius = 0.13 },
	{ name = "torso", a = "spine", b = "neck", radius = 0.15 },
	{ name = "head", a = "neck", b = "head", radius = 0.11 },

	{ name = "upperArmL", a = "shoulderL", b = "elbowL", radius = 0.055 },
	{ name = "forearmL", a = "elbowL", b = "handL", radius = 0.048 },
	{ name = "upperArmR", a = "shoulderR", b = "elbowR", radius = 0.055 },
	{ name = "forearmR", a = "elbowR", b = "handR", radius = 0.048 },

	{ name = "thighL", a = "hipL", b = "kneeL", radius = 0.075 },
	{ name = "shinL", a = "kneeL", b = "ankleL", radius = 0.062 },
	{ name = "footL", a = "ankleL", b = "toeL", radius = 0.055 },
	{ name = "thighR", a = "hipR", b = "kneeR", radius = 0.075 },
	{ name = "shinR", a = "kneeR", b = "ankleR", radius = 0.062 },
	{ name = "footR", a = "ankleR", b = "toeR", radius = 0.055 },
}

-- --------------------------------------------------------------- çözüm
--[[ pose = {
	rootOffset = Vec3 (opsiyonel, tüm gövdeyi öteler),
	root = {x,y,z}, spine = {...}, hipL = {...}, ... (radyan)
} ]]
function Rig.solve(pose)
	pose = pose or {}
	local positions = {}
	local rotations = {}

	for _, joint in ipairs(Rig.joints) do
		local localRot = Rig.matFromEuler(pose[joint.name])
		if joint.parent then
			local parentRot = rotations[joint.parent]
			local parentPos = positions[joint.parent]
			rotations[joint.name] = matMul(parentRot, localRot)
			positions[joint.name] = Vec3.add(parentPos, matVec(parentRot, joint.offset))
		else
			rotations[joint.name] = localRot
			positions[joint.name] = Vec3.new(joint.offset.x, joint.offset.y, joint.offset.z)
		end
	end

	-- Tüm gövdeyi ötele (dalış, zıplama, düşme)
	local offset = pose.rootOffset
	if offset then
		for name, p in pairs(positions) do
			positions[name] = Vec3.add(p, offset)
		end
	end

	local bones = {}
	for _, bone in ipairs(Rig.bones) do
		bones[#bones + 1] = {
			name = bone.name,
			a = positions[bone.a],
			b = positions[bone.b],
			radius = bone.radius,
		}
	end

	return { pos = positions, bones = bones, rotations = rotations }
end

-- Dinlenme pozundaki kemik uzunlukları (görsel parça boyutları için)
local REST_POS = nil
function Rig.boneLengths()
	if not REST_POS then
		REST_POS = Rig.solve({}).pos
	end
	local out = {}
	for _, bone in ipairs(Rig.bones) do
		out[bone.name] = Vec3.distance(REST_POS[bone.a], REST_POS[bone.b])
	end
	return out
end

-- Yerel (rig) noktayı dünya uzayına çevirir.
-- origin: ayak noktası, yaw: baktığı yön (Vec3.yaw ile aynı ölçek)
function Rig.toWorld(localPoint, origin, yaw, studsPerMeter)
	local s = studsPerMeter or 1
	local forward = Vec3.new(cos(yaw), 0, sin(yaw))
	local up = Vec3.new(0, 1, 0)
	local right = Vec3.cross(forward, up) -- (cos,0,sin) x (0,1,0)

	local world = Vec3.add(origin, Vec3.new(
		(right.x * localPoint.x + up.x * localPoint.y + forward.x * localPoint.z) * s,
		(right.y * localPoint.x + up.y * localPoint.y + forward.y * localPoint.z) * s,
		(right.z * localPoint.x + up.z * localPoint.y + forward.z * localPoint.z) * s
	))
	return world, forward, right, up
end

return Rig
]=] },
	["shared/Anim/WalkCycle"] = { class = "ModuleScript", source = [=[
--[[
	WalkCycle — prosedürel koşu/yürüme döngüsü.

	Oyuncunun görsel iskeleti (rig) kodla sürüldüğü için yürüme animasyonu da
	kodla üretilir: kalça salınımı, diz kırılması, kol karşı salınımı ve gövde
	sekmesi. Adım uzunluğu gerçek mesafeye bağlıdır -> kayma (foot sliding) olmaz.

	faz = kat edilen mesafe / adım döngüsü uzunluğu  (0..1 arası döner)
]]

local Ease = require(script.Parent.Ease)
local Pose = require(script.Parent.Pose)
local Vec3 = require(script.Parent.Parent.Core.Vec3)

local WalkCycle = {}

WalkCycle.STRIDE = 1.9 -- bir tam döngüde kat edilen mesafe (m)

--[[ speed: m/s, phase: 0..1, time: saniye (dururken nefes için) ]]
function WalkCycle.sample(speed, phase, time)
	local pose = Pose.new()
	local amp = Ease.clamp01(speed / 7.6)
	local ph = (phase or 0) * math.pi * 2
	local s = math.sin(ph)
	local c = math.cos(ph)

	if amp < 0.05 then
		-- Duruyor: atletik bekleyiş + nefes. Eskiden bu dal neredeyse kimlikle
		-- aynıydı (knee 0.06, rootOffset -0.005) -> karakter sahada HEYKEL
		-- gibi duruyordu. Dizler kırık, gövde hafif öne, kollar açık: kaleci
		-- karşısındaki oyuncunun bekleyişi.
		local breath = math.sin((time or 0) * 1.8) * 0.5 + 0.5
		pose.spine = Pose.joint(0.10 + 0.03 * breath, 0, 0)
		pose.neck = Pose.joint(-0.07, 0, 0)
		pose.shoulderL = Pose.joint(0.04, 0, 0.26 + 0.03 * breath)
		pose.shoulderR = Pose.joint(0.04, 0, -0.26 - 0.03 * breath)
		pose.elbowL = Pose.joint(-0.40, 0, 0)
		pose.elbowR = Pose.joint(-0.40, 0, 0)
		pose.kneeL = Pose.joint(0.24 + 0.04 * breath, 0, 0)
		pose.kneeR = Pose.joint(0.24 + 0.04 * breath, 0, 0)
		pose.ankleL = Pose.joint(-0.14, 0, 0)
		pose.ankleR = Pose.joint(-0.14, 0, 0)
		pose.rootOffset = Vec3.new(0, -0.035 - 0.025 * breath, 0)
		return pose
	end

	-- Bacaklar: +hip.x geriye savurur
	pose.hipL = Pose.joint(0.62 * amp * s, 0, 0)
	pose.hipR = Pose.joint(-0.62 * amp * s, 0, 0)

	-- Diz: bacak geriye giderken kırılır (yerden kaldırma)
	local kneeL = 0.12 + 0.85 * amp * math.max(0, math.sin(ph + 1.2))
	local kneeR = 0.12 + 0.85 * amp * math.max(0, math.sin(ph + 1.2 + math.pi))
	pose.kneeL = Pose.joint(kneeL, 0, 0)
	pose.kneeR = Pose.joint(kneeR, 0, 0)

	-- Ayak bileği: topuk-parmak yuvarlanması
	pose.ankleL = Pose.joint(-0.15 * amp * c, 0, 0)
	pose.ankleR = Pose.joint(0.15 * amp * c, 0, 0)

	-- Kollar karşılıklı salınır
	pose.shoulderL = Pose.joint(-0.55 * amp * s, 0, 0.12)
	pose.shoulderR = Pose.joint(0.55 * amp * s, 0, -0.12)
	pose.elbowL = Pose.joint(-0.45 - 0.25 * amp * math.max(0, s), 0, 0)
	pose.elbowR = Pose.joint(-0.45 - 0.25 * amp * math.max(0, -s), 0, 0)

	-- Gövde: hafif öne eğik + salınım
	pose.spine = Pose.joint(0.06 + 0.10 * amp, 0.08 * amp * s, 0)
	pose.neck = Pose.joint(-0.05 * amp, 0, 0)

	-- Dikey sekme: her adımda iki kez
	pose.rootOffset = Vec3.new(0, -0.02 * amp * (0.5 + 0.5 * math.cos(2 * ph)), 0)

	return pose
end

return WalkCycle
]=] },
	["shared/Config"] = { class = "ModuleScript", source = [=[
--[[
	Config — motorun tüm ayar parametreleri.

	Birim sistemi: SI (metre, saniye, kilogram, radyan).
	Roblox sahnesi için STUD_PER_METER ile çevrim yapılır (1 stud ≈ 0.28 m).
	Böylece fizik "gerçek dünya" sayılarıyla çalışır; Roblox'un 20 stud'luk
	"dev" ölçeğine sıkışmayız.

	Değerler gerçek FIFA ölçüleri ve spor bilimi literatüründen alınmıştır:
	  saha 105 x 68 m, kale 7.32 x 2.44 m, top çapı 22 cm (0.43 kg), hava 1.225 kg/m³
]]

local Config = {}

Config.STUDS_PER_METER = 1 / 0.28 -- 3.5714 stud/metre

-- Simülasyon frekansı. 240 Hz: 25 m/s'lik bir şutta top adım başına ~10 cm ilerler,
-- yani yarıçapından (11 cm) az — tünel geçişi (tunneling) fiziksel olarak imkânsız.
Config.SIM_HZ = 240
Config.FIXED_DT = 1 / Config.SIM_HZ
Config.MAX_FRAME_DT = 0.25 -- tek karede işlenecek maksimum gerçek zaman (spiral ölüm koruması)
Config.MAX_SUBSTEPS = 60

Config.GRAVITY = 9.81

Config.AIR = {
	density = 1.225, -- kg/m³ (deniz seviyesi, 15 °C)
}

local BALL_RADIUS = 0.11 -- FIFA: çevre 68-70 cm -> yarıçap ~0.11 m
Config.BALL = {
	radius = BALL_RADIUS,
	mass = 0.43, -- kg (FIFA: 410-450 g)
	crossSection = math.pi * BALL_RADIUS * BALL_RADIUS, -- m²

	-- Hava direnci: a = -0.5 * rho * A * Cd * |v| * v / m
	-- Cd=0.25 türbülanslı akış rejimi (hızlı şut). Yavaş topta Cd 0.4-0.5'e çıkar;
	-- bu geçiş "drag crisis" olarak adlandırılır ve Knuckleball etkisinin kaynağıdır.
	dragCoefficient = 0.25,
	dragCoefficientSlow = 0.47,
	dragCrisisSpeed = 12, -- m/s: bu hızın altında Cd yavaş değere doğru geçer
	dragCrisisWidth = 6, -- m/s: geçişin yumuşaklığı

	-- Magnus (spin) kuvveti: F = 0.5 * rho * A * Cl * v² * (ω̂ × v̂)
	-- Cl (kaldırma katsayısı) spin oranı S = ω*r/v ile artar, doyuma ulaşır.
	magnusScale = 0.8, -- Cl = min(magnusMax, magnusScale * S)
	magnusMax = 0.32,
	spinDecay = 0.06, -- 1/s: hava sürtünmesiyle spin sönümü (üssel)

	-- Zemin teması (çim, kuru)
	restitution = 0.74, -- dikey sekme katsayısı (zemin testi: 2 m'den ~1.10 m sekme)
	contactFriction = 0.45, -- Coulomb sürtünme katsayısı (teğetsel impuls sınırı)
	rollResistance = 0.06, -- yuvarlanma direnci; ivme = -mu * g ≈ 0.59 m/s²
	rollThreshold = 0.9, -- m/s: bundan yavaş dikey çarpmada sekmez, yuvarlanmaya geçer
	stopSpeed = 0.15, -- m/s: bu hızın altında top durur

	-- Sekme sonrası spinin dikey zıplamaya etkisi (backspin topu alçak tutar).
	spinBounceCoupling = 0.06,

	-- Direk/üst direk çarpışması (metal, çimden daha canlı sekmez)
	postRestitution = 0.62,
	postFriction = 0.35,
}

Config.PITCH = {
	length = 105,
	width = 68,
	halfLength = 52.5,
	halfWidth = 34,
	goalHalfWidth = 3.66, -- 7.32 m kale ağzı
	goalHeight = 2.44,
	goalDepth = 2.0,
	penaltyAreaLength = 16.5,
	penaltyAreaHalfWidth = 20.16,
	goalAreaLength = 5.5,
	goalAreaHalfWidth = 9.16,
	penaltySpot = 11,
	centerCircleRadius = 9.15,
	cornerArcRadius = 1,

	-- Direkler: top bunlara çarpıp döner (Colliders modülü)
	postRadius = 0.06, -- 12 cm direk
	crossbarRadius = 0.06,
}

Config.PLAYER = {
	radius = 0.35,
	maxSpeed = 7.6, -- m/s (27 km/h) — iyi bir amatörün sprint hızı
	sprintMultiplier = 1.0,
	acceleration = 6.5, -- m/s² (0-27 km/h ~1.2 s)
	deceleration = 9.0, -- m/s²
	turnRate = 7.0, -- rad/s (~400°/s) gövde dönüş hızı
	staminaDrainSprint = 0.045, -- 1/s (tam sprintte)
	staminaRegen = 0.07, -- 1/s (dururken)
	staminaMinFactor = 0.72, -- yorgunken hız çarpanı
}

--[[ Vuruş türleri — profesyonel futbolcu şut biomekaniğine göre.
\tHiçbir yayınlanmış animasyon asset'i yok; tüm parametreler kodla uygulanır.
\t
\tTürler:
\t  place   = Plase (iç ayak) — en çok doğruluk, kalça açık, gövde dik, kısa takip
\t  instep  = Düz ayak / paltö (laces) — standart güç, ayak kilitli, gövde topun üstünde, tam takip
\t  drive   = Şanzıman / sürüklü şut — max güç, gövde çok öne eğik, ayak sıkı kilitli, yüksek takip
\t  outside = Ayak dışı / trivela — kıvrımlı, ayak ters yöne döndürülmüş, kalça ters abduksiyon, gövde hafif geri
]]--
Config.SHOT = {
	types = { "place", "instep", "drive", "outside" },
	labels = {
		place   = "Plase (iç ayak)",
		instep  = "Düz ayak (paltö / laces)",
		drive   = "Şanzıman (drive)",
		outside = "Ayak dışı (trivela)",
	},
	-- ankleMult : ayak bileği kilidi (1.0 = tam kilit, 0.5 = açık/esnek)
	-- hipZMult  : kalça abduksiyonu yönü ve miktarı (+ = dışa, - = içe/ters)
	-- spineXMult: gövde ileri eğimi (1.0 = topun üstünde, 0.75 = dik, 1.3 = çok öne)
	-- followY   : takip yüksekliği (daha negatif = bacak daha yüksek kalkar)
	-- power     : savurma genliği çarpanı
	-- bodyLeanBack: gövde geri eğilir mi? (chip/finesse türleri için)
	place   = { ankleMult = 0.70, hipZMult = 1.8,  spineXMult = 0.75, followY = -0.55, power = 0.80, bodyLeanBack = false },
	instep  = { ankleMult = 1.00, hipZMult = 1.0,  spineXMult = 1.00, followY = -1.00, power = 1.00, bodyLeanBack = false },
	drive   = { ankleMult = 1.25, hipZMult = 0.6,  spineXMult = 1.30, followY = -1.40, power = 1.15, bodyLeanBack = false },
	outside = { ankleMult = 0.50, hipZMult = -1.6, spineXMult = 0.90, followY = -0.75, power = 0.90, bodyLeanBack = true },
}

--[[ Oyuncu-top ilişkisi (yakın kontrol / top sürme / şut) ]]
Config.BALL_CONTROL = {
	bodyRadius = 0.42, -- oyuncu gövde yarıçapı (m)
	bodyHeight = 1.80,
	controlRadius = 1.45, -- bu mesafede top "ayakta" sayılır
	kickReach = 2.00, -- şut atılabilen maksimum mesafe (1.70 ilk deneyimde çok dardı)
	dribbleReach = 1.60,

	-- Dokunuş (touch) modeli: gerçekte top sürerken saniyede ~3 dokunuş olur
	touchInterval = 0.34,
	touchSpeedFactor = 1.0, -- (artık kullanılmıyor; dokunuş hızı çözülerek bulunuyor)
	touchForward = 0.18, -- dokunuşun ileri bileşeni (m/s) — küçük düzeltme
	maxTouchSpeed = 10.5,
	sprintTouchPenalty = 0.30, -- hızlı koşarken dokunuş aşırıya kaçar (top kaçar)

	-- İlk dokunuş / kapatma (trap)
	trapSpeedThreshold = 6.0,
	trapFactor = 0.30, -- gelen hızlı topun ne kadarı kalır
	trapRadius = 0.95,

	-- Şut
	minKickSpeed = 13,
	maxKickSpeed = 31,
	chargeTime = 0.9, -- tam güç için basılı tutma süresi
	kickHeight = 1.0, -- top bu yüksekliğin altındaysa vurulabilir
	aimErrorDeg = 2.2, -- nişan hatası (derece, standart sapma)
}

--[[ Kaleci AI ]]
Config.KEEPER = {
	height = 1.90,
	radius = 0.44,
	lineOffset = 0.55, -- kale çizgisinden öne mesafe (m)
	maxSpeed = 6.0, -- yan kayma hızı
	diveSpeed = 8.5,
	diveAccel = 22,
	reachZ = 3.15, -- direklerin içinde kalır
	restitution = 0.45,
	reactionTime = 0.12,
	diveReachBonus = 0.14, -- dalışta gövde yarıçapı artışı (uzanan kollar)
}

--[[ File (ağ) fiziği: top ağda yavaşlar, esnetir, geri sektirmez ]]
Config.NET = {
	damping = 7.0, -- ağ içinde üstel hız sönümü (1/s)
	restitution = 0.14, -- ağdan sekme katsayısı (çok ölü)
	sideRestitution = 0.10,
	topRestitution = 0.10,
	friction = 0.55,
	maxSag = 0.38, -- ağın en fazla esneme miktarı (m)
	sagStiffness = 11.0, -- geri toplama yayı
	sagDamping = 3.2,
	sagImpulse = 1.7, -- çarpma hızının esnemeye dönüşümü
}

--[[ Animasyon: TAMAMEN kodla, sunucuda. Hiçbir yayınlanmış asset yok.
	Pozlar Anim/Rig (FK) + Anim/KickAnim + Anim/KeeperAnim tarafından üretilir. ]]
Config.ANIM = {
	poseHumanoid = true, -- oyuncunun R15 eklemleri sunucudan sürülsün mü (deneysel)
	-- Prosedürel şutçu NPC'si VARSAYILAN KAPALI: sahada şutu atan oyuncunun
	-- KENDİSİdir (SPACE), kaleci ise AI. NPC ancak demo/test için açılır
	-- (Config.ANIM.strikerEnabled = true) — açıkken yürür ve şut çeker.
	strikerEnabled = false,
	keeperPoseEnabled = true, -- kaleci iskeleti gerçekten pozlansın mı
}

Config.MATCH = {
	halves = 2,
	halfLengthSeconds = 45 * 60,
	stoppageBase = 60,
	kickoffCountdown = 3,
}

return Config
]=] },
	["shared/Core/Aero"] = { class = "ModuleScript", source = [=[
--[[
	Aero — aerodinamik kuvvetler: hava direnci (drag) ve Magnus etkisi.

	Top havadayken iki kuvvet onu "gerçek" yapar:

	1) DRAG (hava direnci)
	   a = -0.5 * rho * A * Cd * |v| * v / m
	   30 m/s'lik bir şutta ~12 m/s² yavaşlama (1.2 g). Bu yüzden 30 m/s ile
	   vurulan bir şut, 40 m'ye vardığında ~19 m/s'ye düşer. Düz çizgi varsayan
	   basit simülasyonların "top hep kaleye giriyor" hatası buradan gelir.

	2) MAGNUS (spin / falso)
	   a = 0.5 * rho * A * Cl * v² * (ω̂ × v̂) / m
	   Falso ekseni ile hız vektörünün çapraz çarpımı, topun yana (veya yukarı/aşağı)
	   bükülmesini sağlar. Cl, spin oranı S = ω*r/v ile büyür — yavaş topta
	   falso daha çok etki eder, hızlı topta azalır; gerçek futbolun sezgisi budur.

	Cd'nin hıza bağlı olması ("drag crisis"): 12-30 m/s arasında Cd 0.47'den 0.25'e
	düşer. Knuckleball'un düzensiz uçuşunun sebebi budur; burada yumuşak geçiş
	olarak modellenir (tam türbülans modeli Roblox'ta gereksiz maliyetli).
]]

local Vec3 = require(script.Parent.Vec3)

local Aero = {}

local sqrt = math.sqrt
local exp = math.exp

-- Hıza bağlı direnç katsayısı: drag crisis geçişi.
function Aero.dragCoefficientFor(speed, cfg)
	local b = cfg.BALL
	local slow, fast = b.dragCoefficientSlow, b.dragCoefficient
	local mid = b.dragCrisisSpeed
	local width = b.dragCrisisWidth
	-- 1 / (1 + exp((v - mid) / width)) : yavaşta 1, hızlıda 0 olan yumuşak geçiş
	local t = 1 / (1 + exp((speed - mid) / width))
	return fast + (slow - fast) * t
end

-- Hava direnci ivmesi (m/s²).
function Aero.dragAccel(vel, cfg)
	local speedSq = Vec3.lengthSq(vel)
	local speed = sqrt(speedSq)
	if speed < 1e-6 then
		return Vec3.ZERO
	end
	local b = cfg.BALL
	local cd = Aero.dragCoefficientFor(speed, cfg)
	local k = 0.5 * cfg.AIR.density * b.crossSection * cd * speed / b.mass
	return Vec3.scale(vel, -k)
end

-- Magnus (spin) ivmesi (m/s²).
function Aero.magnusAccel(vel, spin, cfg)
	local speed = Vec3.length(vel)
	if speed < 1e-6 then
		return Vec3.ZERO
	end
	local omega = Vec3.length(spin)
	if omega < 1e-6 then
		return Vec3.ZERO
	end
	local b = cfg.BALL
	local spinRatio = omega * b.radius / speed -- S boyutsuz
	local cl = b.magnusScale * spinRatio
	if cl > b.magnusMax then
		cl = b.magnusMax
	end
	-- (ω̂ × v̂): hem yön hem birim uzunluk; cross(ω, v) normalize etmek yeterli
	local dir = Vec3.unit(Vec3.cross(spin, vel))
	local k = 0.5 * cfg.AIR.density * b.crossSection * cl * speed * speed / b.mass
	return Vec3.scale(dir, k)
end

-- Havadaki toplam ivme (yerçekimi + drag + Magnus). Sadece havada çağırın.
function Aero.totalAccel(vel, spin, cfg)
	local acc = Vec3.new(0, -cfg.GRAVITY, 0)
	acc = Vec3.add(acc, Aero.dragAccel(vel, cfg))
	acc = Vec3.add(acc, Aero.magnusAccel(vel, spin, cfg))
	return acc
end

-- Teorik terminal hız: 2mg / (rho*A*Cd) kökü. Test ve telemetri için.
function Aero.terminalSpeed(cfg)
	local b = cfg.BALL
	return sqrt(2 * b.mass * cfg.GRAVITY / (cfg.AIR.density * b.crossSection * b.dragCoefficient))
end

return Aero
]=] },
	["shared/Core/Ballistics"] = { class = "ModuleScript", source = [=[
--[[
	Ballistics — hedefe vuruş açısı çözümü.

	Bir oyuncu (veya AI) "şu noktaya şu hızla" pas/şut atmak istediğinde, yerçekimi
	altında gereken fırlatma açısını burada çözüyoruz. Formül, sabit yerçekimi
	varsayımıyla klasik eğik atış çözümüdür (hava direnci ihmal edilir; %5-8 hata
	yapar, gerçek oyuncunun nişan hatasıyla aynı mertebede).

	Denklem:  tanθ = (v² ± sqrt(v⁴ - g(g·R² + 2·h·v²))) / (g·R)
	  R = yatay mesafe, h = hedefin yükseklik farkı
	  "−" düz (sert) yörünge, "+" aşırtma (lob) yörüngesi

	Çözüm yoksa (hedef menzil dışı) nil döner — AI bunu "pas imkânsız" olarak yorumlar.
]]

local Vec3 = require(script.Parent.Vec3)

local Ballistics = {}

function Ballistics.solveLaunch(from, to, speed, gravity, highArc)
	local g = gravity or 9.81
	local dx = to.x - from.x
	local dz = to.z - from.z
	local h = to.y - from.y
	local horiz = math.sqrt(dx * dx + dz * dz)

	if speed <= 0 then
		return nil
	end
	if horiz < 1e-4 then
		-- Dikey atış
		return Vec3.new(0, speed, 0)
	end

	local v2 = speed * speed
	local disc = v2 * v2 - g * (g * horiz * horiz + 2 * h * v2)
	if disc < 0 then
		return nil
	end
	local root = math.sqrt(disc)
	local tanTheta
	if highArc then
		tanTheta = (v2 + root) / (g * horiz)
	else
		tanTheta = (v2 - root) / (g * horiz)
	end

	local theta = math.atan(tanTheta)
	local dir = Vec3.unit(Vec3.new(dx, 0, dz))
	local cosT = math.cos(theta)
	local sinT = math.sin(theta)

	return Vec3.new(dir.x * speed * cosT, speed * sinT, dir.z * speed * cosT)
end

-- Verilen hızla hedefe ulaşılabilir mi?
function Ballistics.isReachable(from, to, speed, gravity)
	return Ballistics.solveLaunch(from, to, speed, gravity) ~= nil
end

--[[ Vuruş spinini nişana göre seç.
	Alçak sürükleyici şut  -> topspin (top yere doğru dalar)
	Yüksek köşe şutu       -> backspin (top havada kalır, çabuk düşmez)
	Böylece "1.90 m'ye nişan alınan top 0.60 m'ye iniyor" sorunu kalkar. ]]
function Ballistics.shotSpin(speed, aimY, aimZ)
	local topspin = math.min(70, (speed or 20) * 1.6)
	local loft = math.max(0, math.min(1, ((aimY or 0.8) - 0.7) / 1.3))
	local z = -topspin * (1 - loft) + 26 * loft
	-- Hafif yan falso: köşeye vururken top kaleciden uzağa kıvrılır
	local side = math.max(-1, math.min(1, (aimZ or 0) / 3.0))
	return Vec3.new(0, -side * 12, z)
end

return Ballistics
]=] },
	["shared/Core/Rng"] = { class = "ModuleScript", source = [=[
--[[
	Rng — deterministik sözde rastgele sayı üreteci (Park–Miller / MINSTD).

	Neden math.random değil?
	  * Roblox'un math.random'ı sunucu/istemcide ayrı tohumlanır ve sürümler arası
	    garantisi yoktur. Ağ senkronu ve tekrar oynatma (replay) için aynı tohumdan
	    aynı diziyi üretmemiz şart.
	  * Sadece double aritmetiği kullanır: Lua 5.1, Lua 5.3 ve Luau'da bit-bit aynı
	    sonucu verir (bitwise operatör yok, taşma yok).
]]

local Rng = {}
Rng.__index = Rng

local MOD = 2147483647 -- 2^31 - 1
local MUL = 48271 -- 48271 * 2^31 < 2^53 olduğu için double'da tam duyarlı

function Rng.new(seed)
	local s = math.floor(math.abs(tonumber(seed) or 1)) % MOD
	if s == 0 then
		s = 1
	end
	return setmetatable({ state = s, seed = s }, Rng)
end

-- [0, 1) aralığında float.
function Rng:next()
	self.state = (self.state * MUL) % MOD
	return (self.state - 1) / (MOD - 1)
end

-- [0, 1] aralığında float.
function Rng:nextInclusive()
	self.state = (self.state * MUL) % MOD
	return self.state / MOD
end

-- [a, b) aralığında float.
function Rng:range(a, b)
	return a + (b - a) * self:next()
end

-- [-a, +a] aralığında float.
function Rng:symmetric(a)
	return (self:next() * 2 - 1) * a
end

-- [a, b] aralığında tam sayı.
function Rng:int(a, b)
	if b < a then
		a, b = b, a
	end
	return a + math.floor(self:next() * (b - a + 1))
end

-- Normal dağılım (Box–Muller). Şut/pas hatası için gerçekçi sapma üretir.
function Rng:normal(mean, stddev)
	local u1 = math.max(self:next(), 1e-12)
	local u2 = self:next()
	local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
	return (mean or 0) + z * (stddev or 1)
end

function Rng:chance(p)
	return self:next() < p
end

function Rng:pick(list)
	return list[self:int(1, #list)]
end

function Rng:clone()
	return setmetatable({ state = self.state, seed = self.seed }, Rng)
end

return Rng
]=] },
	["shared/Core/Validate"] = { class = "ModuleScript", source = [=[
--[[
	Validate — doğrulanmamış girdiyi güvenle kullanılabilir değere indirger.

	NEDEN AYRI MODÜL
	  İstemci `Kick` remote'una HERHANGİ bir şey gönderebilir: nil, tablo, string,
	  NaN, 1e300. Sunucu bu değeri fiziğe ve animasyona verdiği için doğrulanmamış
	  girdi iki şekilde patlar:
	    1) Sessiz bozulma  — `math.min(1, NaN) == NaN`; NaN hız topun tüm durumunu
	       zehirler ve bir daha düzelmez (top görünmez olur, skor donar).
	    2) Handler çökmesi — `KickAnim`, `Config.SHOT[shotType]` ve `"hip" .. foot`
	       kullanır; shotType = "labels" (gerçek bir tablo!) -> `sp.power = nil` ->
	       aritmetik hatası; foot = {} -> concatenate hatası.
	  Bu yüzden politika: BEYAZ LİSTE + VARSAYILANA DÜŞ. Girdi geçersizse istek
	  reddedilmez, geçerli varsayılanla uygulanır (şut sessizce yutulmaz).

	  Mantık burada, SimLoop'un içinde değil: böylece birim olarak test edilebilir
	  ve hem sunucu hem istemci aynı kuralları paylaşır. Roblox API'si KULLANMAZ.
]]

local Validate = {}

-- Config.SHOT.types boş/eksik olsa bile her zaman bir geçerli vuruş türü kalsın
Validate.DEFAULT_SHOT_TYPE = "instep"

-- Fizikte anlamı olan en büyük büyüklük (m/s, m). Üstü ölçüm hatası/istismardır.
Validate.MAX_COMPONENT = 1e6

--- Sayı mı, sonlu mu? Değilse `fallback`.
-- tonumber("12") = 12 olduğu için sayısal string'ler de kabul edilir (istemci
-- JSON benzeri bir katmandan string gönderebilir); tonumber({}) = nil -> fallback.
function Validate.number(value, fallback)
	local n = tonumber(value)
	if n == nil then
		return fallback
	end
	if n ~= n or n == math.huge or n == -math.huge then
		return fallback
	end
	return n
end

--- Sayıya çevir, sonra [lo, hi] aralığına kıstır; geçersizse `fallback`.
-- Sıra önemli: önce sonluluk, sonra clamp. `math.min(1, NaN)` NaN döndürdüğü
-- için clamp tek başına koruma sağlamaz.
function Validate.clamp(value, lo, hi, fallback)
	local n = Validate.number(value, fallback)
	if n < lo then
		return lo
	end
	if n > hi then
		return hi
	end
	return n
end

--- Vec3 benzeri `{x, y, z}` gerçekten sonlu bir vektör mü?
-- Bu denetim topa YAZILACAK hız için son savunma hattıdır: balistik çözücü
-- (Ballistics.solveLaunch) hedefe ulaşılamadığında NaN üretebilir ve NaN hız
-- simülasyonun geri kalanını kalıcı olarak bozar.
function Validate.vec3(v)
	if type(v) ~= "table" then
		return false
	end
	-- BİLEREK ipairs değil, indis ile: `ipairs({v.x, v.y, v.z})` z nil olduğunda
	-- 2 elemanda durur ve eksik bileşenli tablo "geçerli" sayılırdı.
	local components = { v.x, v.y, v.z }
	for i = 1, 3 do
		local component = components[i]
		if type(component) ~= "number" or component ~= component or math.abs(component) > Validate.MAX_COMPONENT then
			return false
		end
	end
	return true
end

--- Config.SHOT'tan geçerli vuruş türü kümesi (set) üretir.
function Validate.shotTypeSet(shotConfig)
	local allowed = {}
	local types = shotConfig and shotConfig.types
	if type(types) == "table" then
		for _, typeName in ipairs(types) do
			if type(typeName) == "string" then
				allowed[typeName] = true
			end
		end
	end
	allowed[Validate.DEFAULT_SHOT_TYPE] = true
	return allowed
end

--- Vuruş türü beyaz listede mi? Değilse varsayılan tür.
-- `allowed` verilmezse Validate.shotTypeSet(nil) ile üretilen tek üyeli küme kullanılır.
function Validate.shotType(value, allowed)
	local set = allowed or Validate.shotTypeSet(nil)
	if type(value) == "string" and set[value] then
		return value
	end
	return Validate.DEFAULT_SHOT_TYPE
end

--- Ayak: yalnızca "L" veya "R". Diğer her şey nil -> animasyon otomatik seçer.
-- nil dönüşü bir hata değil, KickAnim'in topun yanına göre ayak seçtiği sözleşmedir.
function Validate.foot(value)
	if value == "L" or value == "R" then
		return value
	end
	return nil
end

return Validate
]=] },
	["shared/Core/Vec3"] = { class = "ModuleScript", source = [=[
--[[
	Vec3 — saf Lua vektör matematiği.

	Neden Roblox'un Vector3'ü değil?
	  * Çekirdek simülasyonun motor API'sine bağımlı olmaması gerekiyor: aynı kod
	    hem Roblox içinde hem de masaüstünde (test/CI) çalışmalı.
	  * Determinizm: float32 Vector3 yuvarlama hataları birikim yapar; burada
	    standart Lua double (float64) kullanıyoruz.
	  * Roblox katmanı (görsel) bu vektörleri Vector3'e çevirir, o kadar.

	Koordinat sistemi (saha merkezli, sağ el):
	  +x : orta saha çizgisinden bir kaleye doğru (uzunluk ekseni)
	  +z : yan çizgiye doğru (genişlik ekseni)
	  +y : yukarı (yerçekimine zıt)

	Kural: tüm fonksiyonlar YENİ tablo döndürür, argümanları asla değiştirmez.
]]

local Vec3 = {}
local sqrt = math.sqrt
-- Lua 5.3: math.atan(y, x) | Luau: math.atan2(y, x). Ikisi de desteklensin.
local atan2 = math.atan2 or math.atan

local function make(x, y, z)
	return { x = x, y = y, z = z }
end

Vec3.new = function(x, y, z)
	return make(x or 0, y or 0, z or 0)
end

-- Paylaşılan sabitler: değiştirilmemeli (tüm fonksiyonlar yeni tablo döndürür).
Vec3.ZERO = make(0, 0, 0)
Vec3.UP = make(0, 1, 0)

function Vec3.add(a, b)
	return make(a.x + b.x, a.y + b.y, a.z + b.z)
end

function Vec3.sub(a, b)
	return make(a.x - b.x, a.y - b.y, a.z - b.z)
end

function Vec3.scale(v, k)
	return make(v.x * k, v.y * k, v.z * k)
end

function Vec3.negate(v)
	return make(-v.x, -v.y, -v.z)
end

function Vec3.addScaled(a, b, k)
	return make(a.x + b.x * k, a.y + b.y * k, a.z + b.z * k)
end

function Vec3.dot(a, b)
	return a.x * b.x + a.y * b.y + a.z * b.z
end

function Vec3.cross(a, b)
	return make(
		a.y * b.z - a.z * b.y,
		a.z * b.x - a.x * b.z,
		a.x * b.y - a.y * b.x
	)
end

function Vec3.lengthSq(v)
	return v.x * v.x + v.y * v.y + v.z * v.z
end

function Vec3.length(v)
	return sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

-- Yatay (y=0) düzlemdeki hız bileşeni.
function Vec3.horizontal(v)
	return make(v.x, 0, v.z)
end

function Vec3.lengthHorizontal(v)
	return sqrt(v.x * v.x + v.z * v.z)
end

function Vec3.withY(v, y)
	return make(v.x, y, v.z)
end

function Vec3.unit(v)
	local len = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
	if len < 1e-12 then
		return make(0, 0, 0)
	end
	local inv = 1 / len
	return make(v.x * inv, v.y * inv, v.z * inv)
end

function Vec3.lerp(a, b, t)
	return make(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
end

-- a vektörünün b vektörü üzerindeki izdüşümü.
function Vec3.project(a, b)
	local d = Vec3.dot(b, b)
	if d < 1e-12 then
		return make(0, 0, 0)
	end
	return Vec3.scale(b, Vec3.dot(a, b) / d)
end

-- İki vektör arasındaki açı (radyan).
function Vec3.angleBetween(a, b)
	local denom = Vec3.length(a) * Vec3.length(b)
	if denom < 1e-12 then
		return 0
	end
	local c = Vec3.dot(a, b) / denom
	if c > 1 then c = 1 elseif c < -1 then c = -1 end
	return math.acos(c)
end

-- Yatay düzlemde yön açısı: +x ekseninden +z'ye doğru (atan2(z, x)).
function Vec3.yaw(v)
	return atan2(v.z, v.x)
end

function Vec3.fromYaw(angle)
	return make(math.cos(angle), 0, math.sin(angle))
end

function Vec3.distance(a, b)
	return Vec3.length(Vec3.sub(a, b))
end

function Vec3.distanceHorizontal(a, b)
	return Vec3.lengthHorizontal(Vec3.sub(a, b))
end

function Vec3.isFinite(v)
	return v.x == v.x and v.y == v.y and v.z == v.z
		and math.abs(v.x) < 1e30 and math.abs(v.y) < 1e30 and math.abs(v.z) < 1e30
end

function Vec3.tostring(v)
	return string.format("(%.3f, %.3f, %.3f)", v.x, v.y, v.z)
end

return Vec3
]=] },
	["shared/Physics/Ball"] = { class = "ModuleScript", source = [=[
--[[
	Ball — topun deterministik fizik modeli.

	ADIM 1'İN KALBİ. Top Roblox'un fizik motoruna BIRAKILMAZ; burada 240 Hz'de
	kendi entegratörümüzle simüle edilir. Sebepleri:

	  * Roblox fiziği float32 + motor içi çözücü; sekme/temas davranışı ayarlanamaz
	    (restitution ayarı yok, sadece CustomPhysicalProperties ile kaba kontrol).
	  * Sunucu ve istemci aynı sonucu üretmez -> istemci tahmini (prediction) ve
	    gecikme telafisi (lag compensation) yapılamaz.
	  * Gerçek aerodinamik (drag + Magnus + drag crisis) Roblox'ta yok.

	Bu modül şunları yapar:
	  1) Havada: yerçekimi + drag + Magnus, yarı-örtük Euler.
	  2) Zemine teması ANALİTİK olarak yakalar: adım içinde y(t)=r denkleminin
	     kökünü bulur, temas anına kadar entegre eder, sekmeyi uygular, kalan
	     süreyi yeniden işler. Yani sekme yüksekliği adım boyutundan bağımsızdır
	     (tünelleme ve "top zemine gömülüyor" hataları oluşmaz).
	  3) Sekmede Coulomb sürtünmesi: temas noktasındaki kayma hızı, normal impuls
	     ile sınırlı teğetsel impuls üretir. Topspin topu ileri hızlandırır,
	     backspin yavaşlatır — gerçek davranış.
	  4) Yuvarlanma: yuvarlanma direnci + kaymadan yuvarlanma koşulu (ω = v/r).

	Koordinatlar: saha merkezli metre. Zemin y=0, top merkezi y=r iken yuvarlanır.
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)
local Aero = require(script.Parent.Parent.Core.Aero)

local Ball = {}
Ball.__index = Ball

local sqrt = math.sqrt
local abs = math.abs
local min = math.min

--[[
	y(t) = y0 + vy0*t + 0.5*ay*t² = r  denkleminin [0, dt] içindeki en küçük kökü.
	Sabit ivme varsayımı geçerli (bir adım boyunca aerodinamik ivme sabit kabul
	edilir; 1/240 s'de hata ihmal edilebilir).
]]
local function solveContactTime(y0, vy0, ay, r, dt)
	local a = 0.5 * ay
	local b = vy0
	local c = y0 - r

	if abs(a) < 1e-9 then
		if abs(b) < 1e-9 then
			return nil
		end
		local t = -c / b
		if t >= 0 and t <= dt then
			return t
		end
		return nil
	end

	local disc = b * b - 4 * a * c
	if disc < 0 then
		return nil
	end

	local sq = sqrt(disc)
	local inv2a = 1 / (2 * a)
	local t1 = (-b - sq) * inv2a
	local t2 = (-b + sq) * inv2a

	local best = nil
	if t1 >= 0 and t1 <= dt then
		best = t1
	end
	if t2 >= 0 and t2 <= dt and (best == nil or t2 < best) then
		best = t2
	end
	return best
end

function Ball.new(cfg, position)
	local r = cfg.BALL.radius
	local pos = position or Vec3.new(0, r, 0)
	local ball = setmetatable({
		cfg = cfg,
		pos = pos,
		vel = Vec3.new(0, 0, 0),
		spin = Vec3.new(0, 0, 0),
		mode = "ground", -- "air" | "ground"
		contacts = 0, -- toplam zemin teması sayısı (telemetri/test)
		postHits = 0, -- direk/üst direk çarpışması sayısı (telemetri/test)
	}, Ball)
	-- Havada başlıyorsa modu düzelt
	if pos.y > r + 1e-6 then
		ball.mode = "air"
	end
	return ball
end

function Ball:setState(position, velocity, spin)
	self.pos = position or self.pos
	self.vel = velocity or Vec3.new(0, 0, 0)
	self.spin = spin or Vec3.new(0, 0, 0)
	local r = self.cfg.BALL.radius
	-- Mod SADECE konuma bakmaz: zeminde duran topa yukarı doğru vurulursa havaya
	-- çıkar. (Bu satır olmadan tüm vuruşlar "yuvarlanma" olarak yorumlanıyordu.)
	self.mode = (self.pos.y > r + 1e-6 or self.vel.y > 1e-6) and "air" or "ground"
	if self.mode == "ground" then
		self.pos = Vec3.withY(self.pos, r)
	end
end

-- Vuruş: hız ve spin ata. (Adım 4'te pas/şut sistemleri bunu kullanacak.)
function Ball:kick(velocity, spin)
	self.vel = velocity
	self.spin = spin or Vec3.new(0, 0, 0)
	local r = self.cfg.BALL.radius
	self.mode = (self.pos.y > r + 1e-6 or self.vel.y > 1e-6) and "air" or "ground"
end

function Ball:speed()
	return Vec3.length(self.vel)
end

function Ball:spinRps()
	return Vec3.length(self.spin) / (2 * math.pi)
end

function Ball:isFinite()
	return Vec3.isFinite(self.pos) and Vec3.isFinite(self.vel) and Vec3.isFinite(self.spin)
end

function Ball:snapshot()
	return {
		pos = { x = self.pos.x, y = self.pos.y, z = self.pos.z },
		vel = { x = self.vel.x, y = self.vel.y, z = self.vel.z },
		spin = { x = self.spin.x, y = self.spin.y, z = self.spin.z },
		mode = self.mode,
	}
end

function Ball:_decaySpin(dt)
	local k = math.exp(-self.cfg.BALL.spinDecay * dt)
	if k < 1 then
		self.spin = Vec3.scale(self.spin, k)
	end
end

--[[
	Sabit ivme altında TAM çözüm (yamuk kuralı / velocity-Verlet):

		v' = v + a*dt
		p' = p + (v + v')/2 * dt

	Klasik yarı-örtük Euler'in (p' = p + v'*dt) aksine burada serbest düşüş
	yörüngesi adım boyutundan bağımsız olarak doğrudur: 60 Hz ile 240 Hz aynı tepe
	noktasını verir. Fiziksel doğruluk için kritik — aksi halde düşük FPS'te
	oynayan oyuncunun şutları 1-2 m sapardı.
]]
function Ball:_integrate(acc, dt)
	local velNew = Vec3.add(self.vel, Vec3.scale(acc, dt))
	local avgVel = Vec3.scale(Vec3.add(self.vel, velNew), 0.5)
	self.pos = Vec3.add(self.pos, Vec3.scale(avgVel, dt))
	self.vel = velNew
end

--[[
	Sekme çözümü. Gelen dikey hız negatif (top aşağı iniyor).
	1) Dikey: v_y' = -e * v_y
	2) Teğetsel: temas noktasındaki kayma = v_t + ω × (0,-r,0)
	   |J_t| <= mu * |J_n|  (Coulomb)
	   Δω = (offset × Δv) * 5/(2r²)  (katı küre, I = 2/5 m r²)
]]
function Ball:_bounce()
	local cfg = self.cfg
	local b = cfg.BALL
	local r = b.radius
	local vy = self.vel.y

	-- Çok yavaş dikey çarpma: sekmez, yuvarlanmaya geçer.
	if -vy < b.rollThreshold then
		self.pos = Vec3.withY(self.pos, r)
		self.vel = Vec3.withY(self.vel, 0)
		self.spin = Vec3.new(self.vel.z / r, self.spin.y * 0.5, -self.vel.x / r)
		self.mode = "ground"
		self.contacts = self.contacts + 1
		return
	end

	-- Spinin sekme yüksekliğine etkisi (ampirik, küçük katsayı):
	-- topspin topu biraz alçak, backspin biraz yüksek zıplatır.
	local horiz = Vec3.lengthHorizontal(self.vel)
	local e = b.restitution
	if horiz > 0.5 then
		local fwd = Vec3.scale(self.vel, 1 / horiz)
		local axis = Vec3.cross(Vec3.UP, fwd) -- topspin ekseni
		local rollingRate = horiz / r
		local t = Vec3.dot(self.spin, axis) / rollingRate -- [-1, 1] civarı
		if t > 1 then t = 1 elseif t < -1 then t = -1 end
		e = e * (1 - b.spinBounceCoupling * t)
	end

	local jn = (1 + e) * (-vy) -- birim kütle normal impuls (m/s)

	-- Teğetsel impuls
	local offset = Vec3.new(0, -r, 0)
	local surface = Vec3.cross(self.spin, offset) -- ω × offset
	local slip = Vec3.new(self.vel.x + surface.x, 0, self.vel.z + surface.z)
	local slipLen = Vec3.length(slip)
	local maxDv = b.contactFriction * jn

	if slipLen > 1e-6 and maxDv > 1e-6 then
		local dvMag = min(slipLen, maxDv)
		local dvel = Vec3.scale(slip, -dvMag / slipLen)
		self.vel = Vec3.add(self.vel, dvel)
		local dOmega = Vec3.scale(Vec3.cross(offset, dvel), 5 / (2 * r * r))
		self.spin = Vec3.add(self.spin, dOmega)
	end

	self.vel = Vec3.withY(self.vel, -e * vy)
	self.pos = Vec3.withY(self.pos, r)
	self.contacts = self.contacts + 1

	-- Enerji bittiyse yuvarlanmaya geç
	if -e * vy < b.rollThreshold * 0.4 then
		self.mode = "ground"
	end
end

-- Havada bir adım. Dönüş değeri: işlenmemiş kalan süre.
function Ball:_stepAir(dt)
	local cfg = self.cfg
	local r = cfg.BALL.radius
	local acc = Aero.totalAccel(self.vel, self.spin, cfg)

	-- Zeminden yeni ayrılan top (y = r, vy >= 0) için denklemin t=0 kökü çıkar;
	-- bu bir çarpma değildir, yoksa sekme anında dikey hız sıfırlanır.
	if self.pos.y <= r + 1e-9 and self.vel.y >= 0 then
		self:_integrate(acc, dt)
		self:_decaySpin(dt)
		return 0
	end

	local t = solveContactTime(self.pos.y, self.vel.y, acc.y, r, dt)
	if t == nil then
		self:_integrate(acc, dt)
		self:_decaySpin(dt)
		return 0
	end

	-- Zemine değene kadar entegre et, sek, kalan süreyi geri ver.
	self:_integrate(acc, t)
	self:_decaySpin(t)
	self:_bounce()
	return dt - t
end

-- Yerde yuvarlanma.
function Ball:_stepGround(dt)
	local cfg = self.cfg
	local b = cfg.BALL
	local r = b.radius
	local speed = Vec3.lengthHorizontal(self.vel)

	if speed <= b.stopSpeed then
		self.vel = Vec3.new(0, 0, 0)
		self.spin = Vec3.new(0, 0, 0)
		self.pos = Vec3.withY(self.pos, r)
		return 0
	end

	local decel = b.rollResistance * cfg.GRAVITY
	local newSpeed = speed - decel * dt
	if newSpeed < 0 then
		newSpeed = 0
	end

	local dir = Vec3.scale(self.vel, 1 / speed)
	self.vel = Vec3.scale(dir, newSpeed)
	self.pos = Vec3.add(self.pos, Vec3.scale(self.vel, dt))
	self.pos = Vec3.withY(self.pos, r)

	-- Kaymadan yuvarlanma: ω = (vz/r, ωy, -vx/r)
	self.spin = Vec3.new(self.vel.z / r, self.spin.y, -self.vel.x / r)
	return 0
end

-- Tek simülasyon adımı. dt sabit (Config.FIXED_DT) olmalıdır.
function Ball:step(dt)
	if dt <= 0 then
		return
	end
	local remaining = dt
	local guard = 0
	while remaining > 1e-9 do
		guard = guard + 1
		if guard > 6 then
			remaining = 0
			break
		end
		if self.mode == "ground" then
			remaining = self:_stepGround(remaining)
		else
			remaining = self:_stepAir(remaining)
		end
	end
end

-- Gelecekteki durumu tahmin et (kaleciler, istemci tahmini, AI için).
-- Simülasyonun kopyası üzerinde çalışır; asıl topu etkilemez.
function Ball:clone()
	local copy = Ball.new(self.cfg, Vec3.new(self.pos.x, self.pos.y, self.pos.z))
	copy.vel = Vec3.new(self.vel.x, self.vel.y, self.vel.z)
	copy.spin = Vec3.new(self.spin.x, self.spin.y, self.spin.z)
	copy.mode = self.mode
	copy.contacts = self.contacts
	copy.postHits = self.postHits
	return copy
end

-- Belirli bir süre sonraki durumu döndürür (topu değiştirmez).
function Ball:predict(dt, steps)
	local copy = self:clone()
	local n = steps or math.max(1, math.ceil(dt / self.cfg.FIXED_DT))
	local h = dt / n
	for _ = 1, n do
		copy:step(h)
	end
	return copy
end

return Ball
]=] },
	["shared/Physics/Body"] = { class = "ModuleScript", source = [=[
--[[
	Body — hareketli gövde (oyuncu/kaleci) ile top çarpışması.

	Oyuncu ve kaleci dikey bir kapsül (silindir) olarak modellenir. Top küre.
	Çarpışma anında:
	  * top yüzeyin dışına taşınır,
	  * gövdeye GÖRE bağıl hız yansıtılır (koşan oyuncu topa hız katar),
	  * teğetsel sürtünme uygulanır.

	Neden bağıl hız? Sabit gövdeye çarpan top sadece seker; koşan bir oyuncunun
	bacağına çarpan top ise oyuncunun hızını da alır. Bu, "top oyuncudan sekiyor"
	hissini veren kritik detaydır.

	Roblox API'si kullanmaz -> test edilebilir.
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)

local Body = {}

local sqrt = math.sqrt
local min = math.min

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

-- Bir noktaya, dikey doğru parçası üzerindeki en yakın nokta.
local function closestOnVerticalSegment(point, base, height)
	local y = clamp(point.y, base.y, base.y + height)
	return Vec3.new(base.x, y, base.z)
end

--[[ Topu gövdeye karşı çözer. body:
	{ pos = Vec3 (ayak seviyesi), vel = Vec3, radius, height, restitution, hits }
	Dönüş: çarpıştı mı? ]]
function Body.collide(ball, body)
	if not body or not body.pos then
		return false
	end
	local ballR = ball.cfg.BALL.radius
	local bodyR = body.radius or 0.42
	local height = body.height or 1.8
	local e = body.restitution or 0.42

	local closest = closestOnVerticalSegment(ball.pos, body.pos, height)
	local delta = Vec3.sub(ball.pos, closest)
	local dist = Vec3.length(delta)
	local minDist = ballR + bodyR

	if dist >= minDist then
		return false
	end

	local n
	if dist > 1e-9 then
		n = Vec3.scale(delta, 1 / dist)
	else
		n = Vec3.negate(Vec3.unit(ball.vel))
		if Vec3.lengthSq(n) < 1e-9 then
			n = Vec3.new(1, 0, 0)
		end
	end

	-- Topu dışarı taşı
	ball.pos = Vec3.add(closest, Vec3.scale(n, minDist + 1e-4))

	-- Bağıl hız: top - gövde
	local bodyVel = body.vel or Vec3.ZERO
	local relVel = Vec3.sub(ball.vel, bodyVel)
	local vn = Vec3.dot(relVel, n)

	if vn < 0 then
		-- Normal bileşen: yansıt ve gövde hızını ekle
		local newRel = Vec3.sub(relVel, Vec3.scale(n, (1 + e) * vn))

		-- Teğetsel sürtünme (top ayağa sürtünür)
		local normalPart = Vec3.scale(n, Vec3.dot(newRel, n))
		local tangent = Vec3.sub(newRel, normalPart)
		local tangentSpeed = Vec3.length(tangent)
		if tangentSpeed > 1e-6 then
			local mu = body.friction or 0.30
			local reduce = min(tangentSpeed, mu * (1 + e) * (-vn))
			tangent = Vec3.scale(tangent, 1 - reduce / tangentSpeed)
		end

		ball.vel = Vec3.add(Vec3.add(bodyVel, normalPart), tangent)
		ball.spin = Vec3.scale(ball.spin, 0.7)
		body.hits = (body.hits or 0) + 1
	end

	return true
end

--[[ Bir gövdenin topa uzanıp uzanamayacağını ölçer (kaleci uzanma mesafesi,
	oyuncu kademesi). Dönüş: mesafe (m). ]]
function Body.reachDistance(ball, body)
	local closest = closestOnVerticalSegment(ball.pos, body.pos, body.height or 1.8)
	return Vec3.length(Vec3.sub(ball.pos, closest))
end

return Body
]=] },
	["shared/Physics/Colliders"] = { class = "ModuleScript", source = [=[
--[[
	Colliders — top ile direk/üst direk çarpışması.

	Direkler silindir, üst direk yatay silindirdir. Bunları "doğru parçası + yarıçap"
	(kapsül) olarak modelliyoruz; top da bir küre. Böylece genel bir çözücü yeterli:

	  1) Topun bu adımdaki hareket doğrusu (önceki konum -> yeni konum) ile direk
	     ekseni arasındaki EN YAKIN noktalar bulunur.
	  2) Mesafe (top yarıçapı + direk yarıçapı)'ndan küçükse çarpışma vardır.
	  3) Top yüzeyin dışına taşınır, normal bileşen -e ile yansıtılır, teğetsel
	     bileşene sürtünme uygulanır.

	Neden hareket doğrusu üzerinden? 30 m/s'lik bir şut 240 Hz'de adım başına
	12.5 cm ilerler; direk yarıçapı 6 cm olduğu için sadece konum kontrolü
	(discrete) bazı çarpışmaları kaçırırdı. Sürekli (continuous) test bunu önler.

	Bu modül Roblox API'si kullanmaz: aynı kod hem sunucuda hem testte çalışır.
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)

local Colliders = {}

local sqrt = math.sqrt
local min = math.min

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

--[[ İki doğru parçası arasındaki en yakın noktalar (Ericson, Real-Time Collision
	Detection, 5.1.9). Dönüş: c1 (p1-q1 üzerinde), c2 (p2-q2 üzerinde). ]]
local function closestPointsBetweenSegments(p1, q1, p2, q2)
	local d1 = Vec3.sub(q1, p1)
	local d2 = Vec3.sub(q2, p2)
	local r = Vec3.sub(p1, p2)

	local a = Vec3.dot(d1, d1)
	local e = Vec3.dot(d2, d2)
	local f = Vec3.dot(d2, r)

	local s, t

	if a <= 1e-12 and e <= 1e-12 then
		s, t = 0, 0
	elseif a <= 1e-12 then
		s = 0
		t = clamp(f / e, 0, 1)
	else
		local c = Vec3.dot(d1, r)
		if e <= 1e-12 then
			t = 0
			s = clamp(-c / a, 0, 1)
		else
			local b = Vec3.dot(d1, d2)
			local denom = a * e - b * b
			if denom > 1e-12 then
				s = clamp((b * f - c * e) / denom, 0, 1)
			else
				s = 0
			end
			t = (b * s + f) / e
			if t < 0 then
				t = 0
				s = clamp(-c / a, 0, 1)
			elseif t > 1 then
				t = 1
				s = clamp((b - c) / a, 0, 1)
			end
		end
	end

	local c1 = Vec3.add(p1, Vec3.scale(d1, s))
	local c2 = Vec3.add(p2, Vec3.scale(d2, t))
	return c1, c2
end

Colliders.closestPointsBetweenSegments = closestPointsBetweenSegments

--[[ Tek bir kapsül engeline karşı çarpışma çözümü. Dönüş: çarpıştı mı? ]]
local function resolveObstacle(ball, obs, fromPos)
	local cfg = ball.cfg
	local r = cfg.BALL.radius

	local c1, c2 = closestPointsBetweenSegments(fromPos, ball.pos, obs.a, obs.b)
	local delta = Vec3.sub(c1, c2)
	local dist = Vec3.length(delta)
	local minDist = r + (obs.radius or 0.06)

	if dist >= minDist then
		return false
	end

	-- Normal: direk ekseninden topa doğru
	local n
	if dist > 1e-9 then
		n = Vec3.scale(delta, 1 / dist)
	else
		n = Vec3.negate(Vec3.unit(ball.vel))
		if Vec3.lengthSq(n) < 1e-9 then
			n = Vec3.new(1, 0, 0)
		end
	end

	-- Topu yüzeyin dışına taşı (gömülmeyi önler)
	ball.pos = Vec3.add(c2, Vec3.scale(n, minDist + 1e-4))

	local vn = Vec3.dot(ball.vel, n)
	if vn >= 0 then
		-- Uzaklaşıyor: sadece konum düzeltmesi yeterli
		return true
	end

	local e = cfg.BALL.postRestitution or 0.62
	local vt = Vec3.sub(ball.vel, Vec3.scale(n, vn))
	local tangentSpeed = Vec3.length(vt)

	if tangentSpeed > 1e-6 then
		local mu = cfg.BALL.postFriction or 0.35
		local normalImpulse = (1 + e) * (-vn) -- birim kütle
		local reduce = min(tangentSpeed, mu * normalImpulse)
		vt = Vec3.scale(vt, 1 - reduce / tangentSpeed)
	end

	ball.vel = Vec3.add(Vec3.scale(n, -e * vn), vt)

	-- Spini gerçekçi biçimde sönümle (çarpma enerjinin bir kısmını yutar)
	ball.spin = Vec3.scale(ball.spin, 0.55)
	ball.postHits = (ball.postHits or 0) + 1
	return true
end

--[[ Topu tüm engellere karşı kontrol eder. fromPos: adım öncesi konum. ]]
function Colliders.resolve(ball, obstacles, fromPos)
	if not obstacles or #obstacles == 0 then
		return 0
	end
	local from = fromPos or ball.pos
	local hits = 0
	for i = 1, #obstacles do
		if resolveObstacle(ball, obstacles[i], from) then
			hits = hits + 1
		end
	end
	return hits
end

return Colliders
]=] },
	["shared/Physics/Net"] = { class = "ModuleScript", source = [=[
--[[
	Net — file (ağ) fiziği: top kaleye girdiğinde ne olur?

	Gerçek futbolda top fileye girdiğinde:
	  * hızı hızla düşer (ağ enerjiyi yutar, top "ölür"),
	  * file esner, sonra toparlanır,
	  * top geri sekmez — file bir yay değil, sönümleyicidir,
	  * top file içinde kalır (yan/üst/arka ağ onu tutar).

	Bu modül top kale kutusunun içindeyken:
	  1) Üstel sönüm uygular: v *= exp(-k·dt)  (k = NET.damping)
	  2) Arka/y an/üst ağ düzlemlerine çok düşük sekme katsayısıyla çarptırır
	  3) Ağın esnemesini yay-sönümleyici olarak modeller (sag)

	Esneme (sag) görsel olarak da kullanılır: sunucu arka ağ parçasını öteleyerek
	topun ağa gömülmesini gösterir.

	Roblox API'si kullanmaz -> aynı kod testte ve oyunda çalışır.
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)

local Net = {}
Net.__index = Net

local abs = math.abs
local min = math.min
local max = math.max
local exp = math.exp

function Net.new(cfg, side)
	return setmetatable({
		cfg = cfg,
		side = side or 1, -- 1: +x kalesi, -1: -x kalesi
		sag = 0,
		sagVel = 0,
		contacts = 0,
		lastImpactSpeed = 0,
	}, Net)
end

-- Top kale kutusunun içinde mi? (ağ bölgesi)
function Net:isInsideGoalBox(pos)
	local P = self.cfg.PITCH
	local r = self.cfg.BALL.radius
	local x0 = self.side * P.halfLength
	local x1 = self.side * (P.halfLength + P.goalDepth)
	local lo, hi = min(x0, x1), max(x0, x1)
	return pos.x >= lo - r and pos.x <= hi + r and abs(pos.z) <= P.goalHalfWidth + r and pos.y <= P.goalHeight + r
end

--[[ Ağın esneme dinamiği: yay + sönümleyici. ]]
function Net:_stepSag(dt)
	local N = self.cfg.NET
	local accel = -N.sagStiffness * self.sag - N.sagDamping * self.sagVel
	self.sagVel = self.sagVel + accel * dt
	self.sag = self.sag + self.sagVel * dt
	if self.sag < 0 then
		self.sag = 0
		if self.sagVel < 0 then
			self.sagVel = 0
		end
	elseif self.sag > N.maxSag then
		self.sag = N.maxSag
		if self.sagVel > 0 then
			self.sagVel = 0
		end
	end
end

--[[ Topu ağ içinde işler. Dönüş: ağ teması oldu mu? ]]
function Net:stepBall(ball, dt)
	local P = self.cfg.PITCH
	local N = self.cfg.NET
	local r = ball.cfg.BALL.radius

	self:_stepSag(dt)

	if not self:isInsideGoalBox(ball.pos) then
		return false
	end

	-- 1) Ağ içindeki hava/sürtünme kaybı: top "ölür"
	local k = exp(-N.damping * dt)
	ball.vel = Vec3.scale(ball.vel, k)
	ball.spin = Vec3.scale(ball.spin, k)

	local touched = false

	-- 2) Arka ağ: x = side * (halfLength + goalDepth - r + sag)
	local backLimit = self.side * (P.halfLength + P.goalDepth - r + self.sag)
	if self.side > 0 and ball.pos.x > backLimit then
		if ball.vel.x > 0 then
			self.lastImpactSpeed = ball.vel.x
			self.sagVel = self.sagVel + ball.vel.x * N.sagImpulse
			ball.vel.x = -N.restitution * ball.vel.x
			ball.vel.y = ball.vel.y * 0.55
			ball.vel.z = ball.vel.z * (1 - N.friction * 0.6)
			touched = true
		end
		ball.pos.x = backLimit
	elseif self.side < 0 and ball.pos.x < backLimit then
		if ball.vel.x < 0 then
			self.lastImpactSpeed = -ball.vel.x
			self.sagVel = self.sagVel - ball.vel.x * N.sagImpulse
			ball.vel.x = -N.restitution * ball.vel.x
			ball.vel.y = ball.vel.y * 0.55
			ball.vel.z = ball.vel.z * (1 - N.friction * 0.6)
			touched = true
		end
		ball.pos.x = backLimit
	end

	-- 3) Yan ağlar
	local sideLimit = P.goalHalfWidth - r
	if abs(ball.pos.z) > sideLimit then
		local sign = ball.pos.z > 0 and 1 or -1
		ball.pos.z = sign * sideLimit
		if ball.vel.z * sign > 0 then
			ball.vel.z = -N.sideRestitution * ball.vel.z
			touched = true
		end
	end

	-- 4) Üst ağ
	local topLimit = P.goalHeight - r
	if ball.pos.y > topLimit then
		ball.pos.y = topLimit
		if ball.vel.y > 0 then
			ball.vel.y = -N.topRestitution * ball.vel.y
			touched = true
		end
	end

	if touched then
		self.contacts = self.contacts + 1
	end

	return touched
end

function Net:resetSag()
	self.sag = 0
	self.sagVel = 0
end

return Net
]=] },
	["shared/Physics/Pitch"] = { class = "ModuleScript", source = [=[
--[[
	Pitch — saha geometrisi ve çizgi/kale olayları.

	Saha 105 x 68 m, merkez orijinde:
	  x ∈ [-52.5, +52.5]  (uzunluk)
	  z ∈ [-34, +34]      (genişlik)
	  Ev sahibi takım +x yönüne hücum eder ("home" kalesi +x'te).

	"Top çizgiyi geçti" kuralı gerçek futbolla aynı: topun TAMAMI çizgiyi geçmeli,
	yani merkez çizginin r kadar ötesine ulaşmalı. Bu yüzden kale/taç tespiti
	top yarıçapını hesaba katar.
]]

local Config = require(script.Parent.Parent.Config)
local Vec3 = require(script.Parent.Parent.Core.Vec3)

local Pitch = {}
local P = Config.PITCH

Pitch.halfLength = P.halfLength
Pitch.halfWidth = P.halfWidth
Pitch.goalHalfWidth = P.goalHalfWidth
Pitch.goalHeight = P.goalHeight

-- Saha içinde mi? (çizgiler dahil)
function Pitch.isInside(pos)
	return math.abs(pos.x) <= P.halfLength and math.abs(pos.z) <= P.halfWidth
end

-- Top tamamen saha dışına çıktı mı? (oyun durur: taç/korner/kale vuruşu)
function Pitch.isOutOfPlay(pos, radius)
	local r = radius or 0
	return math.abs(pos.x) > P.halfLength + r or math.abs(pos.z) > P.halfWidth + r
end

--[[
	Kale çizgisi geçildi mi?
	fromPos -> toPos arasında x = ±(halfLength + r) düzlemini kesen noktayı bulur,
	o noktada top kale ağzının içinde ve üst direğin altında mı diye bakar.
	Dönüş: "home" (+x kalesine gol = ev sahibi attı), "away" (-x kalesi), ya da nil.
]]
function Pitch.goalCrossed(fromPos, toPos, radius)
	local r = radius or 0
	local plane = P.halfLength + r

	for _, side in ipairs({ 1, -1 }) do
		local target = side * plane
		local x0, x1 = fromPos.x, toPos.x
		if (x0 - target) * (x1 - target) <= 0 and x1 ~= x0 then
			local t = (target - x0) / (x1 - x0)
			if t >= 0 and t <= 1 then
				local z = fromPos.z + (toPos.z - fromPos.z) * t
				local y = fromPos.y + (toPos.y - fromPos.y) * t
				if math.abs(z) < P.goalHalfWidth - r and y < P.goalHeight and y > -r then
					return side == 1 and "home" or "away"
				end
			end
		end
	end
	return nil
end

-- Top kale ağının içinde mi? (gol sonrası topu tutmak için)
function Pitch.isInsideGoal(pos)
	return math.abs(pos.x) > P.halfLength and math.abs(pos.z) < P.goalHalfWidth and pos.y < P.goalHeight
end

-- Oyun dışı türü. "corner"/"goalKick" ayrımı son dokunan takıma bağlı olduğu için
-- maç mantığında (Adım 5) çözülür; burada sadece çizgi sınıflandırılır.
function Pitch.classifyOutOfPlay(pos, radius)
	local r = radius or 0
	if math.abs(pos.z) > P.halfWidth + r then
		return "touchLine"
	end
	if math.abs(pos.x) > P.halfLength + r then
		return "goalLine"
	end
	return nil
end

--[[ Direk ve üst direk geometrisi: Colliders modülünün kullandığı kapsüller.
	Kale çizgisi x = ±52.5; direkler tam çizgi üzerinde, yükseklik 2.44 m. ]]
function Pitch.buildObstacles(cfg)
	local c = cfg or Config
	local PP = c.PITCH
	local list = {}

	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * PP.halfLength
		-- Yan direkler
		for _, sz in ipairs({ -1, 1 }) do
			list[#list + 1] = {
				kind = "post",
				a = Vec3.new(x, 0, sz * PP.goalHalfWidth),
				b = Vec3.new(x, PP.goalHeight, sz * PP.goalHalfWidth),
				radius = PP.postRadius,
			}
		end
		-- Üst direk
		list[#list + 1] = {
			kind = "crossbar",
			a = Vec3.new(x, PP.goalHeight, -PP.goalHalfWidth),
			b = Vec3.new(x, PP.goalHeight, PP.goalHalfWidth),
			radius = PP.crossbarRadius,
		}
	end

	return list
end

-- Saha üzerinde deterministik başlangıç pozisyonları (Adım 3: diziliş).
function Pitch.kickoffSpot(side)
	return Vec3.new(side * 1.0, Config.BALL.radius, 0)
end

-- Oyuncu pozisyonunun sahanın içine kırpılması (AI taşmasın).
function Pitch.clampPosition(pos, margin)
	local m = margin or 1.0
	return Vec3.new(
		math.max(-P.halfLength + m, math.min(P.halfLength - m, pos.x)),
		pos.y,
		math.max(-P.halfWidth + m, math.min(P.halfWidth - m, pos.z))
	)
end

-- Sahanın önemli noktaları (Adım 3+: diziliş, korner, penaltı).
Pitch.points = {
	center = Vec3.new(0, 0, 0),
	penaltySpotHome = Vec3.new(P.halfLength - P.penaltySpot, 0, 0),
	penaltySpotAway = Vec3.new(-(P.halfLength - P.penaltySpot), 0, 0),
	goalHome = Vec3.new(P.halfLength, 0, 0),
	goalAway = Vec3.new(-P.halfLength, 0, 0),
}

return Pitch
]=] },
	["shared/Player/BallControl"] = { class = "ModuleScript", source = [=[
--[[
	BallControl — oyuncu ile top arasındaki ilişki (Adım 3'ün kalbi).

	Gerçek futbolcu topu "sürekli itmez"; saniyede ~3 kez dokunur, top öne kaçar,
	direnç onu yavaşlatır, oyuncu yetişir. Bu modül o ritmi kurar:

	  * DOKUNUŞ (touch): top ayak mesafesindeyse ve oyuncu koşuyorsa, topu
	    ileri doğru oyuncu hızının biraz üstünde iter. Dokunuşlar arası en az
	    `touchInterval` (0.34 s) vardır.
	  * GÖVDE ÇARPMASI: top oyuncunun içinden geçemez; Body modülü bağıl hızla
	    yansıtır (koşan oyuncu topa hız katar).
	  * KAPATMA (trap): hızlı gelen topu duran oyuncu yumuşatır (ilk dokunuş).
	  * SPRINT CEZASI: hızlı koşarken dokunuş gücü düşer -> top kontrolden kaçar.
	    Bu, "top sürerken yavaşlamak zorundasın" hissini verir.

	Roblox API'si kullanmaz -> testte ve sunucuda aynı kod.
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)
local Body = require(script.Parent.Parent.Physics.Body)

local BallControl = {}
BallControl.__index = BallControl

local min, max = math.min, math.max

function BallControl.new(cfg)
	return setmetatable({
		cfg = cfg,
		lastTouch = -999,
		touches = 0,
		traps = 0,
		kicks = 0,
	}, BallControl)
end

-- Oyuncu durumunu toplar: { pos (y=0), vel, facing, speed }
function BallControl.playerState(positionStuds, velocityStuds, facing, studsPerMeter)
	local s = 1 / studsPerMeter
	return {
		pos = Vec3.new(positionStuds.X * s, 0, positionStuds.Z * s),
		vel = Vec3.new(velocityStuds.X * s, 0, velocityStuds.Z * s),
		facing = facing,
		speed = math.sqrt(velocityStuds.X * velocityStuds.X + velocityStuds.Z * velocityStuds.Z) * s,
	}
end

--[[ Ana güncelleme. Dönüş: "touch" | "trap" | "body" | nil ]]
function BallControl:update(ball, player, now)
	local BC = self.cfg.BALL_CONTROL
	local r = ball.cfg.BALL.radius

	local dx = ball.pos.x - player.pos.x
	local dz = ball.pos.z - player.pos.z
	local dist = math.sqrt(dx * dx + dz * dz)
	local playerSpeed = player.speed or Vec3.lengthHorizontal(player.vel)
	local ballSpeed = Vec3.lengthHorizontal(ball.vel)

	-- 1) Gövde: top oyuncunun içinden geçemez (240 Hz'de sim içinde de çağrılır;
	--    burada yalnızca kare bazlı güvenlik ağı).
	local hit = Body.collide(ball, {
		pos = player.pos,
		vel = player.vel,
		radius = BC.bodyRadius,
		height = BC.bodyHeight,
		restitution = 0.35,
		friction = 0.25,
	})
	if hit then
		self.lastTouch = now
		return "body"
	end

	if dist > BC.dribbleReach or ball.pos.y > 1.1 then
		return nil
	end

	local flatDir
	if dist > 1e-6 then
		flatDir = Vec3.new(dx / dist, 0, dz / dist)
	else
		flatDir = Vec3.fromYaw(player.facing)
	end
	local facingDir = Vec3.fromYaw(player.facing)
	local aheadDot = Vec3.dot(flatDir, facingDir) -- 1: tam önünde, -1: arkasında

	-- 2) Sprint cezası: hızlı koşarken dokunuş "aşırı" olur -> top öne kaçar
	local sprintFactor = math.max(0, math.min(1, (playerSpeed - 4.5) / 3.1))
	local controlFactor = 1 + BC.sprintTouchPenalty * sprintFactor

	-- 3) Dokunuş: top önde, oyuncu hareketli, top oyuncudan yavaş
	if
		playerSpeed > 0.6
		and aheadDot > 0.15
		and ballSpeed < playerSpeed + 3.0
		and (now - self.lastTouch) >= BC.touchInterval
	then
		--[[ Dokunuş hızını tahminle değil ÇÖZEREK buluyoruz:
		     Top, bir sonraki dokunuşa kadar (touchInterval) oyuncuyla AYNI mesafeyi
		     katetmeli ki aradaki boşluk sabit kalsın.
		       v_top*t - 0.5*a*t² = v_oyuncu*t     (a = yuvarlanma direnci)
		     => v_top = v_oyuncu + 0.5*a*t
		     Bu yüzden iyi bir top sürücü neredeyse hiç hız kaybetmez; top ayağından
		     kaçmaz. Sprint cezası bu hedefi büyütür (aşırı vurulan dokunuş). ]]
		local dir = Vec3.unit(Vec3.add(Vec3.scale(facingDir, 0.80), Vec3.scale(flatDir, 0.20)))
		local a = self.cfg.BALL.rollResistance * self.cfg.GRAVITY
		local baseSpeed = playerSpeed + 0.5 * a * BC.touchInterval
		local targetSpeed = (baseSpeed + BC.touchForward) * controlFactor
		if targetSpeed > BC.maxTouchSpeed then
			targetSpeed = BC.maxTouchSpeed
		end

		ball.vel = Vec3.new(dir.x * targetSpeed, 0, dir.z * targetSpeed)
		-- Yuvarlanma spini (kaymadan yuvarlanma koşulu)
		ball.spin = Vec3.new(ball.vel.z / r, ball.spin.y, -ball.vel.x / r)
		ball.mode = "ground"
		ball.pos = Vec3.withY(ball.pos, r)

		self.lastTouch = now
		self.touches = self.touches + 1
		return "touch"
	end

	-- 4) Kapatma (trap): hızlı gelen top, duran oyuncunun ayağında söner
	if ballSpeed > BC.trapSpeedThreshold and dist < BC.trapRadius and playerSpeed < 2.2 then
		local factor = BC.trapFactor + 0.12 * (1 - math.min(1, ballSpeed / 25))
		ball.vel = Vec3.scale(ball.vel, factor)
		ball.spin = Vec3.scale(ball.spin, 0.4)
		self.lastTouch = now
		self.traps = self.traps + 1
		return "trap"
	end

	return nil
end

-- Şut atılabilir mi? (mesafe + yükseklik)
function BallControl:canKick(ball, player)
	local BC = self.cfg.BALL_CONTROL
	local dx = ball.pos.x - player.pos.x
	local dz = ball.pos.z - player.pos.z
	local dist = math.sqrt(dx * dx + dz * dz)
	return dist <= BC.kickReach and ball.pos.y <= BC.kickHeight
end

-- Güç -> hız eşlemesi (0..1 -> minKickSpeed..maxKickSpeed)
function BallControl:speedForCharge(charge)
	local BC = self.cfg.BALL_CONTROL
	local c = math.max(0, math.min(1, charge or 0.5))
	return BC.minKickSpeed + (BC.maxKickSpeed - BC.minKickSpeed) * c
end

-- Şutu uygular.
function BallControl:kick(ball, player, velocity, spin, now)
	ball.vel = velocity
	ball.spin = spin or Vec3.new(0, 0, 0)
	ball.mode = (velocity.y > 1e-6) and "air" or "ground"
	self.lastTouch = now or 0
	self.kicks = self.kicks + 1
	return true
end

return BallControl
]=] },
	["shared/Player/Keeper"] = { class = "ModuleScript", source = [=[
--[[
	Keeper — kaleci AI (tek kale, yarım saha provası için).

	Davranış:
	  * Top uzaktayken kale çizgisi önünde açıyı kapatır (topun z'sini takip eder).
	  * Top kaleye geliyorsa, topun GELECEK konumunu simülasyon kopyasıyla
	    hesaplar (Ball:clone + step) ve o noktaya atlar (dive).
	  * Tepki süresi vardır (reactionTime): anında değil, gecikmeyle okur.
	  * Gövdesi fiziksel engeldir: top ona çarparsa seker (Body modülü).

	Kaleci "topu yakaladı" mı? Top gövdeye çarpıp hızının büyük kısmını
	kaybettiyse ve yönü kaleye gitmiyorsa kurtarış sayılır.
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)

local Keeper = {}
Keeper.__index = Keeper

local abs = math.abs
local min = math.min
local max = math.max

function Keeper.new(cfg, side)
	local K = cfg.KEEPER
	local P = cfg.PITCH
	local lineX = (side or 1) * (P.halfLength - K.lineOffset)
	return setmetatable({
		cfg = cfg,
		side = side or 1,
		pos = Vec3.new(lineX, 0, 0),
		vel = Vec3.new(0, 0, 0),
		lineX = lineX,
		state = "idle", -- idle | track | dive
		reactionTimer = 0,
		diveTimer = 0,
		diveElapsed = 0,
		diveTarget = nil,
		arrival = nil,
		hits = 0,
		saves = 0,
		conceded = 0,
		-- Gövde tablosu KALICI: Body.collide içindeki hit sayacı birikmeli,
		-- her adımda sıfırlanmamalı (kurtarış sayımı buna bağlı).
		body = {
			pos = Vec3.new(lineX, 0, 0),
			vel = Vec3.new(0, 0, 0),
			radius = K.radius,
			height = K.height,
			restitution = K.restitution,
			friction = 0.35,
			hits = 0,
		},
	}, Keeper)
end

-- Topun kale düzlemine varacağı noktayı simülasyon kopyasıyla tahmin eder.
-- Dönüş: { z = yanal konum, y = yükseklik, t = varış süresi (s) }
function Keeper:predictArrival(ball, maxSeconds)
	local copy = ball:clone()
	-- Tahmin 120 Hz'de yapılır: kaleci için yeterli hassasiyet, yarı maliyet
	local dt = 1 / 120
	local steps = math.floor((maxSeconds or 2.5) / dt)
	local P = self.cfg.PITCH
	local planeX = P.halfLength - self.cfg.KEEPER.lineOffset
	for i = 1, steps do
		copy:step(dt)
		if copy.pos.x * self.side >= planeX then
			return { z = copy.pos.z, y = copy.pos.y, t = i * dt }
		end
		if abs(copy.pos.x) > P.halfLength + P.goalDepth or copy.pos.y < -0.5 then
			break
		end
	end
	return { z = copy.pos.z, y = copy.pos.y, t = steps * dt }
end

-- Geriye dönük: sadece yanal varış noktası
function Keeper:predictArrivalZ(ball, maxSeconds)
	return self:predictArrival(ball, maxSeconds).z
end

--[[ Bir adım. Dönüş: çarpışma için gövde tanımı. ]]
function Keeper:step(ball, dt)
	local K = self.cfg.KEEPER
	local P = self.cfg.PITCH

	-- Top kaleye mi geliyor?
	local towardGoal = ball.vel.x * self.side > 2.5
	-- Kale çizgisine kalan mesafe (her iki kale tarafında da pozitif).
	-- Eski formül ((side * halfLength) - pos.x) side=-1'de NEGATIF oluyordu:
	-- batı kalesindeki kaleci hiç dalmıyordu (ayna tarafı ölüydü).
	local distanceToLine = P.halfLength - self.side * ball.pos.x

	local targetZ = 0
	local wantDive = false

	if towardGoal and distanceToLine > 0 and distanceToLine < P.halfLength then
		self.reactionTimer = self.reactionTimer + dt
		if self.reactionTimer >= K.reactionTime then
			local arrival = self:predictArrival(ball, 2.5)
			-- Kaleci hatası: tepki mesafesiyle artan küçük sapma (deterministik)
			targetZ = max(-K.reachZ, min(K.reachZ, arrival.z))
			self.arrival = arrival
			wantDive = true
		else
			targetZ = max(-K.reachZ, min(K.reachZ, ball.pos.z))
		end
	else
		self.reactionTimer = 0
		-- Açıyı kapat: top z'sinin %60'ı
		targetZ = max(-K.reachZ, min(K.reachZ, ball.pos.z * 0.6))
	end

	-- Hedefe doğru hareket (ivme sınırlı)
	local speedLimit = wantDive and K.diveSpeed or K.maxSpeed
	local accel = wantDive and K.diveAccel or 12
	local dz = targetZ - self.pos.z
	local desiredVel = 0
	if abs(dz) > 0.04 then
		desiredVel = (dz > 0 and 1 or -1) * speedLimit
	end
	local dv = desiredVel - self.vel.z
	local maxDv = accel * dt
	if abs(dv) > maxDv then
		dv = (dv > 0 and 1 or -1) * maxDv
	end
	self.vel = Vec3.new(0, 0, self.vel.z + dv)
	self.pos = Vec3.new(self.lineX, 0, self.pos.z + self.vel.z * dt)

	if self.pos.z < -K.reachZ then
		self.pos = Vec3.new(self.lineX, 0, -K.reachZ)
		self.vel = Vec3.new(0, 0, 0)
	elseif self.pos.z > K.reachZ then
		self.pos = Vec3.new(self.lineX, 0, K.reachZ)
		self.vel = Vec3.new(0, 0, 0)
	end

	if wantDive then
		if self.state ~= "dive" then
			-- Dalış başlıyor: animasyon için hedefi kilitle.
			-- ÖNEMLİ — eksen dönüşümü: KeeperAnim'in sözleşmesi KALECİNİN KENDİ
			-- eksenidir ("+dz = kalecinin sağı"). Oysa targetZ - pos.z DÜNYA z farkıdır.
			-- Kaleci -X'e bakar (side=+1): sağı dünyanın -Z'sidir; +X'e bakar
			-- (side=-1): sağı dünyanın +Z'si. Dünya farkını olduğu gibi verirsek
			-- dalış topun TERSİNE yatar (görülen hata buydu). -side çarpanı dünya
			-- eksenini kalecinin yerel eksenine çevirir.
			self.diveTarget = {
				dz = -self.side * (targetZ - self.pos.z),
				height = (self.arrival and self.arrival.y) or 0.5,
				speed = ball:speed(),
				time = (self.arrival and self.arrival.t) or 1,
			}
			self.diveElapsed = 0
		end
		self.state = "dive"
		self.diveTimer = self.diveTimer + dt
		self.diveElapsed = (self.diveElapsed or 0) + dt
	else
		self.state = abs(self.vel.z) > 0.5 and "track" or "idle"
		self.diveTimer = 0
		self.diveElapsed = 0
		self.diveTarget = nil
	end

	-- Dalış sırasında gövde alçalır (daha geniş ama daha kısa)
	local height = K.height
	if wantDive then
		height = K.height * (1 - 0.35 * min(1, self.diveTimer / 0.45))
	end

	local body = self.body
	body.pos = Vec3.new(self.pos.x, 0, self.pos.z)
	body.vel = Vec3.new(0, 0, self.vel.z)
	-- Dalışta kollar açılır: gövde yarıçapı bir miktar büyür (görsel uzanmayla uyumlu)
	body.radius = K.radius + (wantDive and K.diveReachBonus or 0)
	body.height = height

	return body
end

-- Top gövdeye çarptıktan sonra kurtarış mı, gol mü? (maç mantığı için)
function Keeper:evaluateIncoming(ball)
	if ball.vel.x * self.side > 3 then
		return "incoming"
	end
	return "safe"
end

return Keeper
]=] },
	["shared/Player/Locomotion"] = { class = "ModuleScript", source = [=[
--[[
	Locomotion — oyuncu hareket modeli.

	Roblox'da oyuncuları Humanoid ile yürütmek "gerçekçi" değildir: Humanoid anında
	yön değiştirir, ivme yoktur, yorgunluk yoktur. Burada gerçek spor bilimine yakın
	bir model var:

	  * Hızlanma sınırlı (6.5 m/s²): 0-27 km/h ~1.2 s sürer.
	  * Yavaşlama daha güçlü (9 m/s²).
	  * Dönüş hızı sınırlı: gövde anında dönmez (7 rad/s ≈ 400°/s).
	  * Yorgunluk: sprint atarken stamina düşer, hız tavanı %72'ye kadar iner.
	  * Yön vektörü verilir, gövde açısı ayrı izlenir (animasyon için gerekli).

	Model kara kutu değil: durum (pos, vel, facing, stamina) açıkça tutulur, böylece
	hem sunucu hem istemci aynı girdiyle aynı sonucu üretir (deterministik).
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)

local Locomotion = {}
Locomotion.__index = Locomotion

local abs = math.abs
local min = math.min
local max = math.max

-- Açıyı (-pi, pi] aralığına indirger.
local function wrapAngle(a)
	while a > math.pi do
		a = a - 2 * math.pi
	end
	while a <= -math.pi do
		a = a + 2 * math.pi
	end
	return a
end

Locomotion.wrapAngle = wrapAngle

function Locomotion.new(cfg, position, facing)
	return setmetatable({
		cfg = cfg,
		pos = position or Vec3.new(0, 0, 0),
		vel = Vec3.new(0, 0, 0),
		facing = facing or 0,
		stamina = 1,
		sprinting = false,
	}, Locomotion)
end

function Locomotion:speed()
	return Vec3.lengthHorizontal(self.vel)
end

-- stamina 0..1 -> hız çarpanı
function Locomotion:speedFactor()
	local p = self.cfg.PLAYER
	return p.staminaMinFactor + (1 - p.staminaMinFactor) * self.stamina
end

function Locomotion:maxSpeedNow(sprinting)
	local p = self.cfg.PLAYER
	local m = p.maxSpeed * self:speedFactor()
	if sprinting then
		m = m * p.sprintMultiplier
	end
	return m
end

--[[
	Bir adım ilerlet.
	desiredDir : yön vektörü (uzunluğu önemsiz; yatay bileşen kullanılır)
	sprinting  : bool (verilmezse hız > %55 ise sprint sayılır)
]]
function Locomotion:step(desiredDir, dt, sprinting)
	local p = self.cfg.PLAYER

	local dir = Vec3.horizontal(desiredDir)
	local dirLen = Vec3.length(dir)
	if dirLen > 1e-6 then
		dir = Vec3.scale(dir, 1 / dirLen)
	else
		dir = Vec3.ZERO
	end

	local wantsMove = dirLen > 1e-6
	if sprinting == nil then
		sprinting = wantsMove and self:speed() > p.maxSpeed * 0.55
	end
	self.sprinting = wantsMove and sprinting

	local maxSpeed = self:maxSpeedNow(sprinting)
	local desiredVel = Vec3.scale(dir, maxSpeed)
	local dv = Vec3.sub(desiredVel, self.vel)
	local dvLen = Vec3.length(dv)

	-- Hızlanıyor muyuz, yavaşlıyor muyuz? Hedef hız mevcut hızdan büyükse ivme,
	-- değilse daha güçlü olan yavaşlama kullanılır.
	local accelerating = Vec3.lengthSq(desiredVel) > Vec3.lengthSq(self.vel)
	local rate = accelerating and p.acceleration or p.deceleration
	local maxDv = rate * dt
	if dvLen > maxDv and dvLen > 1e-9 then
		dv = Vec3.scale(dv, maxDv / dvLen)
	end

	self.vel = Vec3.add(self.vel, dv)
	self.pos = Vec3.add(self.pos, Vec3.scale(self.vel, dt))

	-- Gövde yönü: hıza doğru sınırlı hızda döner.
	local speed = Vec3.lengthHorizontal(self.vel)
	if speed > 0.25 then
		local target = Vec3.yaw(self.vel)
		local diff = wrapAngle(target - self.facing)
		local maxTurn = p.turnRate * dt
		self.facing = wrapAngle(self.facing + max(-maxTurn, min(maxTurn, diff)))
	elseif wantsMove then
		-- Duruyorken bile hedef yöne dönmeye başla (ayak yerleşimi/animasyon).
		local target = Vec3.yaw(dir)
		local diff = wrapAngle(target - self.facing)
		local maxTurn = p.turnRate * dt
		self.facing = wrapAngle(self.facing + max(-maxTurn, min(maxTurn, diff)))
	end

	-- Yorgunluk
	local effort = speed / p.maxSpeed
	if effort > 0.55 then
		local intensity = (effort - 0.55) / 0.45
		self.stamina = max(0, self.stamina - p.staminaDrainSprint * intensity * dt)
	else
		self.stamina = min(1, self.stamina + p.staminaRegen * dt)
	end

	return self
end

-- Topa ulaşmak için gereken süre tahmini (AI ve kaleci için, Adım 6).
function Locomotion:timeToReach(targetPos)
	local dist = Vec3.distanceHorizontal(self.pos, targetPos)
	local p = self.cfg.PLAYER
	local v = self:speed()
	if dist <= 0 then
		return 0
	end
	-- Sabit ivmeyle: d = v*t + 0.5*a*t²  ->  t çözümü
	local a = p.acceleration
	local disc = v * v + 2 * a * dist
	local t = (-v + math.sqrt(disc)) / a
	local tAtMax = (self:maxSpeedNow(true) - v) / a
	if t > tAtMax then
		local covered = v * tAtMax + 0.5 * a * tAtMax * tAtMax
		t = tAtMax + (dist - covered) / self:maxSpeedNow(true)
	end
	return t
end

return Locomotion
]=] },
	["shared/Player/Striker"] = { class = "ModuleScript", source = [=[
--[[
	Striker — sunucu tarafındaki şutçu NPC'si (prosedürel iskeletle çizilir).

	Neden NPC? Animasyonun tamamı sunucuda, kodla üretiliyor; gerçek bir Roblox
	karakteri kendi Animate script'iyle çakışır. Bu şutçu:
	  * topa yürür (adım döngüsü gerçek hıza bağlı: kayma yok),
	  * ayak mesafesine gelince topun GERÇEK konumuna göre şut pozisyonu seçer,
	  * temas anında (0.24 s) top ayrılır — animasyon nedensel, süs değil,
	  * her şutta farklı köşe/yükseklik hedefler: kaleci her seferinde farklı atlar.

	Roblox API'si kullanmaz: aynı kod testte ölçülebilir.
]]

local Vec3 = require(script.Parent.Parent.Core.Vec3)
local WalkCycle = require(script.Parent.Parent.Anim.WalkCycle)
local KickAnim = require(script.Parent.Parent.Anim.KickAnim)
local Ease = require(script.Parent.Parent.Anim.Ease)
local Config = require(script.Parent.Parent.Config)

local Striker = {}
Striker.__index = Striker

Striker.REACH = 1.00 -- şut için topun ayağa uzaklığı (m)
Striker.WALK_SPEED = 5.2 -- yaklaşma hızı (m/s)
Striker.COOLDOWN = 1.4 -- şutlar arası bekleme (s)
Striker.MAX_WAIT = 1.2 -- hareketli topa bekleme süresi (s)

local clamp01 = Ease.clamp01
local SHOT_TYPES = Config and Config.SHOT and Config.SHOT.types or { "instep" }

-- Kaleci pozisyonuna göre dinamik şut hedefi seçer.
-- Kaleci sola genişlerse (dz < -1) sağ köşeye, sağa genişlerse (dz > 1) sol köşeye,
-- ortadaysa (-1 <= dz <= 1) yüksek köşeye veya ortaya döngüyle şut atar.
function Striker:selectTarget(keeperPos)
	local goal = self:goalPoint()
	local dz = keeperPos and keeperPos.z or 0

	local targetZ, targetY
	if dz < -1.0 then
		-- Kaleci solda -> sağ alt köşe
		targetZ = 2.55
		targetY = 0.32
	elseif dz > 1.0 then
		-- Kaleci sağda -> sol alt köşe
		targetZ = -2.40
		targetY = 0.32
	else
		-- Kaleci ortada -> yüksek köşe / orta (döngüyle değiştir)
		self.aimIndex = (self.aimIndex % 2) + 1
		if self.aimIndex == 1 then
			targetZ = -2.40
			targetY = 1.90
		else
			targetZ = 1.05
			targetY = 0.85
		end
	end

	return Vec3.new(goal.x, targetY, targetZ)
end

function Striker.new(cfg, opts)
	opts = opts or {}
	local P = cfg.PITCH
	local side = opts.side or 1
	local pos = opts.pos or Vec3.new(P.halfLength * 0.30, 0, 0.8)
	return setmetatable({
		cfg = cfg,
		side = side,
		pos = pos,
		vel = Vec3.new(0, 0, 0),
		facing = Vec3.yaw(Vec3.new(side, 0, 0)),
		state = "idle", -- idle | approach | wait | kick
		kick = nil,
		kickT = 0,
		cooldown = 0,
		waitTimer = 0,
		walkPhase = 0,
		time = 0,
		shots = 0,
		aimIndex = 0,
		shotIndex = 0,
		target = nil,
		speed = 0,
	}, Striker)
end

function Striker:goalPoint()
	local P = self.cfg.PITCH
	return Vec3.new(self.side * P.halfLength, 0, 0)
end

-- Şut için gereken geometri: topun ayağa göre yan/ön/ileri bileşenleri
function Striker:ballGeometry(ball)
	local toBall = Vec3.sub(ball.pos, self.pos)
	local forward = Vec3.new(math.cos(self.facing), 0, math.sin(self.facing))
	local right = Vec3.cross(forward, Vec3.new(0, 1, 0))
	local flat = Vec3.withY(toBall, 0)
	return {
		dist = Vec3.length(flat),
		lateral = Vec3.dot(flat, right),
		forward = Vec3.dot(flat, forward),
		height = ball.pos.y,
	}
end

function Striker:beginKick(ball, keeperPos)
	local geo = self:ballGeometry(ball)
	local goal = self:goalPoint()
	local dx = goal.x - ball.pos.x
	local dz = goal.z - ball.pos.z
	local distGoal = math.sqrt(dx * dx + dz * dz)

	-- Kaleci pozisyonuna göre dinamik hedef
	self.target = self:selectTarget(keeperPos)

	-- Uzaktan sert, yakından kontrollü
	local charge = clamp01(0.42 + distGoal / 42)
	local speed = 15 + 11 * charge

	-- Vuruş türünü döngüyle değiştir (her şutta farklı biomekanik görünüm)
	self.shotIndex = (self.shotIndex % #SHOT_TYPES) + 1
	local shotType = SHOT_TYPES[self.shotIndex]

	-- Ayak otomatik (topun yanına göre) veya kalce yönüne göre tercih
	local foot = nil
	if geo.lateral > 0.2 then
		foot = "R"
	elseif geo.lateral < -0.2 then
		foot = "L"
	end

	self.kick = KickAnim.new({
		ballHeight = geo.height,
		ballLateral = geo.lateral,
		ballForward = geo.forward,
		charge = charge,
		shotType = shotType,
		foot = foot,
	})
	self.kickT = 0
	self.speed = speed
	self.state = "kick"
	self.shots = self.shots + 1
	return self.kick
end

--[[ Bir adım. Dönüş: nil veya {
		type = "shoot", kick = KickAnim, target = Vec3 (metre), speed = m/s } ]]
function Striker:step(dt, ball, keeper)
	self.time = self.time + dt
	if self.cooldown > 0 then
		self.cooldown = math.max(0, self.cooldown - dt)
	end

	-- 1) Şut animasyonu sürüyor: sadece zaman ilerler
	if self.kick then
		local before = self.kickT
		self.kickT = self.kickT + dt
		-- Hazırlık boyunca ayak yere basar; itiş hızı sabit kalır (gerçekçi)
		local event = nil
		if before < KickAnim.CONTACT_TIME and self.kickT >= KickAnim.CONTACT_TIME then
			event = {
				type = "shoot",
				kick = self.kick,
				target = self.target,
				speed = self.speed,
				charge = self.kick.charge,
			}
		end
		if self.kickT >= self.kick:duration() then
			self.kick = nil
			self.kickT = 0
			self.cooldown = Striker.COOLDOWN
			self.state = "idle"
		end
		-- Takip sırasında hafif ileri hareket (topu bırakıp durmak yerine gevolg devam eder)
		local followDir = Vec3.unit(Vec3.withY(Vec3.sub(self.target, self.pos), 0))
		self.vel = Vec3.scale(followDir, Striker.WALK_SPEED * 0.30)
		self.pos = Vec3.add(self.pos, Vec3.scale(self.vel, dt))
		return event
	end

	-- 2) Topa yaklaş
	local geo = self:ballGeometry(ball)
	local ballSpeed = ball:speed()

	if geo.dist > Striker.REACH then
		local dir = Vec3.unit(Vec3.withY(Vec3.sub(ball.pos, self.pos), 0))
		local want = Striker.WALK_SPEED
		-- Yavaşlayarak yaklaş: hedefe 0.4 m kalınca yavaşla
		if geo.dist < 2.2 then
			want = Striker.WALK_SPEED * clamp01((geo.dist - Striker.REACH) / 1.2) + 0.6
		end
		self.vel = Vec3.scale(dir, want)
		self.pos = Vec3.add(self.pos, Vec3.scale(self.vel, dt))
		self.facing = Vec3.yaw(dir)
		self.walkPhase = (self.walkPhase + Vec3.length(self.vel) * dt / WalkCycle.STRIDE) % 1
		self.state = "approach"
		return nil
	end

	self.vel = Vec3.new(0, 0, 0)

	-- 3) Top hızlıysa bekle (ayağına gelsin)
	if ballSpeed > 1.2 then
		self.waitTimer = self.waitTimer + dt
		self.state = "wait"
		if self.waitTimer < Striker.MAX_WAIT then
			return nil
		end
	else
		self.waitTimer = 0
	end

	-- 4) Top kaleye dönük mü? Değilse önce etrafından dolaş (kale arkasına geçme)
	if self.cooldown > 0 then
		self.state = "idle"
		return nil
	end

	self.facing = Vec3.yaw(Vec3.withY(Vec3.sub(self:goalPoint(), self.pos), 0))
	self:beginKick(ball, keeper and keeper.pos or nil)
	return nil
end

-- Görsel poz: şut sürüyorsa şut, değilse adım döngüsü
function Striker:pose()
	if self.kick then
		return self.kick:sample(self.kickT).pose
	end
	local speed = Vec3.length(self.vel)
	return WalkCycle.sample(speed, self.walkPhase, self.time)
end

function Striker:isKicking()
	return self.kick ~= nil
end

return Striker
]=] },
	["shared/Sim"] = { class = "ModuleScript", source = [=[
--[[
	Sim — sabit adımlı simülasyon çekirdeği (fixed timestep).

	Neden sabit adım?
	  Değişken dt ile çalışan fizik, kare hızına göre farklı sonuç üretir: 30 FPS'te
	  oynayan oyuncunun şutu 144 FPS'tekinden farklı yere gider. Rekabetçi bir
	  futbol oyununda bu kabul edilemez. Bu yüzden:

	    * Simülasyon her zaman 1/240 s'lik adımlarla ilerler.
	    * Kare süresi bir "akümülatörde" birikir, yeterince birikince tick çalışır.
	    * Kalan artık zaman bir sonraki kareye taşınır (görsel interpolasyon için).

	Determinizm garantisi: aynı tohum + aynı tick dizisi = aynı sonuç (bit-bit).
]]

local Config = require(script.Parent.Config)
local Vec3 = require(script.Parent.Core.Vec3)
local Rng = require(script.Parent.Core.Rng)
local Ball = require(script.Parent.Physics.Ball)
local Pitch = require(script.Parent.Physics.Pitch)
local Colliders = require(script.Parent.Physics.Colliders)
local Body = require(script.Parent.Physics.Body)

local Sim = {}
Sim.__index = Sim

function Sim.new(opts)
	opts = opts or {}
	local cfg = opts.config or Config
	local self = setmetatable({
		cfg = cfg,
		rng = Rng.new(opts.seed or 1),
		ball = Ball.new(cfg, Vec3.new(0, cfg.BALL.radius, 0)),
		obstacles = Pitch.buildObstacles(cfg),
		bodies = {}, -- hareketli gövdeler (oyuncu/kaleci) — sunucu her karede günceller
		nets = {}, -- file/ağ fizikleri
		ticks = 0, -- islenen sabit adim sayisi (metot adiyla cakismasin)
		time = 0,
		accumulator = 0,
		lastGoal = nil,
		lastSubsteps = 0,
	}, Sim)
	return self
end

-- Tek deterministik adım.
function Sim:tick()
	local dt = self.cfg.FIXED_DT
	local prev = self.ball.pos

	self.ball:step(dt)

	-- Direk / üst direk çarpışması (kale tespitinden ÖNCE: direğe çarpan top gol değil)
	Colliders.resolve(self.ball, self.obstacles, prev)

	-- Hareketli gövdeler (oyuncu bacakları, kaleci) — 240 Hz'de, adım içi hareket
	-- doğrusu ile çarpıştırılır ki hızlı şut oyuncunun içinden geçmesin.
	for i = 1, #self.bodies do
		Body.collide(self.ball, self.bodies[i])
	end

	-- File: top kaleye girdiğinde ağ onu yutar (hız sönümü + esneme)
	for i = 1, #self.nets do
		self.nets[i]:stepBall(self.ball, dt)
	end

	-- Kale tespiti (top bu adımda kale çizgisini geçtiyse)
	local side = Pitch.goalCrossed(prev, self.ball.pos, self.cfg.BALL.radius)
	if side then
		self.lastGoal = { side = side, tick = self.ticks + 1, pos = self.ball.pos }
	end

	self.ticks = self.ticks + 1
	self.time = self.ticks * dt
end

function Sim:advanceTicks(n)
	for _ = 1, n do
		self:tick()
	end
	return self
end

-- Saniye cinsinden ilerlet (testlerde ve sunucu otoritesinde kullanışlı).
function Sim:advance(seconds)
	local n = math.floor(seconds * self.cfg.SIM_HZ + 0.5)
	return self:advanceTicks(n)
end

--[[
	Kare bazlı güncelleme: frameDt kadar gerçek zamanı simüle eder.
	Dönüş: bu karede çalışan tick sayısı.
	Spiral of death koruması: tek karede en fazla MAX_FRAME_DT işlenir.
]]
function Sim:update(frameDt)
	local cfg = self.cfg
	if frameDt < 0 then
		frameDt = 0
	end
	if frameDt > cfg.MAX_FRAME_DT then
		frameDt = cfg.MAX_FRAME_DT
	end

	self.accumulator = self.accumulator + frameDt
	local steps = 0
	while self.accumulator >= cfg.FIXED_DT and steps < cfg.MAX_SUBSTEPS do
		self:tick()
		self.accumulator = self.accumulator - cfg.FIXED_DT
		steps = steps + 1
	end
	-- Çok geride kaldıysak artığı at (yavaş cihazlarda birikmesin)
	if steps >= cfg.MAX_SUBSTEPS then
		self.accumulator = 0
	end
	self.lastSubsteps = steps
	return steps
end

-- Görsel interpolasyon için ara durum (0 = son tick, 1 = bir sonraki tick).
function Sim:interpolatedBall()
	local alpha = self.accumulator / self.cfg.FIXED_DT
	local b = self.ball
	local pred = b:clone()
	pred:step(self.cfg.FIXED_DT)
	return Vec3.lerp(b.pos, pred.pos, alpha)
end

return Sim
]=] },
	["shared/World/SceneBuilder"] = { class = "ModuleScript", source = [=[
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

	-- Doğma noktası: topun BİR ADIM gerisinde. Eskiden 11.5 m uzaktaydı: oyuncu
	-- "şut çekemiyorum" diyordu çünkü menzil kapısı (kickReach) sessizce reddediyordu.
	-- Artık ilk SPACE'te şut atılabilir; kale ve kaleci zaten kadrajda.
	local spawnX = half and (ballStart.X / S - 1.5) or 0
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
]=] },
}

--[[
	KURULUM MANTIĞI (tek kurulum dosyasının gövdesi)

	Yukarıdaki SOURCES tablosunu okur, oyuna yazar, sahneyi kurar.
	Roblox Studio'nun Command Bar'ında çalıştırılmalıdır (Script.Source yazma
	yetkisi orada vardır).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")

local ROOTS = {
	shared = ReplicatedStorage,
	server = ServerScriptService,
	client = StarterPlayerScripts,
}

local ROOT_FOLDER_NAMES = {
	shared = "Shared",
	server = "Server",
	client = "Client",
}

local function ensureFolder(parent, name)
	if not parent then
		return nil
	end
	local existing = parent:FindFirstChild(name)
	if existing and not existing:IsA("Folder") then
		existing:Destroy()
		existing = nil
	end
	if not existing then
		existing = Instance.new("Folder")
		existing.Name = name
		existing.Parent = parent
	end
	return existing
end

local function ensureScript(parent, name, className)
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName ~= className then
		existing:Destroy()
		existing = nil
	end
	if not existing then
		existing = Instance.new(className)
		existing.Name = name
		existing.Parent = parent
	end
	return existing
end

local function splitPath(p)
	local parts = {}
	for part in string.gmatch(p, "[^/]+") do
		table.insert(parts, part)
	end
	return parts
end

-- 1) Scriptleri yaz ---------------------------------------------------------
local keys = {}
for key in pairs(SOURCES) do
	table.insert(keys, key)
end
table.sort(keys)

local written, sourceFailed = 0, 0

for _, key in ipairs(keys) do
	local entry = SOURCES[key]
	local rootName, rest = string.match(key, "^(%w+)/(.+)$")
	local root = rootName and ROOTS[rootName]

	if root and rest then
		local folderName = ROOT_FOLDER_NAMES[rootName]
		local parent = folderName and ensureFolder(root, folderName) or root

		local parts = splitPath(rest)
		for i = 1, #parts - 1 do
			parent = ensureFolder(parent, parts[i])
		end

		local name = parts[#parts]
		if parent and name then
			local inst = ensureScript(parent, name, entry.class)
			local ok = pcall(function()
				inst.Source = entry.source
			end)
			if ok then
				written = written + 1
			else
				sourceFailed = sourceFailed + 1
			end
		end
	else
		warn("[FootballSim] Taninmayan modul yolu: " .. tostring(key))
	end
end

-- 2) Sahneyi kur ------------------------------------------------------------
local sceneOk, sceneErr = pcall(function()
	local SceneBuilder = require(ReplicatedStorage.Shared.World.SceneBuilder)
	SceneBuilder.build()
end)

-- 3) Rapor ------------------------------------------------------------------
local msg = {}
table.insert(msg, "==================================================")
table.insert(msg, "  FootballSim kurulumu")
table.insert(msg, "==================================================")
table.insert(msg, string.format("  Scriptler : %d yazildi, %d basarisiz", written, sourceFailed))
table.insert(msg, "  Sahne     : " .. (sceneOk and "kuruldu (cim, cizgiler, kaleler, ag, top, isik)" or ("HATA - " .. tostring(sceneErr))))
table.insert(msg, "")
table.insert(msg, "  Simdi Play'e bas. SPACE ile sut cekebilirsin.")
table.insert(msg, "  Top fizigi: 240 Hz, kendi motorumuz (Roblox fizigi kullanilmaz).")
table.insert(msg, "==================================================")
print(table.concat(msg, "\n"))

if sourceFailed > 0 then
	warn("[FootballSim] " .. tostring(sourceFailed) .. " script yazilamadi. Command Bar yerine")
	warn("bir Script icinden calistirdiysaniz Source yazma yetkisi yoktur;")
	warn("Command Bar'da calistirin ya da Rojo kullanin (rojo serve).")
end
