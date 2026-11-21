(function (root, factory) {
  if (typeof module === "object" && module.exports) {
    module.exports = factory();
  } else {
    root.ArenaBridgeParser = factory();
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  const SUPPORTED_TOOLS = [
    "run_command",
    "read_file",
    "write_file",
    "edit_file",
    "delete_path",
    "list_dir",
    "terminal_start",
    "terminal_write",
    "terminal_read",
    "terminal_list",
    "terminal_kill",
    "open_terminal_window",
  ];

  const SYSTEM_PROMPT = `Bilgisayarimda yerel arac (tool) ve terminal calistirmak istediginde, her arac cagrisi icin YALNIZCA asagidaki formatta bir \`arena-tool\` kod blogu uret. Her blok tarafimdan manuel olarak onaylandiktan sonra calistirilacak ve cikti sana \`arena-tool-result\` olarak geri gonderilecektir.

Kullanilabilir araclar:
1. run_command: Tek seferlik terminal komutu calistirir.
   args: { "command": "string", "cwd": "." (veya tam yol), "stdin": "opsiyonel", "timeout": 30 }
2. terminal_start: Kalici / interaktif terminal oturumu (PTY/shell) baslatir ve session_id doner.
   args: { "cwd": ".", "command": "opsiyonel baslangic komutu", "wait_ms": 450 }
3. terminal_write: Acik bir terminal oturumuna komut veya tus girdisi yazar.
   args: { "session_id": "term_...", "input": "komut", "enter": true, "ctrl": "c|d|z (opsiyonel)", "wait_ms": 500 }
4. terminal_read: Acik terminal oturumunun yeni ciktilarini okur.
   args: { "session_id": "term_...", "cursor": 0, "wait_ms": 300 }
5. terminal_list: Acik terminal oturumlarini listeler.
   args: {}
6. terminal_kill: Terminal oturumunu kapatir.
   args: { "session_id": "term_..." }
7. open_terminal_window: Masaustunde gercek bir terminal penceresi acar.
   args: { "command": "opsiyonel komut", "cwd": ".", "keep_open": true }
8. read_file: Dosya okur.
   args: { "path": "string", "offset": 1, "limit": 200 }
9. write_file: Dosya olusturur veya uzerine yazar.
   args: { "path": "string", "content": "string", "create_dirs": true }
10. edit_file: Mevcut dosyada metin degistirir.
    args: { "path": "string", "old_text": "string", "new_text": "string", "replace_all": false }
11. delete_path: Dosya veya klasor siler.
    args: { "path": "string", "recursive": false }
12. list_dir: Klasor icerigini listeler.
    args: { "path": ".", "include_hidden": false }

Ornek format (gercek cagrilarda "__example__" alanini ekleme):
\`\`\`arena-tool
{
  "__arena_tool__": true,
  "__example__": true,
  "id": "call_1",
  "tool": "terminal_start",
  "args": {
    "cwd": "~"
  }
}
\`\`\`

Kurallar:
- Yalnizca gecerli JSON yaz (yorum satiri veya trailing comma kullanma).
- Etkilesimli surecler (or. dev server, python REPL, ssh, ardisik cd komutlari) icin \`terminal_start\` + \`terminal_write\` + \`terminal_read\` kullan.
- Komut sonucunu uydurma; \`arena-tool-result\` yanitini bekle.
- Gorev tamamen bittiginde yeni \`arena-tool\` blogu yazmadan normal ozet yanit ver.`;

  /**
   * Parse raw text from a code block into a validated tool call object, or null if not a valid tool call.
   * @param {string} rawText
   * @param {object} [options]
   * @param {string} [options.languageHint] - e.g. 'arena-tool', 'json', etc.
   */
  function parseToolBlock(rawText, options) {
    if (!rawText || typeof rawText !== "string") return null;
    const trimmed = rawText.trim();
    if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) return null;

    const hint = ((options && options.languageHint) || "").toLowerCase().trim();
    if (hint === "arena-tool-result") return null;
    const isExplicitTag = hint === "arena-tool" || hint === "tool_call" || hint === "arena_tool";

    let parsed;
    try {
      parsed = JSON.parse(trimmed);
    } catch (_err) {
      return null;
    }

    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
    // Never treat tool results or prompt examples as tool calls
    if (parsed.ok !== undefined || parsed.result !== undefined || parsed.__example__ === true) return null;

    const hasMarker = parsed.__arena_tool__ === true || parsed.arena_tool === true;
    const matchesSupportedSchema =
      typeof parsed.tool === "string" &&
      SUPPORTED_TOOLS.includes(parsed.tool) &&
      parsed.args !== undefined &&
      parsed.args !== null &&
      typeof parsed.args === "object" &&
      !Array.isArray(parsed.args);

    if (!isExplicitTag && !hasMarker && !matchesSupportedSchema) {
      return null;
    }

    const tool = parsed.tool;
    if (typeof tool !== "string" || !SUPPORTED_TOOLS.includes(tool)) {
      return {
        valid: false,
        error: `Desteklenmeyen arac: "${String(tool || "")}". Desteklenenler: ${SUPPORTED_TOOLS.join(", ")}`,
        raw: trimmed,
      };
    }

    const args = parsed.args === undefined ? {} : parsed.args;
    if (!args || typeof args !== "object" || Array.isArray(args)) {
      return {
        valid: false,
        error: "'args' alani bir JSON nesnesi olmalidir.",
        raw: trimmed,
      };
    }

    if (tool === "run_command" && (typeof args.command !== "string" || !args.command.trim())) {
      return {
        valid: false,
        error: "run_command icin bos olmayan 'args.command' gerekli.",
        raw: trimmed,
      };
    }
    if (
      (tool === "read_file" || tool === "write_file" || tool === "edit_file" || tool === "delete_path") &&
      (typeof args.path !== "string" || !args.path.trim())
    ) {
      return {
        valid: false,
        error: `${tool} icin 'args.path' gerekli.`,
        raw: trimmed,
      };
    }
    if (tool === "write_file" && typeof args.content !== "string") {
      return {
        valid: false,
        error: "write_file icin 'args.content' (string) gerekli.",
        raw: trimmed,
      };
    }
    if (tool === "edit_file" && (typeof args.old_text !== "string" || !args.old_text || typeof args.new_text !== "string")) {
      return {
        valid: false,
        error: "edit_file icin 'args.old_text' ve 'args.new_text' gerekli.",
        raw: trimmed,
      };
    }
    if (
      (tool === "terminal_read" || tool === "terminal_kill") &&
      (typeof args.session_id !== "string" || !args.session_id.trim())
    ) {
      return {
        valid: false,
        error: `${tool} icin 'args.session_id' gerekli.`,
        raw: trimmed,
      };
    }
    if (tool === "terminal_write") {
      if (typeof args.session_id !== "string" || !args.session_id.trim()) {
        return { valid: false, error: "terminal_write icin 'args.session_id' gerekli.", raw: trimmed };
      }
      if (typeof args.input !== "string" && typeof args.ctrl !== "string") {
        return { valid: false, error: "terminal_write icin 'args.input' veya 'args.ctrl' gerekli.", raw: trimmed };
      }
    }

    const id =
      typeof parsed.id === "string" && parsed.id.trim()
        ? parsed.id.trim()
        : `call_${Math.random().toString(36).slice(2, 8)}`;

    return {
      valid: true,
      id,
      tool,
      args,
      raw: trimmed,
    };
  }

  /**
   * Format a native host response into a markdown block ready to send back to Arena.ai.
   */
  function formatToolResultForChat(call, response) {
    const payload = {
      id: (call && call.id) || (response && response.id) || null,
      tool: (call && call.tool) || (response && response.result && response.result.tool) || null,
      ok: Boolean(response && response.ok),
    };

    if (response && response.ok && response.result) {
      payload.result = response.result;
    } else {
      payload.error = (response && response.error) || "Bilinmeyen hata";
    }

    return "```arena-tool-result\n" + JSON.stringify(payload, null, 2) + "\n```";
  }

  return {
    SUPPORTED_TOOLS,
    SYSTEM_PROMPT,
    parseToolBlock,
    formatToolResultForChat,
  };
});
