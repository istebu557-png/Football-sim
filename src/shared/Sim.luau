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
