# Roblox Futbol Simülasyon Motoru

Roblox için **gerçekçi** bir futbol motoru, adım adım inşa ediliyor.
**Adım 1** (top fiziği), **Adım 2** (sahne + tek kurulum) ve
**Adım 3** (oyuncu–top ve top–file ilişkisi) tamam.

> Luau · Rojo uyumlu · Fizik: kendi deterministik entegratörümüz (240 Hz)
> **Şu anki kapsam:** yarım saha, 1 kale, 1 kaleci, 1 şutçu (11v11 sonra).

---

## Tek kurulum: bir kod, tüm oyun

`install/FootballSim_Install.lua` tek dosyadır ve her şeyi oyuna aktarır.

1. Roblox Studio'da oyunu aç.
2. `View → Command Bar` aç.
3. Dosyanın **tamamını** kopyala, komut çubuğuna yapıştır, Enter.
4. Play'e bas. `WASD` ile koş, `SPACE` basılı tut → güç → bırak → şut.
   `R` topu sıfırlar.

Kurulum: 13 ModuleScript (`ReplicatedStorage/Shared/**`), `SimLoop` (Script,
`ServerScriptService/Server`), `BallView` (LocalScript, `StarterPlayerScripts/Client`),
yarım saha + kale + ağ + kaleci + top + ışık (`Workspace/FootballPitch`,
`Workspace.MatchBall`). İdempotenttir; tekrar çalıştırınca çoğaltmaz.

```bash
npm run install:build   # kurulum dosyasını src/'den yeniden üret
npm test                # 63 kontrol + kurulum senkron denetimi
```

---

## Temel tasarım kararı: top Roblox fiziğine bırakılmaz

| Roblox `Part` fiziği sorunu | Sonuç |
|---|---|
| float32 aritmetiği | Uzun maçlarda biriken konum hatası |
| Sunucu/istemci tutarsızlığı | İstemci tahmini / gecikme telafisi imkânsız |
| Hava direnci yok | 30 m'lik pas havada "asılı" kalır |
| Magnus / falso yok | Bükülen şut, orta, korner imkânsız |
| Sekme katsayısı ayarlanamaz | Top ya lastik gibi zıplar ya beton gibi ölür |
| Kare hızına bağımlılık | 30 FPS'teki şut 144 FPS'tekinden farklı yere gider |

Top **240 Hz sabit adımlı kendi simülasyonumuzla** hareket eder;
`Workspace.MatchBall` `Anchored`'dır ve konumu her karede simülasyondan yazılır.
Sunucu otoritedir: istemci topu hareket ettiremez.

---

## Adım 1 — Top fiziği

```
src/shared/
  Config.luau              Tüm parametreler (SI birimleri, gerçek FIFA ölçüleri)
  Core/  Vec3 · Rng · Aero · Ballistics
  Physics/ Ball · Pitch · Colliders · Net · Body
  Player/ Locomotion · BallControl · Keeper
  World/ SceneBuilder
  Sim.luau                 Sabit adımlı döngü, akümülatör, interpolasyon
```

```
a_drag   = -0.5·ρ·A·Cd(v)·|v|·v / m        ρ=1.225, A=πr², m=0.43 kg
a_magnus =  0.5·ρ·A·Cl(S)·|v|²·(ω̂ × v̂) / m  Cl = min(0.32, 0.8·S)
```

`Cd(v)` 12 m/s civarında 0.47'den 0.25'e düşer (**drag crisis**) — Knuckleball'ın
sebebi. Zemine temas **analitik** çözülür (`y(t)=r` kökü), sekmede **Coulomb
sürtünmesi** vardır: topspin topu ileri hızlandırır, backspin yavaşlatır.
Entegrasyon yamuk kuralıdır (sabit ivmede tam çözüm), yani 60 Hz ile 240 Hz aynı
yörüngeyi verir. Aynı tohum + aynı tick → **bit-bit aynı** sonuç.

---

## Adım 2 — Sahne, direkler, istemci

- **Direk/üst direk** fiziksel: topun adım içindeki hareket doğrusu ile direk
  ekseni arasındaki en yakın mesafe (sürekli çarpışma). Direkten dönen top gol
  sayılmaz.
- **İstemci yumuşatma**: sunucu anchored parçayı 20-30 Hz replike eder; 27 m/s'lik
  şut bu hızda 1.3 m sıçrar. İstemci sunucu topunu lokal gizleyip kendi kopyasını
  üstel yaklaşma + hız tahminiyle çizer.
- Sunucu otoritesi + hız sınırlı `SPACE` isteği.

---

## Adım 3 — Oyuncu–top ilişkisi ve file

### Oyuncu → top

Gerçek futbolcu topu sürekli itmez; **saniyede ~3 kez dokunur**, top öne kaçar,
direnç yavaşlatır, oyuncu yetişir. Motor bu ritmi fiziksel olarak çözüyor:

```
Bir sonraki dokunuşa kadar top, oyuncuyla AYNI mesafeyi katetmeli:
    v_top·t − 0.5·a·t² = v_oyuncu·t      (a = yuvarlanma direnci)
=>  v_top = v_oyuncu + 0.5·a·t
```

Tahminle değil çözerek bulunduğu için top ayağından kaçmaz; iyi bir top sürücü
hız kaybetmez. Bileşenler:

| Davranış | Model |
|---|---|
| **Dokunuş** (touch) | 0.34 s aralıkla, çözülen hızla ileri itme; topspin uygulanır |
| **Sprint cezası** | Hızlı koşarken dokunuş aşırıya kaçar → top 2-6 m öne kaçar, kovalamak gerekir |
| **Gövde çarpması** | Top oyuncunun içinden geçmez; çarpışma **bağıl hızla** çözülür (koşan oyuncu topa hız katar) |
| **Kapatma** (trap) | Hızlı gelen top duran oyuncunun ayağında söner (~%70 enerji kaybı) |
| **Şut** | Mesafe kapısı + nişan hatası (σ≈2.2°) + güç→hız eşlemesi (13-31 m/s) + güçle artan topspin |

Gövde çarpışması **240 Hz'de simülasyon içinde** çalışır (adım içi hareket
doğrusuyla), yani 30 m/s'lik şut oyuncunun içinden geçmez.

### Top → file

Gerçek ağ bir yay değil **sönümleyicidir**: enerjiyi yutar, esner, topu geri
fırlatmaz. Model:

- Ağ içinde üstel sönüm `v *= exp(−7·dt)` → top "ölür"
- Arka/yan/üst ağ düzlemlerine çok düşük sekme katsayısıyla (−e = 0.14) çarpma
- Ağın esnemesi **yay-sönümleyici**: çarpma hızı esnemeye dönüşür (`sag`),
  yay onu toparlar. Sunucu arka ağ parçasını `sag` kadar öteleyerek gösterir.
- Top file içinde kalır (yan ağ ve üst ağ onu tutar)

### Kaleci

- Açıyı kapatır (top z'sinin %60'ı), direklerin içinde kalır
- Top kaleye geliyorsa **tahmin** yapar: topun simülasyon kopyasını 120 Hz'de
  çalıştırıp kale çizgisini keseceği z'yi bulur, oraya **dalar**
- Tepki süresi vardır (0.12 s); gövdesi fiziksel engeldir (kurtarış = topun
  gövdeye çarpıp yön değiştirmesi)

---

## Ölçülen davranışlar

`npm test` → **63 kontrol**. Öne çıkanlar:

| Ölçüm | Motor | Gerçek dünya |
|---|---|---|
| Terminal hız | 26.9 m/s | 25–30 m/s |
| 30 m/s'te yavaşlama | 12.7 m/s² | ~12 m/s² |
| 2 m'den sekme yüksekliği | ~1.10 m | 1.0–1.2 m (çim, e≈0.7) |
| Falso sapması (24 m/s, 1 s) | ~3.3 m | 2–4 m (serbest vuruş) |
| 27 m/s şutun 11 m'de hız kaybı | 27 → 22.6 m/s | ~%15 |
| **Top sürme @ 4 m/s** | **3.0 dokunuş/sn, boşluk 0.80–1.33 m** | 0.5–1.5 m |
| **Top sürme @ 5.5 m/s** | 1.3 dokunuş/sn, boşluk ~2.2 m | 1–2 m |
| **Top sürme @ 7.6 m/s (sprint)** | dokunuş kaçar, top 6.6 m'ye kadar açılır | 3–6 m, kovalanır |
| **File: 24 m/s giriş** | **0.25 m/s'de durur, ağ 0.38 m esner** | ağ topu yutar |
| Kaleci | 20 m/s şutu gövdeyle keser | kurtarış |
| 30 m sprint | ~5.2 s | 4.0–5.5 s (amatör) |

Ayrıca: direk/üst direk çarpışması (gol sayılmaz), kare hızı bağımsızlığı, tick
gruplaması değişmezliği, NaN koruması, yorgunluk, ağın toparlanması, topun
ağdan dışarı çıkmaması.

**Kurulum dosyası gerçekten test ediliyor:** testler sahte bir Roblox ortamı
kurup kurulum dosyasını baştan sona çalıştırır; script ağacını ve sahneyi
(yarım saha, 1 kale, 2 direk, üst direk, ağlar, kaleci modeli, top) doğrular.

---

## Görsel doğrulama

```bash
npm run trace     # motor çıktısını preview/trace.json'a yazar
npm run preview   # http://localhost:8080
```

Senaryolar: düz şut (drag), falso (2.89 m bükülme), çip, **direk çarpışması**,
**file (ağda sönümleme + 0.38 m esneme)**, zemin sekmesi. Her nokta 240 Hz
simülasyonun kaydıdır; `preview/` bir oyun değil doğrulama aracıdır.

### Rojo ile (alternatif)

```bash
rojo serve        # Studio'da Rojo eklentisiyle bağlan
rojo build -o FootballSim.rbxlx
```

---

## Yol haritası

- [x] **Adım 1** — Top fiziği: 240 Hz, aerodinamik, sekme/yuvarlanma.
- [x] **Adım 2** — Sahne, direkler, istemci yumuşatma, tek kurulum dosyası.
- [x] **Adım 3** — Oyuncu–top ilişkisi (dokunuş/kapatma/şut), file fiziği, kaleci AI.
      *Kapsam: yarım saha, 1 kaleci, 1 şutçu.*
- [ ] **Adım 4** — Pas ve oyun kurma: pas gücü/hedefi, havadan pas, duvar pası,
      alan boşaltma; top sürerken yön değiştirme.
- [ ] **Adım 5** — Maç kuralları: taç, korner, kale vuruşu, ofsayt, faul, kart, süre.
- [ ] **Adım 6** — 11v11: diziliş, takım AI'sı, baskı, ofansif/defansif geçiş.
- [ ] **Adım 7** — Ağ: istemci tahmini, gecikme telafisi, bant bütçesi.
- [ ] **Adım 8** — Sunum: animasyonlar, kamera modları, UI, ses.

---

## Bilinen sınırlar (dürüst liste)

- **Kaleci sadece çeliyor**, topu yakalamıyor (tutma/oyunu başlatma Adım 5).
- **Pas, çalım, ikili mücadele yok** — Adım 4/6.
- **11v11 yok** (kullanıcı isteğiyle ertelendi): yarım saha, 1 kaleci, 1 şutçu.
- **İstemci yumuşatması tahmin değil**; gerçek prediction Adım 7'de.
- **Balistik çözücü drag'ı saymaz** → ~%15 kısa düşer (şut hedefi bu yüzden
  kompanse edilir).
- **Saha dışına çıkan oyuncu düşebilir** (sadece çim katmanı var).
- **Drag crisis yumuşak geçişle yaklaşımlanır**; gerçek Knuckleball histerezis
  gösterir.
