(function () {
  "use strict";

  const Parser = window.ArenaBridgeParser;
  if (!Parser) return;

  const PROCESSED_ATTR = "data-alb-processed";
  const SOURCE_HASH_ATTR = "data-alb-hash";
  const CARD_ID_ATTR = "data-alb-card-id";

  let settings = { enabled: true, autoInsertResult: false };
  let hostStatus = { connected: false, workspace_root: "", error: null };
  let scanTimer = null;
  let cardCounter = 0;

  function simpleHash(str) {
    let h = 2166136261;
    for (let i = 0; i < str.length; i++) {
      h ^= str.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return String(h >>> 0);
  }

  function sendMessage(msg) {
    return new Promise((resolve) => {
      try {
        chrome.runtime.sendMessage(msg, (res) => {
          if (chrome.runtime.lastError) {
            resolve({ ok: false, error: chrome.runtime.lastError.message });
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
    const classes = `${codeEl.className || ""} ${(codeEl.parentElement && codeEl.parentElement.className) || ""}`;
    const langMatch = classes.match(/language-([a-zA-Z0-9_-]+)/);
    if (langMatch) return langMatch[1];

    const dataLang = codeEl.getAttribute("data-language") || (codeEl.parentElement && codeEl.parentElement.getAttribute("data-language"));
    if (dataLang) return dataLang;

    // Look for common code block header labels in chat UIs
    const pre = codeEl.closest("pre");
    if (pre && pre.parentElement) {
      const prev = pre.previousElementSibling;
      if (prev && prev.textContent) {
        const label = prev.textContent.trim().toLowerCase();
        if (label.includes("arena-tool")) return "arena-tool";
        if (label.includes("tool_call")) return "tool_call";
      }
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
        const rect = el.getBoundingClientRect();
        return rect.width > 80 && rect.height > 20 && !el.disabled;
      });
      if (candidates.length > 0) {
        // Prefer the lowest visible input on screen (main prompt box)
        candidates.sort((a, b) => b.getBoundingClientRect().top - a.getBoundingClientRect().top);
        return candidates[0];
      }
    }
    return null;
  }

  function insertTextIntoChat(text, append = true) {
    const input = findChatInput();
    if (!input) {
      return { ok: false, error: "Sohbet giris kutusu bulunamadi. Metni panoya kopyalayabilirsiniz." };
    }

    input.focus();
    if (input.tagName === "TEXTAREA" || input.tagName === "INPUT") {
      const current = input.value || "";
      const next = append && current.trim() ? `${current.replace(/\s+$/, "")}\n\n${text}` : text;
      const proto = input.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      const descriptor = Object.getOwnPropertyDescriptor(proto, "value");
      if (descriptor && descriptor.set) {
        descriptor.set.call(input, next);
      } else {
        input.value = next;
      }
      input.dispatchEvent(new Event("input", { bubbles: true }));
      input.dispatchEvent(new Event("change", { bubbles: true }));
      return { ok: true };
    }

    // contenteditable fallback
    const currentText = input.innerText || "";
    const nextText = append && currentText.trim() ? `${currentText.replace(/\s+$/, "")}\n\n${text}` : text;
    input.innerText = nextText;
    input.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: text }));
    return { ok: true };
  }

  async function copyToClipboard(text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch (_e) {
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      const ok = document.execCommand("copy");
      ta.remove();
      return ok;
    }
  }

  function formatSummary(call) {
    const args = call.args || {};
    switch (call.tool) {
      case "run_command":
        return `$ ${args.command}${args.cwd && args.cwd !== "." ? `  (cwd: ${args.cwd})` : ""}`;
      case "read_file":
        return `Dosya oku: ${args.path}${args.offset ? ` (satir ${args.offset}+)` : ""}`;
      case "write_file":
        return `Dosya yaz: ${args.path} (${(args.content || "").length} karakter)`;
      case "list_dir":
        return `Klasor listele: ${args.path || "."}`;
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
    if (r.tool === "read_file") {
      return `Dosya: ${r.path} (${r.total_lines} satir, donen: ${r.lines_returned})\n\n${r.content || ""}`;
    }
    if (r.tool === "write_file") {
      return `Yazildi: ${r.path} (${r.bytes_written} byte)`;
    }
    if (r.tool === "list_dir") {
      const lines = (r.entries || []).map((e) => `${e.type === "dir" ? "[DIR] " : "      "}${e.name}${e.type === "file" ? ` (${e.size} B)` : ""}`);
      return `Klasor: ${r.path} (${r.total_entries} oge)\n${lines.join("\n")}`;
    }
    return JSON.stringify(r, null, 2);
  }

  function createCardElement(call, cardId) {
    const card = document.createElement("div");
    card.className = "alb-card";
    card.setAttribute("data-alb-card", cardId);

    if (!call.valid) {
      card.innerHTML = `
        <div class="alb-card-header">
          <span class="alb-badge alb-badge-err">Gecersiz Arac Cagrisi</span>
        </div>
        <div class="alb-error-text"></div>
      `;
      card.querySelector(".alb-error-text").textContent = call.error;
      return card;
    }

    const isDangerous = call.tool === "run_command" || call.tool === "write_file";
    card.innerHTML = `
      <div class="alb-card-header">
        <div class="alb-header-left">
          <span class="alb-badge ${isDangerous ? "alb-badge-warn" : "alb-badge-info"}"></span>
          <span class="alb-call-id"></span>
        </div>
        <span class="alb-status alb-status-pending">Onay Bekliyor</span>
      </div>
      <div class="alb-summary"></div>
      <div class="alb-actions">
        <button type="button" class="alb-btn alb-btn-approve">Onayla ve Calistir</button>
        <button type="button" class="alb-btn alb-btn-reject">Reddet</button>
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
    const actionsEl = card.querySelector(".alb-actions");
    const outputWrap = card.querySelector(".alb-output-wrap");
    const outputPre = card.querySelector(".alb-output");
    const insertBtn = card.querySelector(".alb-btn-insert");
    const copyBtn = card.querySelector(".alb-btn-copy");
    const feedbackEl = card.querySelector(".alb-feedback");

    let lastFormattedResult = "";

    approveBtn.addEventListener("click", async () => {
      card.setAttribute("data-alb-locked", "true");
      approveBtn.disabled = true;
      rejectBtn.disabled = true;
      statusEl.textContent = "Calisiyor...";
      statusEl.className = "alb-status alb-status-running";

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
      card.setAttribute("data-alb-locked", "true");
      statusEl.textContent = "Reddedildi";
      statusEl.className = "alb-status alb-status-rejected";
      actionsEl.hidden = true;
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
    if (!settings.enabled) return;

    const codeBlocks = document.querySelectorAll("pre code");
    for (const codeEl of codeBlocks) {
      if (codeEl.closest(".alb-card") || codeEl.closest(".alb-dock")) continue;

      const preEl = codeEl.closest("pre");
      if (!preEl || !preEl.parentElement) continue;

      const raw = codeEl.textContent || "";
      const hash = simpleHash(raw);
      const prevHash = codeEl.getAttribute(SOURCE_HASH_ATTR);

      const existingCardId = codeEl.getAttribute(CARD_ID_ATTR);
      if (existingCardId) {
        const existingCard = document.querySelector(`[data-alb-card="${existingCardId}"]`);
        if (existingCard && (existingCard.getAttribute("data-alb-locked") === "true" || prevHash === hash)) {
          continue;
        }
        if (existingCard) existingCard.remove();
      }

      const hint = detectLanguageHint(codeEl);
      const parsed = Parser.parseToolBlock(raw, { languageHint: hint });
      codeEl.setAttribute(SOURCE_HASH_ATTR, hash);
      codeEl.setAttribute(PROCESSED_ATTR, "true");

      if (!parsed) continue;

      const cardId = `alb_${++cardCounter}`;
      codeEl.setAttribute(CARD_ID_ATTR, cardId);
      const card = createCardElement(parsed, cardId);
      preEl.insertAdjacentElement("afterend", card);
    }
  }

  function scheduleScan() {
    if (scanTimer) clearTimeout(scanTimer);
    scanTimer = setTimeout(scanDocument, 300);
  }

  async function refreshStatusAndSettings(dockEl) {
    const [settingsRes, pingRes] = await Promise.all([
      sendMessage({ type: "GET_SETTINGS" }),
      sendMessage({ type: "NATIVE_PING" }),
    ]);

    if (settingsRes && settingsRes.ok && settingsRes.settings) {
      settings = settingsRes.settings;
    }

    if (pingRes && pingRes.ok && pingRes.result) {
      hostStatus = {
        connected: true,
        workspace_root: pingRes.result.workspace_root || "",
        workspace_exists: Boolean(pingRes.result.workspace_exists),
        error: null,
      };
    } else {
      hostStatus = {
        connected: false,
        workspace_root: "",
        error: (pingRes && pingRes.error) || "Baglanti kurulamadi",
      };
    }

    if (dockEl) updateDockUI(dockEl);
  }

  function updateDockUI(dockEl) {
    const dot = dockEl.querySelector(".alb-dot");
    const statusText = dockEl.querySelector(".alb-dock-status");
    const wsEl = dockEl.querySelector(".alb-dock-ws");

    if (hostStatus.connected && hostStatus.workspace_exists) {
      dot.className = "alb-dot alb-dot-ok";
      statusText.textContent = "Local Bridge Bagli";
      wsEl.textContent = hostStatus.workspace_root;
      wsEl.title = hostStatus.workspace_root;
    } else if (hostStatus.connected && !hostStatus.workspace_exists) {
      dot.className = "alb-dot alb-dot-warn";
      statusText.textContent = "Workspace Eksik";
      wsEl.textContent = hostStatus.workspace_root || "config.json icinde workspace_root ayarlayin";
    } else {
      dot.className = "alb-dot alb-dot-err";
      statusText.textContent = "Bridge Bagli Degil";
      wsEl.textContent = hostStatus.error || "";
      wsEl.title = hostStatus.error || "";
    }
  }

  function createFloatingDock() {
    if (document.querySelector(".alb-dock")) return null;

    const dock = document.createElement("div");
    dock.className = "alb-dock alb-dock-collapsed";
    dock.innerHTML = `
      <div class="alb-dock-header" title="Arena Local Bridge">
        <span class="alb-dot alb-dot-warn"></span>
        <span class="alb-dock-status">Kontrol ediliyor...</span>
        <button type="button" class="alb-dock-toggle" aria-label="Paneli Ac/Kapat">+</button>
      </div>
      <div class="alb-dock-body">
        <div class="alb-dock-ws-label">Calisma Klasoru:</div>
        <div class="alb-dock-ws">-</div>
        <div class="alb-dock-btns">
          <button type="button" class="alb-btn alb-btn-sm alb-copy-sys">Sistem Promptu Kopyala</button>
          <button type="button" class="alb-btn alb-btn-sm alb-insert-sys">Sohbete Yapistir</button>
          <button type="button" class="alb-btn alb-btn-sm alb-rescan">Tara / Ping</button>
        </div>
        <div class="alb-dock-msg"></div>
      </div>
    `;

    const toggleBtn = dock.querySelector(".alb-dock-toggle");
    const header = dock.querySelector(".alb-dock-header");
    const msgEl = dock.querySelector(".alb-dock-msg");

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
      await refreshStatusAndSettings(dock);
      scanDocument();
      msgEl.textContent = "Tarama ve baglanti kontrolu tamamlandi.";
    });

    document.body.appendChild(dock);
    return dock;
  }

  async function init() {
    const dock = createFloatingDock();
    await refreshStatusAndSettings(dock);
    scanDocument();

    const observer = new MutationObserver(() => {
      scheduleScan();
    });
    observer.observe(document.body, {
      childList: true,
      subtree: true,
      characterData: true,
    });

    chrome.storage.onChanged.addListener((changes) => {
      if (changes.enabled) settings.enabled = Boolean(changes.enabled.newValue);
      if (changes.autoInsertResult) settings.autoInsertResult = Boolean(changes.autoInsertResult.newValue);
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
