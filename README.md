# Roblox Futbol Simülasyon Motoru

Roblox için **gerçekçi** bir futbol maç motoru. Adım adım inşa ediliyor; bu depo
şu an **Adım 1 (top fiziği çekirdeği)** tamamlanmış durumda.

> Dil: **Luau** (Roblox) · Yapı: **Rojo** uyumlu · Fizik: **kendi deterministik
> entegratörümüz**, Roblox fizik motoru değil.

---

## Temel tasarım kararı: top Roblox fiziğine bırakılmaz

Roblox'un `Part` fiziği bir futbol topu için yetersiz:

| Sorun | Sonuç |
|---|---|
| float32 aritmetiği | Uzun maçlarda biriken konum hatası |
| Sunucu/istemci tutarsızlığı | İstemci tahmini (prediction) ve gecikme telafisi yapılamaz |
| Hava direnci yok | Şut "sonsuza kadar" aynı hızda gider; 30 m'lik pas havada asılı kalır |
| Magnus / falso yok | Bükülen şut, orta, köşe vuruşu imkânsız |
| Sekme katsayısı ayarlanamaz | Top ya lastik gibi zıplar ya beton gibi ölür |
| Kare hızına bağımlılık | 30 FPS'te oynayanın şutu 144 FPS'tekinden farklı yere gider |

Bu yüzden top, **240 Hz sabit adımlı kendi simülasyonumuzla** hareket eder;
Roblox tarafında top parçası `Anchored`'dır ve konumu her karede simülasyondan
yazılır (`src/server/SimLoop.server.luau`).

Aynı yaklaşım adım 3'te oyuncular için de kullanılacak (Humanoid yerine kendi
hareket modeli).

---

## Adım 1'de ne var?

```
src/shared/
  Config.luau              Tüm parametreler (SI birimleri, gerçek FIFA ölçüleri)
  Core/
    Vec3.luau              Motor bağımsız vektör matematiği (float64, deterministik)
    Rng.luau               Park–Miller deterministik RNG (replay/anti-cheat için)
    Aero.luau              Hava direnci + drag crisis + Magnus (falso)
    Ballistics.luau        Hedefe vuruş açısı çözümü (AI nişanı için)
  Physics/
    Ball.luau              Top fiziği: entegrasyon, analitik zemin teması, sekme,
                           Coulomb sürtünmesi, yuvarlanma, spin sönümü
    Pitch.luau             Saha geometrisi, çizgi/kale tespiti (top yarıçapı dahil)
  Player/
    Locomotion.luau        Oyuncu hareketi: ivme, dönüş hızı, yorgunluk, durma
  Sim.luau                 Sabit adımlı döngü, akümülatör, interpolasyon
src/server/
  SimLoop.server.luau      Roblox giriş noktası (Heartbeat -> sim:update)
tools/                     Test koşucusu + fizik izi üreteci (Roblox'a dahil değil)
preview/                   Motorun çıktısını gösteren doğrulama arayüzü
```

### Fizik modeli, kısaca

**Havada**

```
a_yerçekimi = (0, -9.81, 0)
a_drag      = -0.5·ρ·A·Cd(v)·|v|·v / m      ρ=1.225, A=πr², m=0.43 kg
a_magnus    =  0.5·ρ·A·Cl(S)·|v|²·(ω̂ × v̂) / m
```

- `Cd(v)` hıza bağlıdır: 12 m/s civarında 0.47'den 0.25'e düşer (**drag crisis**).
  Knuckleball'un düzensiz uçuşunun ve yavaş topların neden bu kadar "ağır"
  hissettirdiğinin fiziksel sebebi budur.
- `Cl(S) = min(0.32, 0.8·S)`, `S = ω·r/|v|` → falso yavaş topta daha çok etki eder.

**Zeminde**

- Temas anı **analitik** çözülür: adım içinde `y(t) = r` denkleminin kökü bulunur,
  temas anına kadar entegre edilir, sekme uygulanır, kalan süre yeniden işlenir.
  Böylece sekme yüksekliği kare hızından bağımsızdır ve top zemine gömülmez.
- Sekmede **Coulomb sürtünmesi**: temas noktasındaki kayma hızı, normal impulsla
  sınırlı teğetsel impuls üretir; spin de buna göre güncellenir. Topspin topu ileri
  hızlandırır, backspin yavaşlatır — gerçek davranış.
- Yuvarlanmada yuvarlanma direnci (`a = -μ·g`) ve kaymadan yuvarlanma koşulu
  (`ω = v/r`) uygulanır.

**Sayısal yöntem**

- Sabit adım 1/240 s, akümülatörlü kare döngüsü (kare hızından bağımsız).
- Konum güncellemesi yamuk kuralı (`p += (v+v')/2·dt`) — sabit ivmede **tam**
  çözüm; 60 Hz ile 240 Hz aynı yörüngeyi verir.
- Determinizm: aynı tohum + aynı tick dizisi → **bit-bit aynı** sonuç.

---

## Doğrulanmış sayılar

`npm test` ile 40 kontrol çalışır. Bazı ölçülen değerler:

| Ölçüm | Motor | Gerçek dünya |
|---|---|---|
| Terminal hız | 26.9 m/s | 25–30 m/s |
| 30 m/s'te yavaşlama | 12.7 m/s² | ~12 m/s² |
| 2 m'den düşme süresi | 0.64 s | 0.639 s (boşlukta) |
| 2 m'den sekme yüksekliği | ~1.10 m | 1.0–1.2 m (çim, e≈0.7) |
| 5 m/s yuvarlanma mesafesi | ~21 m | 15–25 m (çim) |
| 24 m/s + falso sapması (1 s) | ~3.3 m | 2–4 m (serbest vuruş) |
| 27 m/s şutun 11 m'de hız kaybı | 27 → 22.6 m/s | ~%15 |
| 30 m sprint | 5.0–5.5 s | 4.0–5.5 s (amatör) |
| 0–27 km/h hızlanma | ~1.3 s | 1.2–1.5 s |

Ayrıca doğrulanan davranışlar: kare hızı bağımsızlığı, tick gruplaması
değişmezliği, NaN koruması, top yarıçapına duyarlı kale/taç tespiti, yorgunluk.

---

## Çalıştırma

```bash
npm install          # fengari (Lua VM) — sadece testler için
npm test             # 40 fizik/motor kontrolü
npm run trace        # motorun gerçek çıktısını preview/trace.json'a yazar
npm run preview      # http://localhost:8080 -> görsel doğrulama arayüzü
```

`preview/` bir oyun değil, **doğrulama aracıdır**: çizilen her nokta 240 Hz
simülasyonun kaydıdır. Düz şut, falso, çip ve zemin sekmesi senaryolarını
üstten + yandan gösterir.

### Roblox'ta kullanım

```bash
# Rojo kurulu olmalı (https://rojo.space)
rojo serve            # Studio'da Rojo eklentisiyle bağlan
# veya
rojo build -o FootballSim.rbxlx
```

`default.project.json` şunları eşler:

- `ReplicatedStorage/Shared` ← `src/shared`
- `ServerScriptService/Server` ← `src/server`

Server açıldığında `SimLoop` çalışır, `Workspace.MatchBall` parçasını simülasyon
sürer.

---

## Yol haritası

- [x] **Adım 1 — Top fiziği çekirdeği**: deterministik 240 Hz döngü, aerodinamik,
      sekme/yuvarlanma, saha geometrisi, oyuncu hareketi, 40 test, görsel doğrulama.
- [ ] **Adım 2 — Roblox sahnesi**: saha, kale direkleri (çarpışma), top görseli,
      kamera, istemci interpolasyonu, sunucu→istemci top senkronu.
- [ ] **Adım 3 — Oyuncular**: 11v11 diziliş, Humanoid yerine kendi hareket modeli,
      animasyon katmanı, top sürme (dribbling) ve yakın kontrol.
- [ ] **Adım 4 — Vuruşlar**: pas/şut gücü, nişan hatası, ilk dokunuş, havadan pas,
      falso uygulama (oyuncu girdisinden spin üretimi).
- [ ] **Adım 5 — Maç kuralları**: gol, taç, korner, kale vuruşu, ofsayt, faul,
      kart, süre, santra.
- [ ] **Adım 6 — AI**: pozisyon alma, baskı, pas seçenekleri, kaleci (konum + refleks),
      takım taktiği (yüksek hat, pres, kanat oyunu).
- [ ] **Adım 7 — Ağ**: sunucu otoritesi, istemci tahmini, gecikme telafisi,
      bant genişliği bütçesi (yalnızca top + oyuncu durumu).
- [ ] **Adım 8 — Sunum**: animasyonlar, kamera modları (yayın/oyuncu), UI, ses.

---

## Bilinen sınırlar (dürüst liste)

- **Direkler ve ağ modellenmedi**: şu an top direğe çarpıp sekmez, kaleyi geçen
  top "gol" sayılır. Adım 2'de silindir çarpışması eklenecek.
- **Oyuncu-top etkileşimi yok**: top oyuncudan geçer (Adım 3).
- **Drag crisis yumuşak geçişle yaklaşımlanır**; gerçek Knuckleball'da türbülans
  geçişi histerezis gösterir. Oyun için yeterli, simülasyon doğruluğu için değil.
- **Balistik çözücü drag'ı hesaba katmaz** → ~%15 kısa düşer. AI'ye geçmeden önce
  yinelemeli (shooting method) bir çözücü eklenecek.
- **Hakem/AI/ağ yok** — sıradaki adımlar.
