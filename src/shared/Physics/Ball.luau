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
