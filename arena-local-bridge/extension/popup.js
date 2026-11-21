"use strict";

function sendMsg(msg) {
  return new Promise((resolve) => {
    try {
      if (typeof chrome === "undefined" || !chrome.runtime || !chrome.runtime.sendMessage) {
        resolve({ ok: false, error: "Chrome runtime kullanilamiyor." });
        return;
      }
      chrome.runtime.sendMessage(msg, (res) => {
        if (chrome.runtime && chrome.runtime.lastError) {
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

async function copyText(text) {
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

document.addEventListener("DOMContentLoaded", async () => {
  const statusBadge = document.getElementById("statusBadge");
  const hostInfo = document.getElementById("hostInfo");
  const pingBtn = document.getElementById("pingBtn");
  const serverUrlInput = document.getElementById("serverUrlInput");
  const apiTokenInput = document.getElementById("apiTokenInput");
  const toggleTokenBtn = document.getElementById("toggleTokenBtn");
  const saveConnBtn = document.getElementById("saveConnBtn");
  const enabledChk = document.getElementById("enabledChk");
  const autoRunChk = document.getElementById("autoRunChk");
  const autoInsertChk = document.getElementById("autoInsertChk");
  const autoSubmitChk = document.getElementById("autoSubmitChk");
  const maxAutoStepsInput = document.getElementById("maxAutoStepsInput");
  const copyPromptBtn = document.getElementById("copyPromptBtn");
  const msgBox = document.getElementById("msgBox");

  async function runPing() {
    statusBadge.textContent = "Test ediliyor...";
    statusBadge.className = "pill pill-wait";
    const res = await sendMsg({ type: "SERVER_PING" });
    if (res && res.ok && res.result) {
      const r = res.result;
      if (r.full_system_access) {
        statusBadge.textContent = "Tam Erisim";
        statusBadge.className = "pill pill-warn";
      } else if (r.workspace_exists) {
        statusBadge.textContent = "Bagli";
        statusBadge.className = "pill pill-ok";
      } else {
        statusBadge.textContent = "Workspace Eksik";
        statusBadge.className = "pill pill-warn";
      }
      hostInfo.textContent = [
        `Server v${r.server_version || r.host_version} | Python ${r.python_version}`,
        `Mod: ${r.full_system_access ? "Tum Bilgisayar (Tam Erisim)" : "Klasor Kilidi (Jail)"}`,
        `Varsayilan Dizin: ${r.workspace_root || "(ayarlanmamis)"}`,
        `Config: ${r.config_path}`,
      ].join("\n");
    } else {
      statusBadge.textContent = res && res.authMissing ? "Token Gerekli" : "Baglanti Yok";
      statusBadge.className = "pill pill-err";
      hostInfo.textContent = (res && res.error) || "Yerel sunucu baglantisi basarisiz.";
    }
  }

  const info = await sendMsg({ type: "GET_EXTENSION_INFO" });
  if (info && info.ok && info.settings) {
    serverUrlInput.value = info.settings.serverUrl || "http://127.0.0.1:38450";
    apiTokenInput.value = info.settings.apiToken || "";
    enabledChk.checked = Boolean(info.settings.enabled);
    autoRunChk.checked = Boolean(info.settings.autoRun);
    autoInsertChk.checked = Boolean(info.settings.autoInsertResult);
    autoSubmitChk.checked = Boolean(info.settings.autoSubmitResult);
    maxAutoStepsInput.value = String(info.settings.maxAutoSteps || 20);
  }

  toggleTokenBtn.addEventListener("click", () => {
    const isHidden = apiTokenInput.type === "password";
    apiTokenInput.type = isHidden ? "text" : "password";
    toggleTokenBtn.textContent = isHidden ? "Gizle" : "Goster";
  });

  saveConnBtn.addEventListener("click", async () => {
    const saveRes = await sendMsg({
      type: "SAVE_SETTINGS",
      settings: {
        serverUrl: serverUrlInput.value.trim(),
        apiToken: apiTokenInput.value.trim(),
      },
    });
    if (!saveRes || !saveRes.ok) {
      msgBox.textContent = (saveRes && saveRes.error) || "Kaydetme hatasi.";
      return;
    }
    serverUrlInput.value = saveRes.settings.serverUrl;
    msgBox.textContent = "Baglanti bilgileri kaydedildi.";
    await runPing();
  });

  pingBtn.addEventListener("click", runPing);

  enabledChk.addEventListener("change", async () => {
    await sendMsg({ type: "SAVE_SETTINGS", settings: { enabled: enabledChk.checked } });
    msgBox.textContent = "Ayarlar kaydedildi.";
  });

  autoRunChk.addEventListener("change", async () => {
    await sendMsg({ type: "SAVE_SETTINGS", settings: { autoRun: autoRunChk.checked } });
    msgBox.textContent = "Otomatik calistirma ayari kaydedildi.";
  });

  autoInsertChk.addEventListener("change", async () => {
    await sendMsg({ type: "SAVE_SETTINGS", settings: { autoInsertResult: autoInsertChk.checked } });
    msgBox.textContent = "Ayarlar kaydedildi.";
  });

  autoSubmitChk.addEventListener("change", async () => {
    await sendMsg({ type: "SAVE_SETTINGS", settings: { autoSubmitResult: autoSubmitChk.checked } });
    msgBox.textContent = "Otomatik gonderme ayari kaydedildi.";
  });

  maxAutoStepsInput.addEventListener("change", async () => {
    const val = Math.max(1, Math.min(100, Number(maxAutoStepsInput.value) || 20));
    maxAutoStepsInput.value = String(val);
    await sendMsg({ type: "SAVE_SETTINGS", settings: { maxAutoSteps: val } });
    msgBox.textContent = "Maksimum adim sayisi kaydedildi.";
  });

  copyPromptBtn.addEventListener("click", async () => {
    const prompt = window.ArenaBridgeParser ? window.ArenaBridgeParser.SYSTEM_PROMPT : "";
    const ok = await copyText(prompt);
    msgBox.textContent = ok ? "Sistem promptu panoya kopyalandi." : "Kopyalama basarisiz.";
  });

  await runPing();
});
