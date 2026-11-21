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

test("parses terminal_start and terminal_write blocks", () => {
  const start = Parser.parseToolBlock(
    JSON.stringify({
      id: "t1",
      tool: "terminal_start",
      args: { cwd: "~" },
    }),
    { languageHint: "arena-tool" }
  );
  assert.equal(start.valid, true);
  assert.equal(start.tool, "terminal_start");

  const write = Parser.parseToolBlock(
    JSON.stringify({
      id: "t2",
      tool: "terminal_write",
      args: { session_id: "term_abc123", input: "ls -la", enter: true },
    }),
    { languageHint: "arena-tool" }
  );
  assert.equal(write.valid, true);
  assert.equal(write.args.session_id, "term_abc123");

  const ctrl = Parser.parseToolBlock(
    JSON.stringify({
      id: "t3",
      tool: "terminal_write",
      args: { session_id: "term_abc123", ctrl: "c" },
    }),
    { languageHint: "arena-tool" }
  );
  assert.equal(ctrl.valid, true);
});

test("ignores unrelated plain json code blocks", () => {
  const res1 = Parser.parseToolBlock(
    JSON.stringify({
      name: "example",
      tool: "unrelated_tool",
      data: [1, 2, 3],
    }),
    { languageHint: "json" }
  );
  assert.equal(res1, null);

  const res2 = Parser.parseToolBlock(
    JSON.stringify({
      tool: "hammer",
      price: 10,
    }),
    { languageHint: "json" }
  );
  assert.equal(res2, null);
});

test("accepts json block matching supported tool schema even if tag was stripped", () => {
  const res = Parser.parseToolBlock(
    JSON.stringify({
      tool: "run_command",
      args: { command: "pwd" },
    }),
    { languageHint: "" }
  );
  assert.equal(res.valid, true);
  assert.equal(res.tool, "run_command");
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

  const badTerm = Parser.parseToolBlock(
    JSON.stringify({
      tool: "terminal_write",
      args: { session_id: "term_1" },
    }),
    { languageHint: "arena-tool" }
  );
  assert.equal(badTerm.valid, false);
  assert.match(badTerm.error, /input|ctrl/);
});

test("formats tool result back into arena-tool-result markdown block", () => {
  const formatted = Parser.formatToolResultForChat(
    { id: "call_9", tool: "run_command" },
    { ok: true, result: { tool: "run_command", exit_code: 0, stdout: "ok\n" } }
  );
  assert.match(formatted, /^```arena-tool-result\n/);
  assert.match(formatted, /"exit_code": 0/);
  assert.match(formatted, /\n```$/);

  const innerJson = formatted.replace(/^```arena-tool-result\n/, "").replace(/\n```$/, "");
  assert.equal(Parser.parseToolBlock(innerJson, { languageHint: "arena-tool-result" }), null);
  assert.equal(Parser.parseToolBlock(innerJson, { languageHint: "json" }), null);
});

test("ignores __example__ blocks from SYSTEM_PROMPT", () => {
  const match = Parser.SYSTEM_PROMPT.match(/```arena-tool\n([\s\S]*?)\n```/);
  assert.ok(match);
  assert.equal(Parser.parseToolBlock(match[1], { languageHint: "arena-tool" }), null);
});
