"use strict";

function sendMsg(msg) {
  return new Promise((resolve) => {
    chrome.runtime.sendMessage(msg, (res) => {
      if (chrome.runtime.lastError) {
        resolve({ ok: false, error: chrome.runtime.lastError.message });
        return;
      }
      resolve(res || { ok: false, error: "Yanit alinamadi" });
    });
  });
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
  const autoInsertChk = document.getElementById("autoInsertChk");
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
    autoInsertChk.checked = Boolean(info.settings.autoInsertResult);
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

  autoInsertChk.addEventListener("change", async () => {
    await sendMsg({ type: "SAVE_SETTINGS", settings: { autoInsertResult: autoInsertChk.checked } });
    msgBox.textContent = "Ayarlar kaydedildi.";
  });

  copyPromptBtn.addEventListener("click", async () => {
    const prompt = window.ArenaBridgeParser ? window.ArenaBridgeParser.SYSTEM_PROMPT : "";
    await navigator.clipboard.writeText(prompt);
    msgBox.textContent = "Sistem promptu panoya kopyalandi.";
  });

  await runPing();
});
