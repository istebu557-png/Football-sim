"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const Parser = require("../extension/tool-parser.js");

test("parses valid arena-tool block", () => {
  const res = Parser.parseToolBlock(
    JSON.stringify({
      id: "call_1",
      tool: "run_command",
      args: { command: "git status", cwd: "." },
    }),
    { languageHint: "arena-tool" }
  );
  assert.equal(res.valid, true);
  assert.equal(res.id, "call_1");
  assert.equal(res.tool, "run_command");
  assert.equal(res.args.command, "git status");
});

test("ignores plain json code block without explicit marker or tag", () => {
  const res = Parser.parseToolBlock(
    JSON.stringify({
      tool: "run_command",
      args: { command: "rm -rf /" },
    }),
    { languageHint: "json" }
  );
  assert.equal(res, null);
});

test("accepts json block when __arena_tool__ marker is true", () => {
  const res = Parser.parseToolBlock(
    JSON.stringify({
      __arena_tool__: true,
      tool: "read_file",
      args: { path: "README.md" },
    }),
    { languageHint: "json" }
  );
  assert.equal(res.valid, true);
  assert.equal(res.tool, "read_file");
});

test("returns validation error for missing required args", () => {
  const res = Parser.parseToolBlock(
    JSON.stringify({
      tool: "write_file",
      args: { path: "a.txt" },
    }),
    { languageHint: "arena-tool" }
  );
  assert.equal(res.valid, false);
  assert.match(res.error, /content/);
});

test("formats tool result back into arena-tool-result markdown block", () => {
  const formatted = Parser.formatToolResultForChat(
    { id: "call_9", tool: "run_command" },
    { ok: true, result: { tool: "run_command", exit_code: 0, stdout: "ok\n" } }
  );
  assert.match(formatted, /^```arena-tool-result\n/);
  assert.match(formatted, /"exit_code": 0/);
  assert.match(formatted, /\n```$/);
});
