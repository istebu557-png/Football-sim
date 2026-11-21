"use strict";

const NATIVE_HOST_NAME = "com.arena.local_bridge";
const DEFAULT_SETTINGS = {
  enabled: true,
  autoInsertResult: false,
};

function sendNative(payload) {
  return new Promise((resolve) => {
    try {
      chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, payload, (response) => {
        if (chrome.runtime.lastError) {
          const msg = chrome.runtime.lastError.message || "Native host baglantisi basarisiz.";
          resolve({
            id: payload.id || null,
            ok: false,
            error:
              `Native Messaging hatasi: ${msg}. ` +
              `Kurulum yapilmadiysa install.py betigini eklenti ID (${chrome.runtime.id}) ile calistirin.`,
          });
          return;
        }
        resolve(response || { id: payload.id || null, ok: false, error: "Native host bos yanit dondu." });
      });
    } catch (err) {
      resolve({
        id: payload.id || null,
        ok: false,
        error: `Native Messaging istisnasi: ${err && err.message ? err.message : String(err)}`,
      });
    }
  });
}

async function getSettings() {
  return new Promise((resolve) => {
    chrome.storage.local.get(DEFAULT_SETTINGS, (items) => {
      resolve({ ...DEFAULT_SETTINGS, ...(items || {}) });
    });
  });
}

async function saveSettings(patch) {
  const current = await getSettings();
  const next = { ...current, ...(patch || {}) };
  return new Promise((resolve) => {
    chrome.storage.local.set(next, () => resolve(next));
  });
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (!message || typeof message.type !== "string") {
    return false;
  }

  (async () => {
    switch (message.type) {
      case "GET_EXTENSION_INFO": {
        const settings = await getSettings();
        sendResponse({
          ok: true,
          extensionId: chrome.runtime.id,
          hostName: NATIVE_HOST_NAME,
          settings,
        });
        break;
      }
      case "GET_SETTINGS": {
        const settings = await getSettings();
        sendResponse({ ok: true, settings });
        break;
      }
      case "SAVE_SETTINGS": {
        const settings = await saveSettings(message.settings);
        sendResponse({ ok: true, settings });
        break;
      }
      case "NATIVE_PING": {
        const res = await sendNative({
          id: `ping_${Date.now()}`,
          tool: "ping",
          args: {},
        });
        sendResponse(res);
        break;
      }
      case "RUN_TOOL": {
        const call = message.call || {};
        if (!call.tool || typeof call.tool !== "string") {
          sendResponse({ ok: false, error: "Gecersiz arac cagrisi." });
          return;
        }
        const res = await sendNative({
          id: call.id || `call_${Date.now()}`,
          tool: call.tool,
          args: call.args || {},
        });
        sendResponse(res);
        break;
      }
      default:
        sendResponse({ ok: false, error: `Bilinmeyen mesaj tipi: ${message.type}` });
    }
  })();

  return true; // keep message channel open for async response
});
