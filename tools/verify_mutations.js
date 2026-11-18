#!/usr/bin/env node
/**
 * verify_mutations.js — DOĞRULAYICININ KENDİSİ İÇİN MUTASYON TESTİ
 *
 *   npm run verify:mutate
 *
 * `npm run verify` yeşil dönüyor; ama yeşil bir doğrulayıcı ancak KIRMIZIYA
 * dönebiliyorsa kanıttır. Bu araç koda bilinçli kusurlar enjekte eder ve her
 * kusurun ilgili kapıyı düşürdüğünü (exit code 1) doğrular. Bir kusur yeşil
 * kalırsa doğrulayıcı o konuda KÖR demektir ve bu bir hatadır.
 *
 * Kusurlar gerçek dosyalara yazılır, her turdan sonra BİREBİR geri yüklenir
 * (yedekler .build/mut/ altına). Araç yarıda kesilirse `restoreAll()` yine de
 * çalışır; yine de kesinti sonrası `git status` ile kontrol etmek iyi bir
 * alışkanlıktır.
 *
 * Hız için her vaka yalnızca ilgili kapıyı koşar (VERIFY_ONLY). Tam kanıt:
 *   npm run verify          → 13/13 kapı
 *   npm run verify:mutate   → 33/33 kusur yakalandı
 */
"use strict";

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const ROOT = path.resolve(__dirname, "..");
const BAK = path.join(ROOT, ".build", "mut");

const F = {
  sim: "src/shared/Sim.luau",
  loop: "src/server/SimLoop.server.luau",
  view: "src/client/BallView.client.luau",
  proj: "default.project.json",
  readme: "README.md",
  index: "preview/index.html",
  anim: "preview/anim.html",
  spec: "tools/spec.luau",
  validate: "src/shared/Core/Validate.luau",
  scene: "src/shared/World/SceneBuilder.luau",
};

/** [ad, dosyalar, koşulan kapılar, kaynak → kusurlu kaynak] */
const CASES = [
  ["M1 sözdizimi hatası (local x = =)", [F.sim], "sozdizimi",
    (s) => s.replace("local Sim = {}", "local Sim = {}\nlocal bozuk = = 1")],
  ["M2 Luau'da olmayan sözdizimi (io.write + // + goto)", [F.sim], "dil",
    (s) => s.replace("local Sim = {}",
      "local Sim = {}\nlocal function kusur(a, b) io.write(a) local c = a // b goto done ::done:: return c end")],
  ["M3 Enum yazım hatası (KeyCode.Spacee)", [F.loop], "api",
    (s) => s.replace("local Shared = ReplicatedStorage", "local kusur = Enum.KeyCode.Spacee\nlocal Shared = ReplicatedStorage")],
  ["M4 uydurma Instance.new sınıfı (Sparkle)", [F.loop], "api",
    (s) => s.replace("local Shared = ReplicatedStorage", 'local kusur = Instance.new("Sparkle")\nlocal Shared = ReplicatedStorage')],
  ["M5 uydurma servis (Playerz)", [F.loop], "api",
    (s) => s.replace("local Shared = ReplicatedStorage", 'local kusur = game:GetService("Playerz")\nlocal Shared = ReplicatedStorage')],
  ["M6 özellik yazım hatası (.Perent)", [F.loop], "api",
    (s) => s.replace("local Shared = ReplicatedStorage", "local kusur = workspace.Perent\nlocal Shared = ReplicatedStorage")],
  ["M7 uydurma Roblox metodu (:WaitForChildren)", [F.loop], "api",
    (s) => s.replace("local Shared = ReplicatedStorage", 'local kusur = workspace:WaitForChildren("X")\nlocal Shared = ReplicatedStorage')],
  ["M8 sınır ihlali: sunucuda Players.LocalPlayer", [F.loop], "sinir",
    (s) => s.replace("local Shared = ReplicatedStorage", "local kusur = Players.LocalPlayer\nlocal Shared = ReplicatedStorage")],
  ["M9 sınır ihlali: istemcide FireAllClients", [F.view], "sinir",
    (s) => s.replace("local remotes = ReplicatedStorage", "local kusur = function(r) r:FireAllClients() end\nlocal remotes = ReplicatedStorage")],
  ["M10 kurulum dosyası bayat (src değişti, install:build çalışmadı)", [F.sim], "kurulum",
    (s) => s.replace("local Sim = {}", "local Sim = {}\n-- senkron bozma denemesi")],
  ["M11 rojo: istemci eşlemesi silindi", [F.proj], "rojo",
    (s) => {
      const p = JSON.parse(s);
      const sps = p.tree.StarterPlayer.StarterPlayerScripts;
      delete sps.Client;
      return JSON.stringify(p, null, 2);
    }],
  ["M12 remote: istemci yanlış ad bekliyor (Kickz)", [F.view], "remote",
    (s) => s.replace('remotes:WaitForChild("Kick", 10)', 'remotes:WaitForChild("Kickz", 10)')],
  ["M13 remote: FireServer argüman sayısı düştü", [F.view], "remote",
    (s) => s.replace('kickRemote:FireServer(charge, aim.Z / S, aim.Y / S, shotTypes[shotIndex] or "instep", currentFoot)',
      'kickRemote:FireServer(charge, aim.Z / S, aim.Y / S, shotTypes[shotIndex] or "instep")')],
  ["M14 remote: InputEnded bağlantısı koptu (şut atılmaz)", [F.view], "remote",
    (s) => s.replace("UserInputService.InputEnded:Connect(function(input)", "local inputEndedKoptu = function(input)")],
  ["M15 iz: index.html olmayan alanı okuyor", [F.index], "iz",
    (s) => s.replace("shot.curve", "shot.eğrilikYok")],
  ["M16 belge: README test sayısı bayatladı", [F.readme], "belge",
    (s) => s.replace("**132 kontrol**", "**99 kontrol**")],
  ["M17 önizleme: preview/anim.html silindi", [F.anim], "onizleme",
    () => null], // özel: dosya silinir (aşağıda DELETE olarak ele alınır)
  ["M18 bir spec kontrolü başarısız", [F.spec], "testler",
    (s) => s.replace("local passed, failed = 0, 0", "local passed, failed = 0, 1")],
  ["M19 launch koruması silindi (isFiniteVec3 → velocity)", [F.loop], "remote",
    (s) => s.replace("if isFiniteVec3(velocity) then", "if velocity then")],
  ["M20 modül üyesi yeniden adlandırıldı (Validate.vec3)", [F.validate], "api",
    (s) => s.replace("function Validate.vec3(v)", "function Validate.vec3_RENAMED(v)")],
  ["M21 Validate.vec3 NaN denetimi kaldırıldı", [F.validate], "testler",
    (s) => s.replace('if type(component) ~= "number" or component ~= component or math.abs(component) > Validate.MAX_COMPONENT then',
      'if type(component) ~= "number" then')],
  ["M22 Validate.shotType beyaz listesi kaldırıldı", [F.validate], "testler",
    (s) => s.replace('if type(value) == "string" and set[value] then', 'if type(value) == "string" then')],
  ["M23 var olmayan modül fonksiyonu çağrıldı (Vec3.crossX)", [F.loop], "api",
    (s) => s.replace("local S = Config.STUDS_PER_METER", "local kusur = Vec3.crossX(1, 2)\nlocal S = Config.STUDS_PER_METER")],
  ["M24 fare nişanı kesildi (mouseRay → nil)", [F.view], "testler",
    (s) => s.replace("\tlocal ray = mouseRay(camera)", "\tlocal ray = nil")],
  ["M25 fare konumu yerine sabit ekran noktası", [F.view], "testler",
    (s) => s.replace("return cam:ViewportPointToRay(loc.X, loc.Y)", "return cam:ViewportPointToRay(960, 540)")],
  ["M26 çift kardeş adı geri geldi (PostNorth/PostSouth → Post)", [F.scene], "testler",
    (s) => s.replace('"Post" .. (sz < 0 and "North" or "South")', '"Post"')],

  // ---- "şut çekemiyorum / animasyonlar çalışmıyor" kusur sınıfı ----
  // Bu dördü, kullanıcının yaşadığı gerçek arızaların geri gelmesi hâlinde
  // doğrulayıcının KÖR kalmadığını kanıtlar: doğma noktası menzil dışına
  // taşınırsa, menzil reddi yeniden sessizleşirse, oyuncu yalnızca şut
  // sırasında pozlanırsa ya da kaleci boşta donarsa ilgili kapı düşmeli.
  ["M27 doğma noktası yeniden menzil dışında (topun 11.5 m gerisi)", [F.scene], "testler",
    (s) => s.replace("local spawnX = half and (ballStart.X / S - 1.5) or 0",
      "local spawnX = half and (P.halfLength * 0.18) or 0")],
  ["M28 menzil reddi yeniden sessiz (HUD uyarısı metni silindi)", [F.view], "testler",
    (s) => s.replace('hint.Text = "TOPA YAKLAŞ → "', 'hint.Text = "" .. "--"')],
  ["M29 oyuncu yalnızca şut sırasında pozlanıyor (yürüyüş pozu kapalı)", [F.loop], "testler",
    (s) => s.replace("\tif ANIM.poseHumanoid then\n\t\tplayerAnimClock",
      "\tif false then\n\t\tplayerAnimClock")],
  ["M30 kaleci boşta donuyor (idle → sabit poz)", [F.loop], "testler",
    (s) => s.replace("return KeeperAnim.idle(keeperClock)", "return KeeperAnim.idle(0)")],
  ["M31 istemci tek-yazar kuralını bozuyor (şut sırasında o da poz yazıyor)", [F.view], "testler",
    (s) => s.replace("\t\tif animClock >= serverKickUntil then", "\t\tif true then")],
  ["M32 istemci hızı yalnız girdiden okuyor (koşu animasyonu donuyor)", [F.view], "testler",
    (s) => s.replace("local speed = math.max(moveVel.Magnitude, rootVel.Magnitude) / S -- stud/s -> m/s",
      "local speed = moveVel.Magnitude / S -- stud/s -> m/s")],
  ["M33 duruş kimliğe döndü (atletik bekleyiş silindi → heykel)", ["src/shared/Anim/WalkCycle.luau"], "testler",
    (s) => s.replace("pose.kneeL = Pose.joint(0.24 + 0.04 * breath, 0, 0)", "pose.kneeL = Pose.joint(0.02, 0, 0)")],
];

function read(rel) {
  return fs.readFileSync(path.join(ROOT, rel), "utf8");
}
function write(rel, text) {
  fs.writeFileSync(path.join(ROOT, rel), text);
}
function backupName(rel) {
  return path.join(BAK, rel.replace(/[\\/]/g, "__") + ".bak");
}
function runGates(gates) {
  const r = spawnSync(process.execPath, [path.join(ROOT, "tools", "verify.js")], {
    cwd: ROOT,
    encoding: "utf8",
    env: Object.assign({}, process.env, { VERIFY_ONLY: gates }),
    maxBuffer: 64 * 1024 * 1024,
    timeout: 600000,
  });
  const out = (r.stdout || "") + (r.stderr || "");
  return { code: r.status, out };
}

function main() {
  fs.mkdirSync(BAK, { recursive: true });
  const restore = [];
  const restoreAll = () => {
    while (restore.length) {
      const { rel, text, existed } = restore.pop();
      if (!existed) {
        try { fs.unlinkSync(path.join(ROOT, rel)); } catch {}
      } else {
        write(rel, text);
      }
    }
  };
  process.on("exit", restoreAll);
  process.on("SIGINT", () => { restoreAll(); process.exit(130); });

  console.log("=== DOĞRULAYICI MUTASYON TESTİ (" + CASES.length + " kusur) ===\n");
  const blind = [];
  for (const [name, files, gates, mutate] of CASES) {
    restore.length = 0;
    for (const rel of files) {
      const exists = fs.existsSync(path.join(ROOT, rel));
      restore.push({ rel, text: exists ? read(rel) : null, existed: exists });
    }
    let applied = true;
    try {
      for (const rel of files) {
        const orig = read(rel);
        const mutated = mutate(orig);
        if (mutated === null) {
          fs.unlinkSync(path.join(ROOT, rel)); // M17: dosyayı sil
        } else if (mutated === orig) {
          console.log("  ?  " + name + " → MUTASYON UYGULANAMADI (hedef metin bulunamadı)");
          blind.push(name + " [uygulanamadı]");
          applied = false;
          break;
        } else {
          write(rel, mutated);
        }
      }
      if (!applied) continue;

      const { code, out } = runGates(gates);
      const caught = code !== 0;
      const firstError = out.split("\n").find((l) => l.includes("✗") && !l.includes("KALDI")) || "";
      console.log("  " + (caught ? "✓" : "✗") + "  " + name);
      console.log("      " + (caught ? "yakalandı" : "KÖR — YEŞİL KALDI!") +
        " · exit=" + code + " · kapılar=" + gates + (firstError ? " · " + firstError.trim().slice(2, 110) : ""));
      if (!caught) blind.push(name);
    } finally {
      restoreAll();
    }
  }

  console.log("");
  if (blind.length) {
    console.log("✗ KÖR NOKTA VAR (" + blind.length + "):");
    for (const b of blind) console.log("  - " + b);
    console.log("Doğrulayıcı bu kusurları görmüyor: ilgili kapıya denetim ekleyin.");
    process.exit(1);
  }
  console.log("✓ Doğrulayıcı enjekte edilen " + CASES.length + " kusurun " + CASES.length + " tanesini de yakaladı.");
  console.log("  (yeşil doğrulayıcı kör değildir: her kapı kırmızıya dönebiliyor)");
  process.exit(0);
}

main();
