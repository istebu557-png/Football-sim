(function (root, factory) {
  if (typeof module === "object" && module.exports) {
    module.exports = factory();
  } else {
    root.ArenaBridgeParser = factory();
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  const SUPPORTED_TOOLS = ["run_command", "read_file", "write_file", "list_dir"];

  const SYSTEM_PROMPT = `Bilgisayarimda yerel arac (tool) ve terminal calistirmak istediginde, her arac cagrisi icin YALNIZCA asagidaki formatta bir \`arena-tool\` kod blogu uret. Birden fazla arac gerekirse adim adim ilerle veya ayri bloklar yaz. Her blok tarafimdan manuel olarak onaylandiktan sonra calistirilacak ve cikti sana \`arena-tool-result\` olarak geri gonderilecektir.

Kullanilabilir araclar:
1. run_command: Terminal komutu calistirir.
   args: { "command": "string", "cwd": "." (opsiyonel), "timeout": 30 (opsiyonel) }
2. read_file: Dosya okur.
   args: { "path": "string", "offset": 1 (opsiyonel), "limit": 200 (opsiyonel) }
3. write_file: Dosya olusturur/yazar.
   args: { "path": "string", "content": "string", "create_dirs": true }
4. list_dir: Klasor icerigini listeler.
   args: { "path": "." (opsiyonel), "include_hidden": false }

Ornek format:
\`\`\`arena-tool
{
  "id": "call_1",
  "tool": "run_command",
  "args": {
    "command": "git status",
    "cwd": "."
  }
}
\`\`\`

Kurallar:
- Yalnizca gecerli JSON yaz (yorum satiri veya trailing comma kullanma).
- Komut sonucunu uydurma; sonucu kullanicidan bekle.`;

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
    const isExplicitTag = hint === "arena-tool" || hint === "tool_call" || hint === "arena_tool";

    let parsed;
    try {
      parsed = JSON.parse(trimmed);
    } catch (_err) {
      return null;
    }

    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;

    // Require explicit language tag OR explicit marker property so ordinary JSON blocks are never misread as tool calls
    const hasMarker = parsed.__arena_tool__ === true || parsed.arena_tool === true;
    if (!isExplicitTag && !hasMarker) {
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

    // Per-tool required arg validation
    if (tool === "run_command" && (typeof args.command !== "string" || !args.command.trim())) {
      return {
        valid: false,
        error: "run_command icin bos olmayan 'args.command' gerekli.",
        raw: trimmed,
      };
    }
    if ((tool === "read_file" || tool === "write_file") && (typeof args.path !== "string" || !args.path.trim())) {
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
