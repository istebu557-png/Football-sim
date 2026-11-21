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
  const extIdBox = document.getElementById("extIdBox");
  const installCmd = document.getElementById("installCmd");
  const copyIdBtn = document.getElementById("copyIdBtn");
  const enabledChk = document.getElementById("enabledChk");
  const autoInsertChk = document.getElementById("autoInsertChk");
  const copyPromptBtn = document.getElementById("copyPromptBtn");
  const msgBox = document.getElementById("msgBox");

  async function runPing() {
    statusBadge.textContent = "Test ediliyor...";
    statusBadge.className = "pill pill-wait";
    const res = await sendMsg({ type: "NATIVE_PING" });
    if (res && res.ok && res.result) {
      const r = res.result;
      if (r.workspace_exists) {
        statusBadge.textContent = "Bagli";
        statusBadge.className = "pill pill-ok";
      } else {
        statusBadge.textContent = "Workspace Eksik";
        statusBadge.className = "pill pill-warn";
      }
      hostInfo.textContent = [
        `Host v${r.host_version} | Python ${r.python_version}`,
        `Workspace: ${r.workspace_root || "(ayarlanmamis)"}`,
        `Araclar: ${(r.allowed_tools || []).join(", ")}`,
        `Config: ${r.config_path}`,
      ].join("\n");
    } else {
      statusBadge.textContent = "Baglanti Yok";
      statusBadge.className = "pill pill-err";
      hostInfo.textContent = (res && res.error) || "Native host baglantisi basarisiz.";
    }
  }

  const info = await sendMsg({ type: "GET_EXTENSION_INFO" });
  if (info && info.ok) {
    extIdBox.textContent = info.extensionId;
    installCmd.textContent = `python3 install/install.py --extension-id ${info.extensionId} --workspace /proje/yolunuz`;
    enabledChk.checked = Boolean(info.settings && info.settings.enabled);
    autoInsertChk.checked = Boolean(info.settings && info.settings.autoInsertResult);
  }

  pingBtn.addEventListener("click", runPing);

  copyIdBtn.addEventListener("click", async () => {
    await navigator.clipboard.writeText(extIdBox.textContent.trim());
    msgBox.textContent = "Eklenti ID panoya kopyalandi.";
  });

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
