"use strict";

const DEFAULT_SERVER_URL = "http://127.0.0.1:38450";
const DEFAULT_SETTINGS = {
  enabled: true,
  autoInsertResult: false,
  serverUrl: DEFAULT_SERVER_URL,
  apiToken: "",
};

function normalizeServerUrl(rawUrl) {
  const input = String(rawUrl || DEFAULT_SERVER_URL).trim();
  let parsed;
  try {
    parsed = new URL(input);
  } catch (_err) {
    throw new Error("Gecersiz sunucu adresi. Ornek: http://127.0.0.1:38450");
  }
  if (parsed.protocol !== "http:") {
    throw new Error("Sunucu adresi http:// ile baslamalidir.");
  }
  if (parsed.hostname !== "127.0.0.1" && parsed.hostname !== "localhost") {
    throw new Error("Guvenlik geregi yalnizca 127.0.0.1 veya localhost adresine baglanilabilir.");
  }
  return `${parsed.protocol}//${parsed.host}`;
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
  if (patch && typeof patch.serverUrl === "string") {
    next.serverUrl = normalizeServerUrl(patch.serverUrl);
  }
  if (patch && typeof patch.apiToken === "string") {
    next.apiToken = patch.apiToken.trim();
  }
  return new Promise((resolve) => {
    chrome.storage.local.set(next, () => resolve(next));
  });
}

async function callLocalServer(endpoint, method, bodyObj, reqId) {
  const settings = await getSettings();
  let baseUrl;
  try {
    baseUrl = normalizeServerUrl(settings.serverUrl);
  } catch (err) {
    return { id: reqId || null, ok: false, error: err.message };
  }

  const token = (settings.apiToken || "").trim();
  if (!token) {
    return {
      id: reqId || null,
      ok: false,
      authMissing: true,
      error: "API Token girilmemis. Eklenti simgesine tiklayip sunucu terminalindeki Token'i yapistirin.",
    };
  }

  const opts = {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
    },
  };
  if (method !== "GET" && bodyObj !== undefined) {
    opts.headers["Content-Type"] = "application/json";
    opts.body = JSON.stringify(bodyObj);
  }

  try {
    const resp = await fetch(`${baseUrl}${endpoint}`, opts);
    let data = null;
    try {
      data = await resp.json();
    } catch (_e) {
      data = null;
    }

    if (!resp.ok) {
      return {
        id: reqId || null,
        ok: false,
        httpStatus: resp.status,
        error: (data && data.error) || `Sunucu hatasi (HTTP ${resp.status})`,
      };
    }
    return data || { id: reqId || null, ok: false, error: "Sunucu bos yanit dondu." };
  } catch (_err) {
    return {
      id: reqId || null,
      ok: false,
      unreachable: true,
      error:
        `Yerel sunucuya (${baseUrl}) baglanilamadi. ` +
        "Bilgisayarinizda start.sh / start.bat (veya server/local_server.py) calistigindan emin olun.",
    };
  }
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
          transport: "localhost_http",
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
        try {
          const settings = await saveSettings(message.settings);
          sendResponse({ ok: true, settings });
        } catch (err) {
          sendResponse({ ok: false, error: err && err.message ? err.message : String(err) });
        }
        break;
      }
      case "NATIVE_PING":
      case "SERVER_PING": {
        const res = await callLocalServer("/api/ping", "GET", undefined, `ping_${Date.now()}`);
        sendResponse(res);
        break;
      }
      case "RUN_TOOL": {
        const call = message.call || {};
        if (!call.tool || typeof call.tool !== "string") {
          sendResponse({ ok: false, error: "Gecersiz arac cagrisi." });
          return;
        }
        const id = call.id || `call_${Date.now()}`;
        const res = await callLocalServer(
          "/api/tool",
          "POST",
          { id, tool: call.tool, args: call.args || {} },
          id
        );
        sendResponse(res);
        break;
      }
      default:
        sendResponse({ ok: false, error: `Bilinmeyen mesaj tipi: ${message.type}` });
    }
  })();

  return true;
});
