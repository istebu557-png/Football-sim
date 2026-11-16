#!/usr/bin/env node
/**
 * Test koşucusu.
 *
 * src/ altındaki tüm .luau dosyalarını okuyup tek bir Lua paketi üretir,
 * Roblox'un script/require semantiğini taklit eden shim ile birleştirir ve
 * fengari (Lua 5.3 VM) üzerinde çalıştırır.
 *
 *   node tools/runner.js           -> testler
 *   node tools/runner.js --trace   -> fizik izlerini JSON olarak üretir
 */
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const installerLib = require("./installer_lib");

const ROOT = path.resolve(__dirname, "..");
const SRC = path.join(ROOT, "src");
const BUILD = path.join(ROOT, ".build");

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith(".luau")) out.push(full);
  }
  return out;
}

// "src/shared/Physics/Ball.luau" -> "shared/Physics/Ball"
// "src/server/SimLoop.server.luau" -> "server/SimLoop"
function moduleKey(file) {
  return path
    .relative(SRC, file)
    .replace(/\.(server|client)\.luau$/, "")
    .replace(/\.luau$/, "")
    .split(path.sep)
    .join("/");
}

function luaString(s) {
  return (
    '"' +
    s
      .replace(/\\/g, "\\\\")
      .replace(/"/g, '\\"')
      .replace(/\r/g, "")
      .replace(/\n/g, "\\n")
      .replace(/\t/g, "\\t") +
    '"'
  );
}

const files = walk(SRC).sort();

// Tek kurulum dosyası kaynaklarla senkron mu?
const freshInstaller = installerLib.generateInstaller().text;
const onDiskInstaller = installerLib.readInstaller();
let installerError = null;
if (onDiskInstaller === null) {
  installerError = "install/FootballSim_Install.lua yok. Çalıştır: npm run install:build";
} else if (onDiskInstaller !== freshInstaller) {
  installerError = "install/FootballSim_Install.lua kaynaklarla senkron değil. Çalıştır: npm run install:build";
}

const parts = [];
parts.push("-- OTOMATIK URETILDI: tools/runner.js");
parts.push("local SOURCES = {");
for (const file of files) {
  const key = moduleKey(file);
  parts.push(`  [${luaString(key)}] = ${luaString(fs.readFileSync(file, "utf8"))},`);
}
parts.push("};");
parts.push(fs.readFileSync(path.join(ROOT, "tools", "shim.luau"), "utf8"));
parts.push("local INSTALLER_SRC = " + luaString(freshInstaller));
parts.push(
  "local RobloxMock = (function()\n" +
    fs.readFileSync(path.join(ROOT, "tools", "roblox_mock.luau"), "utf8") +
    "\nend)()"
);

const traceMode = process.argv.includes("--trace");
const entry = traceMode ? "trace.luau" : "spec.luau";
parts.push(fs.readFileSync(path.join(ROOT, "tools", entry), "utf8"));

fs.mkdirSync(BUILD, { recursive: true });
const bundlePath = path.join(BUILD, traceMode ? "trace.lua" : "tests.lua");
fs.writeFileSync(bundlePath, parts.join("\n"));

const bin = path.join(ROOT, "node_modules", ".bin", "fengari");
const result = spawnSync(bin, [bundlePath], {
  cwd: ROOT,
  encoding: "utf8",
  maxBuffer: 64 * 1024 * 1024,
});

if (traceMode) {
  if (result.status !== 0) {
    if (result.stderr) process.stderr.write(result.stderr);
    process.exit(1);
  }
  const outDir = path.join(ROOT, "preview");
  fs.mkdirSync(outDir, { recursive: true });
  // JSON'un başında/sonunda Lua çıktısı kalmasın
  const json = (result.stdout || "").trim();
  fs.writeFileSync(path.join(outDir, "trace.json"), json);
  let parsed = null;
  try { parsed = JSON.parse(json); } catch (e) { console.error("Gecersiz JSON:", e.message); process.exit(1); }
  console.log("Iz yazildi: preview/trace.json (" + (json.length / 1024).toFixed(1) + " KB)");
  for (const shot of parsed.shots) {
    console.log(
      "  " + shot.label.padEnd(22) +
      " yol=" + shot.path.length + " nokta" +
      "  tepe=" + shot.maxHeight.toFixed(2) + "m" +
      "  falso=" + shot.curve.toFixed(2) + "m" +
      "  hiz " + shot.speedStart.toFixed(1) + "->" + shot.speedEnd.toFixed(1) +
      (shot.goal ? "  GOL" : "")
    );
  }
  process.exit(0);
}

if (result.stdout) process.stdout.write(result.stdout);
if (result.stderr) process.stderr.write(result.stderr);

const failed = result.status !== 0 || /\n\s*\[FAIL\]/.test(result.stdout || "");

if (installerError) {
  console.error("\n[KURULUM DOSYASI] " + installerError);
}

process.exit(failed || installerError ? 1 : 0);
