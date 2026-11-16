#!/usr/bin/env node
/**
 * Tek kurulum dosyası üreteci.
 *
 * src/ altındaki tüm Luau kaynaklarını (shared / server / client) tek bir Lua
 * dosyasına gömer. Bu dosya Roblox Studio'nun Command Bar'ına yapıştırıldığında:
 *
 *   1) ReplicatedStorage.Shared altına tüm ModuleScript'ler yazılır,
 *   2) ServerScriptService.Server.SimLoop (Script) oluşturulur,
 *   3) StarterPlayerScripts.Client.BallView (LocalScript) oluşturulur,
 *   4) Saha/kale/ağ/top/ışık SceneBuilder ile kurulur.
 *
 * Yani "tek kurulum kodu" = bu çıktı. Kaynaklar ile senkron kalması için
 * `npm test` dosyanın güncel olup olmadığını kontrol eder.
 */
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const SRC = path.join(ROOT, "src");
const OUT = path.join(ROOT, "install", "FootballSim_Install.lua");

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith(".luau")) out.push(full);
  }
  return out;
}

/** Dosya adından Roblox sınıfını ve ağaç anahtarını çıkarır. */
function moduleInfo(file) {
  const rel = path.relative(SRC, file).split(path.sep).join("/");
  if (rel.endsWith(".server.luau")) {
    return { key: rel.slice(0, -".server.luau".length), className: "Script", source: fs.readFileSync(file, "utf8") };
  }
  if (rel.endsWith(".client.luau")) {
    return { key: rel.slice(0, -".client.luau".length), className: "LocalScript", source: fs.readFileSync(file, "utf8") };
  }
  return { key: rel.slice(0, -".luau".length), className: "ModuleScript", source: fs.readFileSync(file, "utf8") };
}

function collectModules() {
  return walk(SRC).sort().map(moduleInfo);
}

/** Kaynak içinde geçmeyen bir uzun-köşeli parantez seviyesi seçer. */
function longBracket(text) {
  for (let level = 0; level <= 8; level++) {
    const eq = "=".repeat(level);
    if (!text.includes("]" + eq + "]")) {
      return { open: "[" + eq + "[", close: "]" + eq + "]" };
    }
  }
  return null;
}

function luaEscape(text) {
  return (
    '"' +
    text
      .replace(/\\/g, "\\\\")
      .replace(/"/g, '\\"')
      .replace(/\r/g, "")
      .replace(/\n/g, "\\n") +
    '"'
  );
}

function generateInstaller() {
  const modules = collectModules();
  const bootstrap = fs.readFileSync(path.join(ROOT, "tools", "installer", "bootstrap.lua"), "utf8");

  const lines = [];
  lines.push("--[[");
  lines.push("\tFootballSim — TEK KURULUM DOSYASI (otomatik üretilir, elle düzenlemeyin).");
  lines.push("");
  lines.push("\tKULLANIM");
  lines.push("\t  1) Roblox Studio'da oyunu aç.");
  lines.push("\t  2) View > Command Bar (komut çubuğu) aç.");
  lines.push("\t  3) Bu dosyanın TAMAMINI kopyalayıp komut çubuğuna yapıştır, Enter.");
  lines.push("\t  4) Sahne kurulur, scriptler yerleşir. Play'e bas: SPACE ile şut çek.");
  lines.push("");
  lines.push("\tYeniden üretmek için: npm run install:build");
  lines.push("\tKaynak: src/ (" + modules.length + " modül)");
  lines.push("]]");
  lines.push("");
  lines.push("local SOURCES = {");

  for (const mod of modules) {
    const bracket = longBracket(mod.source);
    lines.push(`\t["${mod.key}"] = { class = "${mod.className}", source = ${bracket ? bracket.open : ""}`);
    if (bracket) {
      lines.push(mod.source.replace(/\s+$/, ""));
      lines.push(bracket.close + " },");
    } else {
      lines.push(luaEscape(mod.source) + " },");
    }
  }

  lines.push("}");
  lines.push("");
  lines.push(bootstrap);

  return { text: lines.join("\n"), modules };
}

function writeInstaller() {
  const { text, modules } = generateInstaller();
  fs.mkdirSync(path.join(ROOT, "install"), { recursive: true });
  fs.writeFileSync(OUT, text);
  return { bytes: Buffer.byteLength(text), modules: modules.length, path: OUT };
}

function readInstaller() {
  try {
    return fs.readFileSync(OUT, "utf8");
  } catch {
    return null;
  }
}

module.exports = { generateInstaller, writeInstaller, readInstaller, collectModules, OUT };

if (require.main === module) {
  const info = writeInstaller();
  console.log("Tek kurulum dosyası yazıldı: install/FootballSim_Install.lua");
  console.log("  " + info.modules + " modül, " + (info.bytes / 1024).toFixed(1) + " KB");
}
