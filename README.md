# Roblox Futbol Simülasyon Motoru

Roblox için **gerçekçi** bir futbol maç motoru. Adım adım inşa ediliyor;
**Adım 1 (top fiziği)** ve **Adım 2 (Roblox sahnesi + tek kurulum)** tamam.

> Luau · Rojo uyumlu · Fizik: kendi deterministik entegratörümüz (240 Hz)

---

## Tek kurulum: bir kod, tüm oyun

`install/FootballSim_Install.lua` tek dosyadır ve **her şeyi** oyuna aktarır.

1. Roblox Studio'da oyunu aç.
2. `View → Command Bar` (komut çubuğu) aç.
3. `install/FootballSim_Install.lua` dosyasının **tamamını** kopyala, komut çubuğuna
   yapıştır ve Enter'a bas.
4. Play'e bas. `SPACE` ile şut çek.

Kurulum şunları yapar:

| Ne | Nereye |
|---|---|
| 11 ModuleScript (Config, fizik, çekirdek, sahne) | `ReplicatedStorage/Shared/**` |
| `SimLoop` (Script) | `ServerScriptService/Server/` |
| `BallView` (LocalScript) | `StarterPlayer/StarterPlayerScripts/Client/` |
| Çim, çizgiler, 2 kale, direkler, ağ, top, ışık, doğma noktası | `Workspace/FootballPitch` + `Workspace/MatchBall` |

Kurulum **idempotent**: tekrar çalıştırınca çoğaltmaz, günceller.

`install/FootballSim_Install.lua` elle düzenlenmez; `src/` içinden üretilir:

```bash
npm run install:build   # kurulum dosyasını yeniden üret
```

`npm test` bu dosyanın kaynaklarla senkron olup olmadığını denetler (bayatlamayı önler).

---

## Temel tasarım kararı: top Roblox fiziğine bırakılmaz

| Roblox `Part` fiziği sorunu | Sonuç |
|---|---|
| float32 aritmetiği | Uzun maçlarda biriken konum hatası |
| Sunucu/istemci tutarsızlığı | İstemci tahmini, gecikme telafisi yapılamaz |
| Hava direnci yok | 30 m'lik pas havada "asılı" kalır |
| Magnus / falso yok | Bükülen şut, orta, korner imkânsız |
| Sekme katsayısı ayarlanamaz | Top ya lastik gibi zıplar ya beton gibi ölür |
| Kare hızına bağımlılık | 30 FPS'teki şut 144 FPS'tekinden farklı yere gider |

Bu yüzden top **240 Hz sabit adımlı kendi simülasyonumuzla** hareket eder;
`Workspace.MatchBall` parçası `Anchored`'dır ve konumu her karede simülasyondan
yazılır (`src/server/SimLoop.server.luau`). Sunucu otoritedir: istemci topu
hareket ettiremez.

---

## Adım 1 — Top fiziği çekirdeği

```
src/shared/
  Config.luau              Tüm parametreler (SI birimleri, gerçek FIFA ölçüleri)
  Core/
    Vec3.luau              Motor bağımsız vektör matematiği (float64, deterministik)
    Rng.luau               Park–Miller deterministik RNG (replay/anti-cheat)
    Aero.luau              Hava direnci + drag crisis + Magnus (falso)
    Ballistics.luau        Hedefe vuruş açısı çözümü (AI nişanı)
  Physics/
    Ball.luau              Entegrasyon, analitik zemin teması, sekme, yuvarlanma
    Pitch.luau             Saha geometrisi, çizgi/kale tespiti, direk engelleri
    Colliders.luau         Direk/üst direk çarpışması (sürekli çarpışma testi)
  Player/
    Locomotion.luau        İvme, sınırlı dönüş, yorgunluk, durma
  Sim.luau                 Sabit adımlı döngü, akümülatör, interpolasyon
```

**Havada**

```
a_yerçekimi = (0, -9.81, 0)
a_drag      = -0.5·ρ·A·Cd(v)·|v|·v / m        ρ=1.225, A=πr², m=0.43 kg
a_magnus    =  0.5·ρ·A·Cl(S)·|v|²·(ω̂ × v̂) / m  Cl = min(0.32, 0.8·S)
```

`Cd(v)` 12 m/s civarında 0.47'den 0.25'e düşer (**drag crisis**) — Knuckleball'ın
fiziksel sebebi. `S = ω·r/|v|` olduğu için falso yavaş topta daha çok etki eder.

**Zeminde**

- Temas anı **analitik** çözülür: adım içinde `y(t) = r` kökü bulunur, temas anına
  kadar entegre edilir, sekme uygulanır, kalan süre yeniden işlenir. Sekme
  yüksekliği kare hızından bağımsızdır, top zemine gömülmez.
- Sekmede **Coulomb sürtünmesi**: temas noktasındaki kayma, normal impulsla sınırlı
  teğetsel impuls üretir. Topspin topu ileri hızlandırır, backspin yavaşlatır.
- Yuvarlanmada direnç (`a = -μ·g`) ve kaymadan yuvarlanma (`ω = v/r`).

**Sayısal yöntem**: 1/240 s sabit adım, akümülatörlü kare döngüsü, yamuk kuralı
(`p += (v+v')/2·dt` — sabit ivmede tam çözüm). Aynı tohum + aynı tick → **bit-bit
aynı** sonuç.

---

## Adım 2 — Roblox sahnesi, direkler, istemci

```
src/shared/World/SceneBuilder.luau   Saha/kale/ağ/top/ışık/doğma noktası üretir
src/server/SimLoop.server.luau       Sunucu otoritesi: simülasyon + top + demo + şut
src/client/BallView.client.luau      İstemci: yumuşatılmış top, iz, kamera, HUD
```

- **Direk ve üst direk** artık fiziksel: `Colliders` topun adım içindeki hareket
  doğrusu ile direk ekseni arasındaki en yakın mesafeyi bulur (sürekli çarpışma).
  30 m/s'lik şutta adım başına 12.5 cm yol alınır; direk yarıçapı 6 cm olduğu için
  sadece konum kontrolü çarpışmaları kaçırırdı. Direkten dönen top **gol sayılmaz**.
- **Ağ** görsel; top kaleye girince kural gereği durur (Adım 5'te file çarpışması
  ve santra gelecek).
- **İstemci yumuşatma**: sunucu anchored parçayı 20-30 Hz replike eder; 27 m/s'lik
  şut bu hızda 1.3 m sıçrayarak görünür. İstemci, sunucu topunu lokal olarak
  gizleyip kendi kopyasını üstel yaklaşma + hız tahmini ile çizer. (Adım 7'de
  gerçek prediction/lag compensation.)
- **Demo**: top durduğunda 6 s sonra otomatik şut; `SPACE` ile anında şut.
- **Güvenlik**: `SPACE` isteği sunucuda hız sınırına ve "top duruyor mu" kontrolüne
  tabidir; istemci yalnızca istek gönderir, sonucu sunucu belirler.

---

## Doğrulanmış sayılar

`npm test` → **50 kontrol**. Bazıları:

| Ölçüm | Motor | Gerçek dünya |
|---|---|---|
| Terminal hız | 26.9 m/s | 25–30 m/s |
| 30 m/s'te yavaşlama | 12.7 m/s² | ~12 m/s² |
| 2 m'den düşme süresi | 0.64 s | 0.639 s (boşlukta) |
| 2 m'den sekme yüksekliği | ~1.10 m | 1.0–1.2 m (çim, e≈0.7) |
| 5 m/s yuvarlanma mesafesi | ~21 m | 15–25 m (çim) |
| 24 m/s + falso sapması (1 s) | ~3.3 m | 2–4 m (serbest vuruş) |
| 27 m/s şutun 11 m'de hız kaybı | 27 → 22.6 m/s | ~%15 |
| 30 m sprint | ~5.2 s | 4.0–5.5 s (amatör) |
| 0–27 km/h hızlanma | ~1.3 s | 1.2–1.5 s |

Ayrıca doğrulananlar: direk/üst direk çarpışması (gol sayılmıyor, top gömülmüyor),
kare hızı bağımsızlığı, tick gruplaması değişmezliği, NaN koruması, top yarıçapına
duyarlı kale/taç tespiti, yorgunluk.

**Kurulum dosyası gerçekten test ediliyor**: testler sahte bir Roblox ortamı
(`tools/roblox_mock.luau`) kurup tek kurulum dosyasını baştan sona çalıştırır ve
script ağacını, sahneyi (2 kale, 4 direk, 2 üst direk, ağlar, top) doğrular.

---

## Çalıştırma

```bash
npm install              # fengari (Lua VM) — sadece testler için
npm test                 # 50 kontrol + kurulum senkron denetimi
npm run install:build    # install/FootballSim_Install.lua'yı yeniden üret
npm run trace            # motor çıktısını preview/trace.json'a yazar
npm run preview          # http://localhost:8080 görsel doğrulama arayüzü
```

`preview/` bir oyun değil **doğrulama aracıdır**: düz şut, falso, çip, direk
çarpışması ve zemin sekmesi senaryolarını üstten + yandan gösterir; her nokta
240 Hz simülasyonun kaydıdır.

### Roblox'ta Rojo ile (alternatif)

```bash
rojo serve        # Studio'da Rojo eklentisiyle bağlan
# veya
rojo build -o FootballSim.rbxlx
```

---

## Yol haritası

- [x] **Adım 1 — Top fiziği çekirdeği**: deterministik 240 Hz döngü, aerodinamik,
      sekme/yuvarlanma, saha geometrisi, oyuncu hareketi, görsel doğrulama.
- [x] **Adım 2 — Roblox sahnesi**: sahne kurucu, direk/üst direk çarpışması,
      istemci yumuşatma + kamera, sunucu otoritesi, demo şut, tek kurulum dosyası.
- [ ] **Adım 3 — Oyuncular**: 11v11 diziliş, Humanoid yerine kendi hareket modeli,
      top sürme (dribbling) ve yakın kontrol.
- [ ] **Adım 4 — Vuruşlar**: pas/şut gücü, nişan hatası, ilk dokunuş, havadan pas,
      oyuncu girdisinden spin üretimi.
- [ ] **Adım 5 — Maç kuralları**: gol, taç, korner, kale vuruşu, ofsayt, faul, kart,
      süre, santra, file çarpışması.
- [ ] **Adım 6 — AI**: pozisyon alma, baskı, pas seçenekleri, kaleci, takım taktiği.
- [ ] **Adım 7 — Ağ**: istemci tahmini, gecikme telafisi, bant bütçesi, otorite
      doğrulaması.
- [ ] **Adım 8 — Sunum**: animasyonlar, kamera modları, UI, ses.

---

## Bilinen sınırlar (dürüst liste)

- **Top-oyuncu etkileşimi yok**: top oyuncuların içinden geçer (Adım 3).
- **Ağ görsel**: file çarpışması ve topun ağda yavaşlaması yok; kural gereği duruyor.
- **İstemci yumuşatması tahmin değil**: sunucu konumunu yumuşatıyor; gerçek
  prediction/lag compensation Adım 7'de.
- **Balistik çözücü drag'ı saymaz** → ~%15 kısa düşer; AI'de yinelemeli çözücü gerekli.
- **Drag crisis yumuşak geçişle yaklaşımlanır**; gerçek Knuckleball histerezis
  gösterir. Oyun için yeterli.
- **Hakem, AI, ağ, animasyon yok** — sıradaki adımlar.
