# Roblox Futbol Simülasyon Motoru

Roblox için **gerçekçi** bir futbol motoru, adım adım inşa ediliyor.
**Adım 1** (top fiziği), **Adım 2** (sahne + tek kurulum) ve
**Adım 3** (oyuncu–top ve top–file ilişkisi) tamam.
**Adım 8 (sunum): kodla animasyon** — şut ve kaleci pozları sunucuda hesaplanıyor,
herhangi bir yayınlanmış Asset / Animation instance yok.

> Luau · Rojo uyumlu · Fizik: kendi deterministik entegratörümüz (240 Hz)
> **Şu anki kapsam:** yarım saha, 1 kale, 1 kaleci (AI). Şutu **oynayan oyuncu** atar;
> prosedürel şutçu NPC demo/test için opt-in (`Config.ANIM.strikerEnabled = true`).

---

## Tek kurulum: bir kod, tüm oyun

`install/FootballSim_Install.lua` tek dosyadır ve her şeyi oyuna aktarır.

1. Roblox Studio'da oyunu aç.
2. `View → Command Bar` aç.
3. Dosyanın **tamamını** kopyala, komut çubuğuna yapıştır, Enter.
4. Play'e bas.

| Tuş | Eylem |
|---|---|
| `WASD` | koş |
| `SPACE` | basılı tut → güç barı dolar, **bırak → şut** (nişan fareyle alınır) |
| `T` | vuruş türü (plase / düz ayak / drive / ayak dışı) |
| `F` | ayak değiştir (sol / sağ) |
| `C` | kamera kipi değiştir: **1. şahıs ↔ 3. şahıs** |
| `V` | izleme kipi (topun arkasına geçip kaleyi çerçeveler) |
| `R` | topu sıfırla |

### Kamera kipleri (varsayılan: **1. şahıs**)

| Kip | Tuş | Davranış |
|---|---|---|
| **1. şahıs** (varsayılan) | `C` | Kamerayı **Roblox sürer** (`Humanoid.CameraMode = LockFirstPerson`): baş kilitli, `Head` gizli. İstemci bu kipte kamera `CFrame`'i **yazmaz** — yazsa Roblox ile yarışır ve görüntü titrer. Nişan = karakterin baktığı yön (fare zaten ekranın ortasına kilitli). |
| 3. şahıs | `C` | Omuz üstü ve **yakın** (karakter ~9.4 stud ötede; eskiden 36 stud → animasyonlar ekranda birkaç pikseldi). Kamera `Scriptable`, istemci sürer. |
| İzleme | `V` | Topun arkasına geçip kaleyi çerçeveler; adaptif şut + kaleci dalışını izlemek için. |

HUD satırı hangi kipte olduğunu yazar (`C → kamera: 1. şahıs`).

**Nişan asla yutulmaz.** Sıra: (1) fare ışını (3. şahıs/izleme), (2) kamera bakışı,
(3) karakterin yönü (1. şahıs), (4) **kale ortası**. `computeAim` `nil` dönerse
`fireKick` hiç `FireServer` çağırmaz ve şut sessizce yutulur — bu yüzden son çare
her zaman bir nokta üretir (ör. karakterin sırtı kaleye dönükken bile şut çıkar).

**Şut neden çekilemiyordu?** İki sebep vardı, ikisi de kapalı:

1. Doğma noktası topun **11.5 m gerisindeydi**; sunucunun menzil kapısı
   (`Config.BALL_CONTROL.kickReach`) her `SPACE`'i sessizce reddediyordu. Artık
   `PitchSpawn` topun **1.5 m gerisinde** (menzil **2.00 m**): ilk `SPACE` şut
   üretir. Sınır yine gerçek bir sınırdır — 20 m uzaktaki oyuncunun şut isteği
   reddedilmeye devam ediyor ve bu test ediliyor.
2. Reddedilme **sessizdi**. Artık top menzil dışındayken HUD yazısı turuncuya
   dönüp mesafeyi söylüyor: `TOPA YAKLAŞ → 9.4 m önde · menzil 3.2 m · koşunca
   şut çıkar · WASD ile koş`. Sunucu otoritesi değişmedi; yalnızca nedeni
   görünür oldu.
3. **Top sürerken şut çıkmıyordu**: dokunuş topu oyuncunun önüne iter, boşluk
   5.5 m/s'de ~2.2 m'ye açılır ve katı menzili (2.00 m) geçer. İki çözüm:
   - **Sürüş sahipliği** (`possessionReach = 3.20 m`, `possessionTime = 0.60 s`):
     az önce dokunduğun topa, bir adım önde olsa da vurabilirsin — gerçek
     futbolcu böyle vurur. Dokunulmamış top için kural değişmedi.
   - **Şut tamponu** (`shotBufferReach = 6.00 m`, `shotBufferTime = 0.75 s`):
     `SPACE`'i bıraktığında top menzil dışındaysa istek **çöpe gitmez**; oyuncu
     yetişince şut kendiliğinden çıkar. Pencere kapanırsa nedeni söylenir.
4. Ret / tampon / çıkış **oyuncuya bildiriliyor**: sunucu `MatchState` içinde
   `hint` alanı gönderiyor (`şut bekliyor → topa yetiş…`, `şut çıktı`,
   `şut kaçtı: …`, `şut çıkmadı: top 9.0 m önde — şut menzili 3.2 m`); istemci
   bunu HUD satırında 2.4 s gösteriyor. Top katı menzil içindeyse HUD yeşil
   **`ŞUT HAZIR`** diyor.

Sprint cezası **korundu**: 7.6 m/s'de dokunuş kaçar, top 6.6 m'ye kadar açılır —
o topa anında vurulamaz, kovalamak gerekir (tampon menzili de 6.00 m).

Kurulum: 26 ModuleScript (`ReplicatedStorage/Shared/**`), `SimLoop` (Script,
`ServerScriptService/Server`), `BallView` (LocalScript, `StarterPlayerScripts/Client`),
yarım saha + kale + ağ + kaleci + top + stadyum çevresi (`Workspace/FootballPitch`,
`Workspace.MatchBall`). İdempotenttir; tekrar çalıştırınca çoğaltmaz.

```bash
npm run install:build   # kurulum dosyasını src/'den yeniden üret
npm test                # 145 kontrol + kurulum senkron denetimi
```

---

## Tek komutla tam doğrulama

```bash
npm run verify
```

Roblox entegrasyonunun **tamamını** baştan sona denetler; 13 kapıdan biri bile
kırmızıysa çıkış kodu `1` döner. Her kapı kendi alanında kanıt üretir:

| # | Kapı | Ne kanıtlar |
|---|---|---|
| 1 | Ortam | Node ≥ 18, Lua VM (`fengari`) çalışıyor, npm script'leri tanımlı |
| 2 | Sözdizimi | Roblox'a giden **30 kaynak** (28 modül + bootstrap + kurulum dosyası) ve JSON'lar derleniyor |
| 3 | Dil uyumu | Luau'da **çalışmayacak** sözdizimi/API yok (`goto`, `//`, bit operatörleri, `+=`, `io/os/debug/package`, `continue`, Luau tip notasyonu) — yorum ve string gövdeleri elenerek taranır |
| 4 | Roblox API | Her `GetService`, `Instance.new`, `Enum.X.Y`, `Vector3.new`, `:Metot()` ve `.Özellik` gerçek Roblox API'sinde var (yazım hatası burada patlar) |
| 5 | Sınır | Sunucu dosyasında istemci-özel API yok, istemcide sunucu-özel API yok; kullanılmayan servis importu (ölü entegrasyon) yok |
| 6 | Kurulum | `install/FootballSim_Install.lua` kaynaklarla **bit-bit senkron**: 26 ModuleScript + 1 Script + 1 LocalScript, sınıf ve kaynak birebir |
| 7 | Rojo | `default.project.json` `src/`'nin **tamamını** eşliyor; eşlenmemiş tek dosya yok |
| 8 | Remote + otorite | `Kick` / `ResetBall` / `MatchState` iki tarafta da var; `FireServer` argüman sayısı = `OnServerEvent` parametre sayısı; `MatchState` alanları istemcinin okuduklarını kapsıyor; `InputEnded → fireKick` zinciri kopuk değil; **her `Ballistics.solveLaunch` çıktısı `isFiniteVec3` denetiminden geçiyor** (silinirse kapı düşer) |
| 9 | Testler | `tools/spec.luau` → **145 kontrol**, 15 grup, 0 başarısız (test sayısı geri giderse ya da bir grup hiç koşmazsa kapı düşer) |
| 10 | Fizik izi | `preview/trace.json` üretiliyor; 6 senaryo, 635 yol noktası sonlu; falso > 2 m, direk gol değil, ağ esner ve topu yutar; `index.html`'in okuduğu her alan JSON'da var |
| 11 | Anim izi | `preview/anim.json` üretiliyor; 16 sahne / 481 kare, her kare eklem sayısıyla uyumlu ve sonlu; `dive/jump/block/jumpDive` kaleci hareketleri mevcut |
| 12 | Önizleme | `tools/serve.js` gerçekten ayakta: `/`, `/anim.html`, `/trace.json`, `/anim.json` → 200 + doğru `content-type`, olmayan dosya 404, dizin dışı erişim engelli |
| 13 | Belge | README'deki test/modül/senaryo sayıları, komutlar ve tuş belgeleri gerçekle uyumlu |

Kapı 4–5 statik taramadır, kapı 9 canlı testtir: ikisi birlikte "kod Roblox'ta
çalışır" iddiasını hem sözdizimi hem davranış düzeyinde kapatır.

### Doğrulayıcının kendisi de test ediliyor

Yeşil bir doğrulayıcı, ancak kırmızıya dönebiliyorsa kanıttır:

```bash
npm run verify:mutate                          # 48 kusurun tamamı (~28 dk)
MUTATE_ONLY=M41,M44 npm run verify:mutate      # yalnızca seçili kusurlar (kısmi koşu)
```

`tools/verify_mutations.js` koda **48 bilinçli kusur** enjekte eder (sözdizimi
hatası, `Enum.KeyCode.Spacee`, uydurma servis/sınıf, `.Perent`, sunucuda
`Players.LocalPlayer`, silinmiş rojo eşlemesi, yanlış remote adı, eksik
`FireServer` argümanı, kopmuş `InputEnded`, silinmiş `isFiniteVec3` koruması,
var olmayan modül fonksiyonu, kesilmiş fare nişanı, geri gelmiş çift kardeş adı,
bayat README sayısı, açılmamış 1. şahıs kilidi, 1. şahısta kamerayı ezen istemci,
yeniden çok uzağa alınmış 3. şahıs kamerası, kapatılmamış varsayılan `Animate`,
silinmiş R6 desteği, nişanı `nil` kalan şut…) ve her birinin ilgili kapıyı düşürdüğünü doğrular; biri
yeşil kalırsa araç `✗ KÖR NOKTA` yazıp 1 döner. Her turdan sonra dosyalar
birebir geri yüklenir.

Kapsamlı bir kapı yalnızca bir alt kümede çalışmak istiyorsanız:
`VERIFY_ONLY=api,remote npm run verify` (atlanan kapılar raporda `ATLANDI`
görünür ve sonuç satırı bunun tam doğrulama olmadığını açıkça söyler).

### Nişan nasıl alınıyor

Kamera `Scriptable` ve sabit bir ofsette durduğu için kameranın `LookVector`'ü
oyuncunun baktığı yer **değildir**. Bu yüzden `computeAim()` sırayla:

1. `UserInputService:GetMouseLocation()` → `camera:ViewportPointToRay(x, y)` ile
   fare ekran noktasından dünya ışını kurar,
2. ışını kale düzlemine (`X = halfLength`) izdüşürür; `z ∈ ±3.3 m`, `y ∈ 0.25..2.3 m`
   arasına kıstırır,
3. ışın düzlemi **önden kesmiyorsa** (gökyüzüne/arkaya nişan) kamera bakışına düşer
   — yani şut hiçbir zaman sessizce yutulmaz.

14. test grubu bu bağlantıyı kilitler: fare ekranı sağa/sola/yukarı/aşağı
kaydırıldığında `workspace.AimMarker`'ın kale düzlemindeki yeri de değişmelidir.

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

### Görsel sunum (prosedürel, asset yok)

Saha "boş yeşil dikdörtgen" gibi görünmesin diye çevresi de kurulur:

- **Çim:** uzaktan seçilen kontrastlı biçim şeritleri + ceza yayı ("D").
- **Stadyum:** sahayı saran apron + beton concourse, üç tribün (kuzey/güney/kale
  arkası; kademeli koltuklar, arka duvar, çatı bandı), saha çevresinde renkli
  reklam panoları, 4 köşe flaması, 4 ışık kulesi.
- **Işık:** altın saat (`ClockTime 16.8`), `Sky` (gri stüdyo ufku yerine bulutlu
  mavi), `Atmosphere` + hafif `SunRays`/`Bloom`/`ColorCorrection`.
- **Oyuncular:** kaleci turuncu formayla ilk bakışta seçilir; oyuncu sahaya
  kaleye dönük doğar.

Bunların hiçbiri "elle düzeltilen" sahne değildir: `SceneBuilder` her kurulumda
aynı ağacı üretir ve 8. grup testleri tribün/pano/flama/ışık/gökyüzü varlığını
kilitler (bir parça sessizce kaybolursa test düşer).

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

`npm test` → **145 kontrol**. Öne çıkanlar:

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
| **Sürüş hâlinde şut** | 2.0–3.2 m boşlukta şut çıkar (sürüş sahipliği) | bir adım öndeki topa vurulur |
| **Şut tamponu** | menzil dışı istek 0.75 s bekler, yetişince çıkar | input buffering |
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

## Animasyon — kodla, adaptif, yayınlanmasın

Önemli karar: **yayınlanmış bir Asset yok, `Animation` instance yok, hareketlere "animasyon" diye isim verilmedi.** Pozlar sunucuda kodla hesaplanır ve `PartRig` (13 parçalı R15 eşlemesi) ile doğru şekilde parçalara uygulanır (ileri kinematik, FK).

| Dosya | Sorumluluk |
|---|---|
| `src/shared/Anim/Rig.luau` | FK: 18 eklem → 13 parçalı dünya konumu |
| `src/shared/Anim/KickAnim.luau` | Şut pozları: top yüksekliği/yanı/gücüne göre ayak seçimi, kalça bükülmesi, gövde egimi |
| `src/shared/Anim/KeeperAnim.luau` | Kaleci: blok / dalış / zıplama / zıplamalı dalış seçimi; el uzanma; boşta **nefes + ağırlık salınımı** (`KeeperAnim.idle`) |
| `src/shared/Anim/WalkCycle.luau` | Koşu döngüsü: adım fazı mesafeye bağlı (ayak kaymaz), dururken atletik bekleyiş |
| `src/shared/Anim/PlayerPose.luau` | **Oynayan oyuncunun** yürüyüş/duruş pozu: zamanı adım fazına çevirir, `HumanoidPose` ile R15 eklemlerine yazar |
| `src/shared/Anim/PartRig.luau` | Pozu Roblox parçalarına uygulama (FK) |
| `src/shared/Anim/Ease.luau` · `Pose.luau` · `HumanoidPose.luau` | Eğri/poz yardımcıları |

Özellikler:

- **Adaptif şut**: `ballHeight` → yerden / yarım vole / vole / sol ayak; `charge` → şut gücü ve kalça bükülmesi; temas anında top ayrılır (`KickAnim.CONTACT_TIME = 0.24 s`, `DURATION = 0.62 s`).
- **Adaptif kaleci**: topun kaleye varış noktası (`dz`) ve yüksekliği hareketi seçer — blok (`dz < 0.5`) / dalış (`dz ≥ 0.5`) / zıplama (`height ≥ 1.45`); yüksek+yan şutta `jumpDive`. El uzanma `0.38–2.30 m`.
- **Varsayılan Roblox animasyonu pozu EZMİYOR**: karakterdeki `Animate`
  LocalScript'i her karede `Motor6D.Transform`'a kendi pozunu yazar; bu yüzden
  Studio'da "animasyonlar çalışmıyor" görünüyordu. Pozlama gerçekten
  çalışıyorsa (`HumanoidPose.supported`) `Animate` **kapatılır**; çalışmıyorsa
  (eklem bulunamadı) **açık bırakılır** ki karakter heykele dönmesin.
  Script'i kapatmak tek başına yeterli değildir: zaten oynayan varsayılan
  `AnimationTrack`'ler `Animator` içinde yaşamaya devam eder ve `Transform`'u
  her karede yeniden yazar — istemci bunları da `Stop(0)` ile durdurur.
  `Animate` veya `Motor6D`'ler `CharacterAdded`'dan **sonra** gelirse periyodik
  kontrol / `ChildAdded` ile yakalanır; daha önceki "tek seferlik kontrol"
  yüzünden prosedürel poz hiç açılmıyordu.
  `Config.ANIM.poseHumanoid = false` tüm prosedürel pozu kapatır (kaçış kapağı).
- **R15 + R6**: R15'te 12 eklem (bel/diz/dirsek dahil), R6'da 5 eklem
  (`Neck`, `Left/Right Shoulder`, `Left/Right Hip`) sürülür. Eski kod R6
  avatarlarda sessizce hiçbir şey yapmıyordu.
- **Oynayan oyuncu sürekli animasyonlu**: karakter yalnızca şut sırasında değil,
  **her karede** pozlanır — koşarken adım döngüsü, dururken nefes alan bekleyiş.
  Poz hem sunucuda (`SimLoop` adım 3b, `Config.ANIM.poseHumanoid`) hem istemcide
  (`BallView`, kendi karakteri = gecikmesiz) yazılır; şut anında `KickAnim`
  istemcide **hemen** başlar, sunucu onayı beklenmez.
  **Zamanlama kritik**: Roblox `Animator`'ı `Motor6D.Transform`'u her karede
  `PreAnimation` sonrası / `PreSimulation` öncesinde ezer. Bu yüzden istemci
  pozları `RenderStepped` değil **`Stepped`** içinde yazar (animatordan sonra);
  kamera, HUD ve top yumuşatma `RenderStepped`'de kalır. `RenderStepped`'e geri
  alınırsa animasyon görünmez — 47. mutasyon tam bunu denetler.
- **Kaleci boşta heykel değil**: dalış yokken `KeeperAnim.idle(t)` nefes ve
  ağırlık salınımı üretir.
- **Deterministik**: aynı giriş → aynı poz; `t = 0` başlangıç, `t = DURATION` bitiş.

Tarayıcı izleyici (sadece geliştirme, oyun dışı):

```bash
npm run anim   # tools/anim_trace.luau → preview/anim.json (FK, 40 Hz, 16 senaryo)
npm run preview # http://localhost:8080/anim.html
```

`preview/anim.html` canvas ile yandan/önden görünüm, oynat/duraklat, zaman çubuğu, temas anı işareti, kemik çizimi ve top işareti sunar. Kaynak: `tools/anim_trace.luau` (11 şut + 5 kaleci sahnesi = 16, `contact` ve `bayrak` alanları ile).

Test: `tools/spec.luau` → **145/145** (8. grup kaleci + kurulum + sahne ağacı + stadyum çevresi, 9. grup anim, 10. grup canlı döngü + şutçu, 11. grup istemci/E2E, 12. grup girdi sertleştirme, 13. grup `Validate` birim testleri, 14. grup fare → nişan).

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
      *Animasyon alt-adımı (şut + kaleci + oyuncu yürüyüşü/duruşu): kodla, FK, testli (145/145). Kamera modu (V izleme) ve HUD (ipucu/güç barı/skor) tamam; ses bekliyor.*

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
- **Animasyon şut + kaleci + yürüyüş/duruş** ile sınırlı (tek bir şutçu, tek bir
  kaleci); top sürme/çalım/ikili mücadele animasyonu ve geçiş akışı yok.
- **1. şahısta kendi gövdeni göremezsin** (Roblox `Head`'i gizler): aşağı
  bakınca bacaklar görünür, kendi animasyonunu izlemek için `C` ile 3. şahsa geç.
- **R6'da poz kaba** (diz/dirsek/bel yok): omuz + kalça + boyun sürülür.
- Prosedürel poz açıkken karakterin varsayılan `Animate` script'i kapalıdır
  (yoksa pozu ezer); `Config.ANIM.poseHumanoid = false` ile tümüyle kapanır.
  Kamera kipleri (1./3. şahıs, izleme) ve UI istemci tarafındadır.
