(function () {
  "use strict";

  const Parser = window.ArenaBridgeParser;
  if (!Parser) return;

  let settings = {
    enabled: true,
    autoRun: true,
    autoInsertResult: true,
    autoSubmitResult: true,
    maxAutoSteps: 20,
  };
  let hostStatus = { connected: false, workspace_root: "", full_system_access: false, error: null };
  let scanTimer = null;
  let cardCounter = 0;
  let initialScanDone = false;
  let autoBusy = false;
  let autoStepsCount = 0;

  // Map from source code element -> { hash, occurrenceKey, cardId, cardEl, locked }
  const trackedNodes = new WeakMap();
  // Active UI card records keyed by cardId
  const activeRecords = new Map();
  // Occurrence keys ("<hash>#<idx>") already executed or baselined
  const executedOccurrences = new Set();

  let dockEl = null;
  let trayListEl = null;
  let trayCountEl = null;
  let autoToggleBtn = null;

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

  function setDockMessage(text) {
    if (!dockEl) return;
    const msgEl = dockEl.querySelector(".alb-dock-msg");
    if (msgEl) msgEl.textContent = text || "";
  }

  function detectLanguageHint(codeEl) {
    if (!codeEl || typeof codeEl.getAttribute !== "function") return "";
    const parentClass =
      codeEl.parentElement && typeof codeEl.parentElement.className === "string"
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
      if (label.includes("arena-tool-result")) return "arena-tool-result";
      if (label.includes("arena-tool")) return "arena-tool";
      if (label.includes("tool_call")) return "tool_call";
    }
    return "";
  }

  function isModelStreaming() {
    try {
      const buttons = document.querySelectorAll("button");
      for (const btn of buttons) {
        if (btn.closest && btn.closest(".alb-dock")) continue;
        const rect = btn.getBoundingClientRect();
        if (rect.width <= 0 || rect.height <= 0 || btn.disabled) continue;
        const label = `${btn.getAttribute("aria-label") || ""} ${btn.getAttribute("title") || ""} ${btn.textContent || ""}`
          .trim()
          .toLowerCase();
        if (
          label === "stop" ||
          label === "durdur" ||
          label.includes("stop generating") ||
          label.includes("stop response") ||
          label.includes("üretimi durdur")
        ) {
          return true;
        }
      }
    } catch (_e) {
      // ignore
    }
    return false;
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
        if (el.closest && el.closest(".alb-dock")) return false;
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

  function findSubmitButton(input) {
    if (!input) return null;
    const containers = [];
    const form = input.closest ? input.closest("form") : null;
    if (form) containers.push(form);

    let p = input.parentElement;
    for (let i = 0; i < 4 && p; i++) {
      containers.push(p);
      p = p.parentElement;
    }

    for (const box of containers) {
      const directSubmit = box.querySelector('button[type="submit"]:not(:disabled)');
      if (directSubmit && directSubmit.getBoundingClientRect().width > 0) {
        return directSubmit;
      }

      const buttons = Array.from(box.querySelectorAll("button:not(:disabled)")).filter((btn) => {
        if (btn.closest && btn.closest(".alb-dock")) return false;
        const rect = btn.getBoundingClientRect();
        if (rect.width <= 0 || rect.height <= 0) return false;
        const label = `${btn.getAttribute("aria-label") || ""} ${btn.getAttribute("title") || ""} ${btn.textContent || ""}`
          .trim()
          .toLowerCase();
        if (label.includes("attach") || label.includes("upload") || label.includes("mic") || label.includes("clear")) {
          return false;
        }
        return (
          label.includes("send") ||
          label.includes("submit") ||
          label.includes("gönder") ||
          label.includes("gonder") ||
          btn.getAttribute("type") === "submit"
        );
      });
      if (buttons.length > 0) {
        return buttons[buttons.length - 1];
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
        return { ok: true, input };
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
      const inserted =
        typeof document.execCommand === "function" && document.execCommand("insertText", false, prefix + text);
      if (!inserted) {
        input.textContent = prefix ? `${input.textContent || ""}${prefix}${text}` : text;
        input.dispatchEvent(new Event("input", { bubbles: true }));
      }
      return { ok: true, input };
    } catch (err) {
      return {
        ok: false,
        error: `Sohbet kutusuna yazilamadi (${err && err.message ? err.message : "hata"}). Panoya kopyalayabilirsiniz.`,
      };
    }
  }

  async function submitChatMessage(input) {
    if (!input) return { ok: false, error: "Giris kutusu yok." };
    await new Promise((r) => setTimeout(r, 180));

    const sendBtn = findSubmitButton(input);
    if (sendBtn && !sendBtn.disabled) {
      sendBtn.click();
      return { ok: true, method: "button" };
    }

    // Fallback: press Enter without Shift
    try {
      input.focus();
      const evInit = {
        key: "Enter",
        code: "Enter",
        keyCode: 13,
        which: 13,
        bubbles: true,
        cancelable: true,
      };
      input.dispatchEvent(new KeyboardEvent("keydown", evInit));
      input.dispatchEvent(new KeyboardEvent("keypress", evInit));
      input.dispatchEvent(new KeyboardEvent("keyup", evInit));
      return { ok: true, method: "enter" };
    } catch (err) {
      return { ok: false, error: err && err.message ? err.message : String(err) };
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

  function updateAutoToggleUI() {
    if (!autoToggleBtn) return;
    if (settings.autoRun) {
      autoToggleBtn.textContent = `Otonom: ACIK (${autoStepsCount}/${settings.maxAutoSteps || 20})`;
      autoToggleBtn.className = "alb-btn alb-btn-sm alb-btn-auto-on";
    } else {
      autoToggleBtn.textContent = "Otonom: KAPALI";
      autoToggleBtn.className = "alb-btn alb-btn-sm";
    }
  }

  function expandDock() {
    if (!dockEl) return;
    dockEl.classList.remove("alb-dock-collapsed");
    const btn = dockEl.querySelector(".alb-dock-toggle");
    if (btn) btn.textContent = "-";
  }

  function createCardElement(call, cardId, sourceEl, occurrenceKey) {
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
      return { card, execute: null };
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

    async function executeCall(options = { insertAndSubmit: false }) {
      const rec = activeRecords.get(cardId);
      if (rec) rec.locked = true;
      const tracked = trackedNodes.get(sourceEl);
      if (tracked) tracked.locked = true;
      if (occurrenceKey) executedOccurrences.add(occurrenceKey);

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

      if (options.insertAndSubmit) {
        if (settings.autoInsertResult) {
          const ins = insertTextIntoChat(lastFormattedResult, true);
          feedbackEl.textContent = ins.ok ? "Sohbet kutusuna eklendi." : ins.error;
          if (ins.ok && settings.autoSubmitResult) {
            const sub = await submitChatMessage(ins.input);
            feedbackEl.textContent = sub.ok ? "Otomatik gonderildi!" : `Eklendi ama gonderilemedi: ${sub.error}`;
          }
        }
      }

      return lastFormattedResult;
    }

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
      await executeCall({ insertAndSubmit: true });
    });

    rejectBtn.addEventListener("click", () => {
      const rec = activeRecords.get(cardId);
      if (rec) rec.locked = true;
      const tracked = trackedNodes.get(sourceEl);
      if (tracked) tracked.locked = true;
      if (occurrenceKey) executedOccurrences.add(occurrenceKey);

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

    return { card, execute: executeCall };
  }

  async function processAutoQueue(pendingRecords) {
    if (!pendingRecords.length || autoBusy || !settings.autoRun) return;
    if (!hostStatus.connected) {
      setDockMessage("Otonom mod bekliyor: Yerel sunucu bagli degil.");
      return;
    }

    const limit = Math.max(1, Number(settings.maxAutoSteps) || 20);
    if (autoStepsCount >= limit) {
      settings.autoRun = false;
      updateAutoToggleUI();
      setDockMessage(`Otonom adim sinirina (${limit}) ulasildi; duraklatildi.`);
      return;
    }

    autoBusy = true;
    try {
      const batchResults = [];
      for (const rec of pendingRecords) {
        if (!settings.autoRun) break;
        if (rec.locked || !rec.execute) continue;
        autoStepsCount += 1;
        updateAutoToggleUI();
        setDockMessage(`Otonom calistiriliyor (${rec.tool})...`);
        const formatted = await rec.execute({ insertAndSubmit: false });
        if (formatted) batchResults.push(formatted);
      }

      if (batchResults.length > 0 && settings.autoInsertResult) {
        const combined = batchResults.join("\n\n");
        const ins = insertTextIntoChat(combined, true);
        if (ins.ok) {
          if (settings.autoSubmitResult) {
            const sub = await submitChatMessage(ins.input);
            setDockMessage(
              sub.ok
                ? `Sonuc sohbete otomatik gonderildi (${autoStepsCount}/${limit}).`
                : `Sonuc yazildi, gonderme bekliyor: ${sub.error}`
            );
          } else {
            setDockMessage("Sonuc sohbet kutusuna otomatik yazildi.");
          }
        } else {
          setDockMessage(ins.error);
        }
      }
    } catch (err) {
      setDockMessage(`Otonom calistirma hatasi: ${err && err.message ? err.message : String(err)}`);
    } finally {
      autoBusy = false;
    }
  }

  function scanDocument() {
    if (!settings.enabled || !trayListEl) return;

    try {
      const nodes = document.querySelectorAll("pre code, pre");
      const hashCounts = new Map();
      const newlyAppearedPending = [];

      for (const el of nodes) {
        if (!el || (el.closest && (el.closest(".alb-card") || el.closest(".alb-dock")))) continue;
        if (el.tagName === "PRE" && el.querySelector && el.querySelector("code")) continue;

        const raw = el.textContent || "";
        const hash = simpleHash(raw);
        const occIndex = hashCounts.get(hash) || 0;
        hashCounts.set(hash, occIndex + 1);
        const occurrenceKey = `${hash}#${occIndex}`;

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
          trackedNodes.set(el, { hash, occurrenceKey, cardId: null, cardEl: null, locked: false });
          continue;
        }

        // Baseline any tool blocks that already existed on initial page load so old history never auto-runs!
        if (!initialScanDone) {
          executedOccurrences.add(occurrenceKey);
        }

        const alreadyHandled = executedOccurrences.has(occurrenceKey);
        const cardId = `alb_${++cardCounter}`;
        const { card, execute } = createCardElement(parsed, cardId, el, occurrenceKey);
        trayListEl.insertBefore(card, trayListEl.firstChild);

        trackedNodes.set(el, { hash, occurrenceKey, cardId, cardEl: card, locked: alreadyHandled });
        const rec = {
          cardId,
          cardEl: card,
          tool: parsed.tool,
          locked: alreadyHandled,
          valid: Boolean(parsed.valid),
          execute,
        };
        activeRecords.set(cardId, rec);

        if (alreadyHandled) {
          const st = card.querySelector(".alb-status");
          if (st) st.textContent = "Gecmis Oge";
        } else if (parsed.valid) {
          newlyAppearedPending.push(rec);
        }
      }

      initialScanDone = true;
      updateTrayCounter();

      if (newlyAppearedPending.length > 0) {
        expandDock();
        if (settings.autoRun) {
          if (isModelStreaming()) {
            setDockMessage("Model yaniti tamamlaniyor, bitince otomatik calisacak...");
            scheduleScan(700);
          } else {
            processAutoQueue(newlyAppearedPending);
          }
        }
      }
    } catch (err) {
      setDockMessage(`Tarama hatasi: ${err && err.message ? err.message : String(err)}`);
    }
  }

  function scheduleScan(customDelay) {
    if (scanTimer) clearTimeout(scanTimer);
    const delay = typeof customDelay === "number" ? customDelay : settings.autoRun ? 850 : 300;
    scanTimer = setTimeout(scanDocument, delay);
  }

  async function refreshStatusAndSettings() {
    const [settingsRes, pingRes] = await Promise.all([
      sendMessage({ type: "GET_SETTINGS" }),
      sendMessage({ type: "SERVER_PING" }),
    ]);

    if (settingsRes && settingsRes.ok && settingsRes.settings) {
      settings = { ...settings, ...settingsRes.settings };
      updateAutoToggleUI();
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
          <button type="button" class="alb-btn alb-btn-sm alb-auto-toggle">Otonom: ACIK</button>
          <button type="button" class="alb-btn alb-btn-sm alb-copy-sys">Prompt Kopyala</button>
          <button type="button" class="alb-btn alb-btn-sm alb-insert-sys">Sohbete Yapistir</button>
          <button type="button" class="alb-btn alb-btn-sm alb-rescan">Tara / Ping</button>
        </div>
        <div class="alb-dock-msg"></div>
        <div class="alb-tray-list"></div>
      </div>
    `;

    const toggleBtn = dock.querySelector(".alb-dock-toggle");
    const header = dock.querySelector(".alb-dock-header");
    trayListEl = dock.querySelector(".alb-tray-list");
    trayCountEl = dock.querySelector(".alb-tray-count");
    autoToggleBtn = dock.querySelector(".alb-auto-toggle");

    function toggle() {
      const collapsed = dock.classList.toggle("alb-dock-collapsed");
      toggleBtn.textContent = collapsed ? "+" : "-";
    }

    header.addEventListener("click", (e) => {
      if (e.target === toggleBtn || e.currentTarget === header) toggle();
    });

    autoToggleBtn.addEventListener("click", async () => {
      const nextAuto = !settings.autoRun;
      settings.autoRun = nextAuto;
      if (nextAuto) autoStepsCount = 0;
      updateAutoToggleUI();
      await sendMessage({ type: "SAVE_SETTINGS", settings: { autoRun: nextAuto } });
      setDockMessage(nextAuto ? "Otonom mod acildi." : "Otonom mod duraklatildi.");
    });

    dock.querySelector(".alb-copy-sys").addEventListener("click", async () => {
      const ok = await copyToClipboard(Parser.SYSTEM_PROMPT);
      setDockMessage(ok ? "Sistem promptu panoya kopyalandi." : "Kopyalama basarisiz.");
    });

    dock.querySelector(".alb-insert-sys").addEventListener("click", () => {
      const res = insertTextIntoChat(Parser.SYSTEM_PROMPT, false);
      setDockMessage(res.ok ? "Sohbet kutusuna yerlestirildi." : res.error);
    });

    dock.querySelector(".alb-rescan").addEventListener("click", async () => {
      setDockMessage("Yenileniyor...");
      await refreshStatusAndSettings();
      scanDocument();
      setDockMessage("Tarama ve baglanti kontrolu tamamlandi.");
    });

    document.body.appendChild(dock);
    return dock;
  }

  async function init() {
    dockEl = createFloatingDock();
    await refreshStatusAndSettings();
    scanDocument();

    if (document.body && typeof MutationObserver !== "undefined") {
      const observer = new MutationObserver((mutations) => {
        // Ignore mutations inside our own dock so tray updates don't re-trigger scan timer
        const hasExternal = mutations.some((m) => !(m.target && m.target.closest && m.target.closest(".alb-dock")));
        if (hasExternal) scheduleScan();
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
          if (changes.autoRun) {
            settings.autoRun = Boolean(changes.autoRun.newValue);
            updateAutoToggleUI();
          }
          if (changes.autoInsertResult) settings.autoInsertResult = Boolean(changes.autoInsertResult.newValue);
          if (changes.autoSubmitResult) settings.autoSubmitResult = Boolean(changes.autoSubmitResult.newValue);
          if (changes.maxAutoSteps) {
            settings.maxAutoSteps = Number(changes.maxAutoSteps.newValue) || 20;
            updateAutoToggleUI();
          }
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
