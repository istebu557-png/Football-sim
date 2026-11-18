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
