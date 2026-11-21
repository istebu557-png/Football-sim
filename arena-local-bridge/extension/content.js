(function () {
  "use strict";

  const Parser = window.ArenaBridgeParser;
  if (!Parser) return;

  let settings = { enabled: true, autoInsertResult: false };
  let hostStatus = { connected: false, workspace_root: "", full_system_access: false, error: null };
  let scanTimer = null;
  let cardCounter = 0;

  // Map from source code element -> { hash, cardId, cardEl, locked }
  const trackedNodes = new WeakMap();
  // Keep ordered list of active card records
  const activeRecords = new Map();

  let dockEl = null;
  let trayListEl = null;
  let trayCountEl = null;

  function simpleHash(str) {
    let h = 2166136261;
    for (let i = 0; i < str.length; i++) {
      h ^= str.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return String(h >>> 0);
  }

  function hasChromeRuntime() {
    try {
      return typeof chrome !== "undefined" && Boolean(chrome && chrome.runtime && chrome.runtime.sendMessage);
    } catch (_e) {
      return false;
    }
  }

  function sendMessage(msg) {
    return new Promise((resolve) => {
      if (!hasChromeRuntime()) {
        resolve({
          ok: false,
          error: "Eklenti baglanti baglami gecersiz (eklenti guncellenmis olabilir). Lutfen sayfayi yenileyin (F5).",
        });
        return;
      }
      try {
        chrome.runtime.sendMessage(msg, (res) => {
          try {
            if (chrome.runtime && chrome.runtime.lastError) {
              resolve({ ok: false, error: chrome.runtime.lastError.message || "Chrome runtime hatasi" });
              return;
            }
          } catch (_e) {
            resolve({ ok: false, error: "Sayfayi yenileyin (F5)." });
            return;
          }
          resolve(res || { ok: false, error: "Yanit alinamadi" });
        });
      } catch (err) {
        resolve({ ok: false, error: err && err.message ? err.message : String(err) });
      }
    });
  }

  function detectLanguageHint(codeEl) {
    if (!codeEl || typeof codeEl.getAttribute !== "function") return "";
    const parentClass = codeEl.parentElement && typeof codeEl.parentElement.className === "string"
      ? codeEl.parentElement.className
      : "";
    const ownClass = typeof codeEl.className === "string" ? codeEl.className : "";
    const classes = `${ownClass} ${parentClass}`;
    const langMatch = classes.match(/language-([a-zA-Z0-9_-]+)/);
    if (langMatch) return langMatch[1];

    const dataLang =
      codeEl.getAttribute("data-language") ||
      (codeEl.parentElement && codeEl.parentElement.getAttribute && codeEl.parentElement.getAttribute("data-language"));
    if (dataLang) return dataLang;

    const pre = codeEl.closest ? codeEl.closest("pre") : null;
    if (pre && pre.previousElementSibling && pre.previousElementSibling.textContent) {
      const label = pre.previousElementSibling.textContent.trim().toLowerCase();
      if (label.includes("arena-tool")) return "arena-tool";
      if (label.includes("tool_call")) return "tool_call";
    }
    return "";
  }

  function findChatInput() {
    const selectors = [
      'textarea[placeholder*="Ask"]',
      'textarea[placeholder*="Message"]',
      'textarea[placeholder*="Prompt"]',
      'textarea[placeholder*="Sor"]',
      "form textarea",
      "textarea",
      '[contenteditable="true"][role="textbox"]',
      '[contenteditable="true"]',
    ];
    for (const sel of selectors) {
      const candidates = Array.from(document.querySelectorAll(sel)).filter((el) => {
        if (!el || typeof el.getBoundingClientRect !== "function") return false;
        const rect = el.getBoundingClientRect();
        return rect.width > 80 && rect.height > 20 && !el.disabled;
      });
      if (candidates.length > 0) {
        candidates.sort((a, b) => b.getBoundingClientRect().top - a.getBoundingClientRect().top);
        return candidates[0];
      }
    }
    return null;
  }

  function insertTextIntoChat(text, append = true) {
    const input = findChatInput();
    if (!input) {
      return { ok: false, error: "Sohbet giris kutusu bulunamadi. 'Sonucu Kopyala' kullanabilirsiniz." };
    }

    try {
      input.focus();
      if (input.tagName === "TEXTAREA" || input.tagName === "INPUT") {
        const current = input.value || "";
        const next = append && current.trim() ? `${current.replace(/\s+$/, "")}\n\n${text}` : text;
        const proto = input.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
        const descriptor = Object.getOwnPropertyDescriptor(proto, "value");
        if (descriptor && typeof descriptor.set === "function") {
          descriptor.set.call(input, next);
        } else {
          input.value = next;
        }
        input.dispatchEvent(new Event("input", { bubbles: true }));
        input.dispatchEvent(new Event("change", { bubbles: true }));
        return { ok: true };
      }

      // Rich text / contenteditable (ProseMirror / Lexical / TipTap safe insertion)
      const sel = window.getSelection();
      if (sel && typeof document.createRange === "function") {
        const range = document.createRange();
        range.selectNodeContents(input);
        if (!append) {
          sel.removeAllRanges();
          sel.addRange(range);
        } else {
          range.collapse(false);
          sel.removeAllRanges();
          sel.addRange(range);
        }
      }
      const prefix = append && (input.textContent || "").trim() ? "\n\n" : "";
      const inserted = typeof document.execCommand === "function" && document.execCommand("insertText", false, prefix + text);
      if (!inserted) {
        input.textContent = prefix ? `${input.textContent || ""}${prefix}${text}` : text;
        input.dispatchEvent(new Event("input", { bubbles: true }));
      }
      return { ok: true };
    } catch (err) {
      return {
        ok: false,
        error: `Sohbet kutusuna yazilamadi (${err && err.message ? err.message : "hata"}). Panoya kopyalayabilirsiniz.`,
      };
    }
  }

  async function copyToClipboard(text) {
    try {
      if (navigator && navigator.clipboard && typeof navigator.clipboard.writeText === "function") {
        await navigator.clipboard.writeText(text);
        return true;
      }
    } catch (_e) {
      // fallback below
    }
    try {
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      const ok = document.execCommand("copy");
      ta.remove();
      return ok;
    } catch (_e2) {
      return false;
    }
  }

  function formatSummary(call) {
    const args = (call && call.args) || {};
    switch (call.tool) {
      case "run_command":
        return `$ ${args.command}${args.cwd && args.cwd !== "." ? `  (cwd: ${args.cwd})` : ""}`;
      case "read_file":
        return `Dosya oku: ${args.path}${args.offset ? ` (satir ${args.offset}+)` : ""}`;
      case "write_file":
        return `Dosya yaz: ${args.path} (${(args.content || "").length} karakter)`;
      case "edit_file":
        return `Dosya duzenle: ${args.path}`;
      case "delete_path":
        return `Sil: ${args.path}${args.recursive ? " (recursive)" : ""}`;
      case "list_dir":
        return `Klasor listele: ${args.path || "."}`;
      case "terminal_start":
        return `Terminal oturumu baslat${args.cwd ? ` (cwd: ${args.cwd})` : ""}${args.command ? `: ${args.command}` : ""}`;
      case "terminal_write":
        return args.ctrl
          ? `Terminale tus gonder [${args.session_id}]: Ctrl+${String(args.ctrl).toUpperCase()}`
          : `Terminale yaz [${args.session_id}]: ${args.input}`;
      case "terminal_read":
        return `Terminal ciktisi oku [${args.session_id}]`;
      case "terminal_list":
        return "Acik terminal oturumlarini listele";
      case "terminal_kill":
        return `Terminal oturumunu kapat [${args.session_id}]`;
      case "open_terminal_window":
        return `Masaustu terminali ac${args.cwd ? ` (cwd: ${args.cwd})` : ""}${args.command ? `: ${args.command}` : ""}`;
      default:
        return JSON.stringify(args);
    }
  }

  function formatOutputPreview(response) {
    if (!response || !response.ok) {
      return `HATA: ${(response && response.error) || "Bilinmeyen hata"}`;
    }
    const r = response.result || {};
    if (r.tool === "run_command") {
      const parts = [];
      parts.push(`Exit: ${r.exit_code}${r.timed_out ? " (ZAMAN ASIMI)" : ""} | Sure: ${r.duration_ms} ms | CWD: ${r.cwd}`);
      if (r.stdout) parts.push(`--- STDOUT ---\n${r.stdout}`);
      if (r.stderr) parts.push(`--- STDERR ---\n${r.stderr}`);
      if (!r.stdout && !r.stderr) parts.push("(Cikti yok)");
      return parts.join("\n");
    }
    if (r.tool === "terminal_start" || r.tool === "terminal_write" || r.tool === "terminal_read") {
      const state = r.alive ? "ACIK" : `KAPALI (exit=${r.exit_code})`;
      return `[${r.session_id}] ${state} | cursor=${r.cursor}\n${r.output || "(Yeni cikti yok)"}`;
    }
    if (r.tool === "terminal_list") {
      const rows = (r.sessions || []).map(
        (s) => `${s.session_id} | pid=${s.pid} | ${s.alive ? "ACIK" : `KAPALI (${s.exit_code})`} | ${s.cwd}`
      );
      return rows.length ? rows.join("\n") : "(Acik terminal oturumu yok)";
    }
    if (r.tool === "terminal_kill") {
      return `Terminal kapatildi: ${r.session_id}`;
    }
    if (r.tool === "open_terminal_window") {
      return `Masaustu terminal penceresi acildi (${r.launcher}) | CWD: ${r.cwd}`;
    }
    if (r.tool === "read_file") {
      return `Dosya: ${r.path} (${r.total_lines} satir, donen: ${r.lines_returned})\n\n${r.content || ""}`;
    }
    if (r.tool === "write_file") {
      return `Yazildi: ${r.path} (${r.bytes_written} byte)`;
    }
    if (r.tool === "edit_file") {
      return `Duzenlendi: ${r.path} (${r.replacements} degisiklik)`;
    }
    if (r.tool === "delete_path") {
      return `Silindi (${r.type}): ${r.path}`;
    }
    if (r.tool === "list_dir") {
      const lines = (r.entries || []).map(
        (e) => `${e.type === "dir" ? "[DIR] " : "      "}${e.name}${e.type === "file" ? ` (${e.size} B)` : ""}`
      );
      return `Klasor: ${r.path} (${r.total_entries} oge)\n${lines.join("\n")}`;
    }
    return JSON.stringify(r, null, 2);
  }

  function updateTrayCounter() {
    if (!trayCountEl) return;
    let pending = 0;
    for (const rec of activeRecords.values()) {
      if (rec && !rec.locked && rec.valid) pending++;
    }
    trayCountEl.textContent = pending > 0 ? `${pending} Bekleyen` : `${activeRecords.size} Islem`;
    trayCountEl.className = pending > 0 ? "alb-tray-count alb-tray-count-pending" : "alb-tray-count";
  }

  function expandDock() {
    if (!dockEl) return;
    dockEl.classList.remove("alb-dock-collapsed");
    const btn = dockEl.querySelector(".alb-dock-toggle");
    if (btn) btn.textContent = "-";
  }

  function createCardElement(call, cardId, sourceEl) {
    const card = document.createElement("div");
    card.className = "alb-card";
    card.setAttribute("data-alb-card", cardId);

    if (!call.valid) {
      card.innerHTML = `
        <div class="alb-card-header">
          <span class="alb-badge alb-badge-err">Gecersiz Arac Cagrisi</span>
          <button type="button" class="alb-btn alb-btn-xs alb-btn-dismiss">Kapat</button>
        </div>
        <div class="alb-error-text"></div>
      `;
      card.querySelector(".alb-error-text").textContent = call.error || "Bilinmeyen format hatasi";
      card.querySelector(".alb-btn-dismiss").addEventListener("click", () => {
        activeRecords.delete(cardId);
        card.remove();
        updateTrayCounter();
      });
      return card;
    }

    const isCritical = call.tool === "delete_path";
    const isDangerous =
      call.tool === "run_command" ||
      call.tool === "write_file" ||
      call.tool === "edit_file" ||
      call.tool === "terminal_write" ||
      call.tool === "terminal_start" ||
      call.tool === "open_terminal_window";
    const badgeClass = isCritical ? "alb-badge-err" : isDangerous ? "alb-badge-warn" : "alb-badge-info";

    card.innerHTML = `
      <div class="alb-card-header">
        <div class="alb-header-left">
          <span class="alb-badge ${badgeClass}"></span>
          <span class="alb-call-id"></span>
        </div>
        <span class="alb-status alb-status-pending">Onay Bekliyor</span>
      </div>
      <div class="alb-summary"></div>
      <div class="alb-actions">
        <button type="button" class="alb-btn alb-btn-approve">Onayla ve Calistir</button>
        <button type="button" class="alb-btn alb-btn-reject">Reddet</button>
        <button type="button" class="alb-btn alb-btn-sm alb-btn-goto">Koda Git</button>
      </div>
      <div class="alb-output-wrap" hidden>
        <pre class="alb-output"></pre>
        <div class="alb-post-actions">
          <button type="button" class="alb-btn alb-btn-insert">Sohbete Ekle</button>
          <button type="button" class="alb-btn alb-btn-copy">Sonucu Kopyala</button>
          <span class="alb-feedback"></span>
        </div>
      </div>
    `;

    card.querySelector(".alb-badge").textContent = call.tool;
    card.querySelector(".alb-call-id").textContent = `#${call.id}`;
    card.querySelector(".alb-summary").textContent = formatSummary(call);

    const statusEl = card.querySelector(".alb-status");
    const approveBtn = card.querySelector(".alb-btn-approve");
    const rejectBtn = card.querySelector(".alb-btn-reject");
    const gotoBtn = card.querySelector(".alb-btn-goto");
    const actionsEl = card.querySelector(".alb-actions");
    const outputWrap = card.querySelector(".alb-output-wrap");
    const outputPre = card.querySelector(".alb-output");
    const insertBtn = card.querySelector(".alb-btn-insert");
    const copyBtn = card.querySelector(".alb-btn-copy");
    const feedbackEl = card.querySelector(".alb-feedback");

    let lastFormattedResult = "";

    gotoBtn.addEventListener("click", () => {
      try {
        if (sourceEl && typeof sourceEl.scrollIntoView === "function") {
          sourceEl.scrollIntoView({ behavior: "smooth", block: "center" });
        }
      } catch (_e) {
        // ignore
      }
    });

    approveBtn.addEventListener("click", async () => {
      const rec = activeRecords.get(cardId);
      if (rec) rec.locked = true;
      const tracked = trackedNodes.get(sourceEl);
      if (tracked) tracked.locked = true;

      card.setAttribute("data-alb-locked", "true");
      approveBtn.disabled = true;
      rejectBtn.disabled = true;
      statusEl.textContent = "Calisiyor...";
      statusEl.className = "alb-status alb-status-running";
      updateTrayCounter();

      const response = await sendMessage({ type: "RUN_TOOL", call });
      lastFormattedResult = Parser.formatToolResultForChat(call, response);

      outputWrap.hidden = false;
      outputPre.textContent = formatOutputPreview(response);

      if (response && response.ok) {
        const exitBad = response.result && response.result.tool === "run_command" && response.result.exit_code !== 0;
        statusEl.textContent = exitBad ? `Bitti (Exit ${response.result.exit_code})` : "Tamamlandi";
        statusEl.className = `alb-status ${exitBad ? "alb-status-warn" : "alb-status-ok"}`;
      } else {
        statusEl.textContent = "Hata";
        statusEl.className = "alb-status alb-status-err";
      }
      actionsEl.hidden = true;

      if (settings.autoInsertResult) {
        const ins = insertTextIntoChat(lastFormattedResult, true);
        feedbackEl.textContent = ins.ok ? "Sohbet kutusuna eklendi." : ins.error;
      }
    });

    rejectBtn.addEventListener("click", () => {
      const rec = activeRecords.get(cardId);
      if (rec) rec.locked = true;
      const tracked = trackedNodes.get(sourceEl);
      if (tracked) tracked.locked = true;

      card.setAttribute("data-alb-locked", "true");
      statusEl.textContent = "Reddedildi";
      statusEl.className = "alb-status alb-status-rejected";
      actionsEl.hidden = true;
      updateTrayCounter();
    });

    insertBtn.addEventListener("click", () => {
      const ins = insertTextIntoChat(lastFormattedResult, true);
      feedbackEl.textContent = ins.ok ? "Sohbet kutusuna eklendi!" : ins.error;
    });

    copyBtn.addEventListener("click", async () => {
      const ok = await copyToClipboard(lastFormattedResult);
      feedbackEl.textContent = ok ? "Panoya kopyalandi!" : "Kopyalama basarisiz.";
    });

    return card;
  }

  function scanDocument() {
    if (!settings.enabled || !trayListEl) return;

    try {
      const nodes = document.querySelectorAll("pre code, pre");
      let addedNewPending = false;

      for (const el of nodes) {
        if (!el || (el.closest && (el.closest(".alb-card") || el.closest(".alb-dock")))) continue;
        // If <pre> has a <code> child, process the <code> child instead of <pre> twice
        if (el.tagName === "PRE" && el.querySelector && el.querySelector("code")) continue;

        const raw = el.textContent || "";
        const hash = simpleHash(raw);
        const existing = trackedNodes.get(el);

        if (existing) {
          if (existing.locked || existing.hash === hash) continue;
          if (existing.cardEl && existing.cardEl.parentNode) {
            existing.cardEl.remove();
          }
          activeRecords.delete(existing.cardId);
        }

        const hint = detectLanguageHint(el);
        const parsed = Parser.parseToolBlock(raw, { languageHint: hint });

        if (!parsed) {
          trackedNodes.set(el, { hash, cardId: null, cardEl: null, locked: false });
          continue;
        }

        const cardId = `alb_${++cardCounter}`;
        const card = createCardElement(parsed, cardId, el);
        // Prepend newest tool call at top of tray so user sees it immediately without scrolling Arena chat!
        trayListEl.insertBefore(card, trayListEl.firstChild);

        trackedNodes.set(el, { hash, cardId, cardEl: card, locked: false });
        activeRecords.set(cardId, { cardId, cardEl: card, locked: false, valid: Boolean(parsed.valid) });
        if (parsed.valid) addedNewPending = true;
      }

      updateTrayCounter();
      if (addedNewPending) {
        expandDock();
      }
    } catch (err) {
      if (dockEl) {
        const msgEl = dockEl.querySelector(".alb-dock-msg");
        if (msgEl) msgEl.textContent = `Tarama hatasi: ${err && err.message ? err.message : String(err)}`;
      }
    }
  }

  function scheduleScan() {
    if (scanTimer) clearTimeout(scanTimer);
    scanTimer = setTimeout(scanDocument, 300);
  }

  async function refreshStatusAndSettings() {
    const [settingsRes, pingRes] = await Promise.all([
      sendMessage({ type: "GET_SETTINGS" }),
      sendMessage({ type: "SERVER_PING" }),
    ]);

    if (settingsRes && settingsRes.ok && settingsRes.settings) {
      settings = settingsRes.settings;
    }

    if (pingRes && pingRes.ok && pingRes.result) {
      hostStatus = {
        connected: true,
        workspace_root: pingRes.result.workspace_root || "",
        workspace_exists: Boolean(pingRes.result.workspace_exists),
        full_system_access: Boolean(pingRes.result.full_system_access),
        authMissing: false,
        error: null,
      };
    } else {
      hostStatus = {
        connected: false,
        workspace_root: "",
        full_system_access: false,
        authMissing: Boolean(pingRes && pingRes.authMissing),
        error: (pingRes && pingRes.error) || "Baglanti kurulamadi",
      };
    }

    if (dockEl) updateDockUI(dockEl);
  }

  function updateDockUI(dock) {
    const dot = dock.querySelector(".alb-dot");
    const statusText = dock.querySelector(".alb-dock-status");
    const wsEl = dock.querySelector(".alb-dock-ws");

    if (hostStatus.connected && (hostStatus.workspace_exists || hostStatus.full_system_access)) {
      dot.className = "alb-dot alb-dot-ok";
      statusText.textContent = hostStatus.full_system_access ? "Bridge: Tam Erisim" : "Local Bridge Bagli";
      wsEl.textContent = hostStatus.full_system_access
        ? `Tum Bilgisayar (Varsayilan: ${hostStatus.workspace_root || "~"})`
        : hostStatus.workspace_root;
      wsEl.title = hostStatus.workspace_root;
    } else if (hostStatus.connected && !hostStatus.workspace_exists) {
      dot.className = "alb-dot alb-dot-warn";
      statusText.textContent = "Workspace Eksik";
      wsEl.textContent = hostStatus.workspace_root || "config.json icinde workspace_root ayarlayin";
    } else if (hostStatus.authMissing) {
      dot.className = "alb-dot alb-dot-warn";
      statusText.textContent = "Token Gerekli";
      wsEl.textContent = hostStatus.error || "";
      wsEl.title = hostStatus.error || "";
    } else {
      dot.className = "alb-dot alb-dot-err";
      statusText.textContent = "Sunucu Kapali";
      wsEl.textContent = hostStatus.error || "";
      wsEl.title = hostStatus.error || "";
    }
  }

  function createFloatingDock() {
    const existing = document.querySelector(".alb-dock");
    if (existing) return existing;

    const dock = document.createElement("div");
    dock.className = "alb-dock alb-dock-collapsed";
    dock.innerHTML = `
      <div class="alb-dock-header" title="Arena Local Bridge">
        <span class="alb-dot alb-dot-warn"></span>
        <span class="alb-dock-status">Kontrol ediliyor...</span>
        <span class="alb-tray-count">0 Islem</span>
        <button type="button" class="alb-dock-toggle" aria-label="Paneli Ac/Kapat">+</button>
      </div>
      <div class="alb-dock-body">
        <div class="alb-dock-ws-label">Calisma Ortami:</div>
        <div class="alb-dock-ws">-</div>
        <div class="alb-dock-btns">
          <button type="button" class="alb-btn alb-btn-sm alb-copy-sys">Sistem Promptu Kopyala</button>
          <button type="button" class="alb-btn alb-btn-sm alb-insert-sys">Sohbete Yapistir</button>
          <button type="button" class="alb-btn alb-btn-sm alb-rescan">Tara / Ping</button>
        </div>
        <div class="alb-dock-msg"></div>
        <div class="alb-tray-list"></div>
      </div>
    `;

    const toggleBtn = dock.querySelector(".alb-dock-toggle");
    const header = dock.querySelector(".alb-dock-header");
    const msgEl = dock.querySelector(".alb-dock-msg");
    trayListEl = dock.querySelector(".alb-tray-list");
    trayCountEl = dock.querySelector(".alb-tray-count");

    function toggle() {
      const collapsed = dock.classList.toggle("alb-dock-collapsed");
      toggleBtn.textContent = collapsed ? "+" : "-";
    }

    header.addEventListener("click", (e) => {
      if (e.target === toggleBtn || e.currentTarget === header) toggle();
    });

    dock.querySelector(".alb-copy-sys").addEventListener("click", async () => {
      const ok = await copyToClipboard(Parser.SYSTEM_PROMPT);
      msgEl.textContent = ok ? "Sistem promptu panoya kopyalandi." : "Kopyalama basarisiz.";
    });

    dock.querySelector(".alb-insert-sys").addEventListener("click", () => {
      const res = insertTextIntoChat(Parser.SYSTEM_PROMPT, false);
      msgEl.textContent = res.ok ? "Sohbet kutusuna yerlestirildi." : res.error;
    });

    dock.querySelector(".alb-rescan").addEventListener("click", async () => {
      msgEl.textContent = "Yenileniyor...";
      await refreshStatusAndSettings();
      scanDocument();
      msgEl.textContent = "Tarama ve baglanti kontrolu tamamlandi.";
    });

    document.body.appendChild(dock);
    return dock;
  }

  async function init() {
    dockEl = createFloatingDock();
    await refreshStatusAndSettings();
    scanDocument();

    if (document.body && typeof MutationObserver !== "undefined") {
      const observer = new MutationObserver(() => {
        scheduleScan();
      });
      observer.observe(document.body, {
        childList: true,
        subtree: true,
        characterData: true,
      });
    }

    try {
      if (typeof chrome !== "undefined" && chrome.storage && chrome.storage.onChanged) {
        chrome.storage.onChanged.addListener((changes) => {
          if (!changes) return;
          if (changes.enabled) settings.enabled = Boolean(changes.enabled.newValue);
          if (changes.autoInsertResult) settings.autoInsertResult = Boolean(changes.autoInsertResult.newValue);
          if (changes.apiToken || changes.serverUrl) {
            refreshStatusAndSettings();
          }
        });
      }
    } catch (_e) {
      // ignore if extension context invalidated
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
