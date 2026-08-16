---
name: serena
description: Token-efficient Serena MCP bootstrap and workflow for structured app development
allowed-tools: Read, Glob, Grep, Edit, Write, Bash, TodoWrite, ToolSearch, mcp__serena__initial_instructions, mcp__serena__onboarding, mcp__serena__list_memories, mcp__serena__read_memory, mcp__serena__write_memory, mcp__serena__edit_memory, mcp__serena__rename_memory, mcp__serena__delete_memory, mcp__serena__get_symbols_overview, mcp__serena__find_symbol, mcp__serena__find_declaration, mcp__serena__find_implementations, mcp__serena__find_referencing_symbols, mcp__serena__insert_after_symbol, mcp__serena__insert_before_symbol, mcp__serena__replace_symbol_body, mcp__serena__replace_content, mcp__serena__replace_in_files, mcp__serena__rename_symbol, mcp__serena__safe_delete_symbol, mcp__serena__get_diagnostics_for_file, mcp__context7__resolve-library-id, mcp__context7__query-docs
---

# Serena Workflow

## Bootstrap (run once per session, in order)

1. If Serena's tools are deferred, load **all** of them now: `ToolSearch` with query `"+serena"` (max_results 25). Never call a tool whose schema you have not loaded.
2. If you have not yet read the Serena Instructions Manual in this session, call `mcp__serena__initial_instructions` and follow it — it overrides any stale habits.
3. If the manual reports onboarding has not been performed, call `mcp__serena__onboarding` before task work.

## Reading Code (symbol-first)

* Discovery: `Glob` (names) / `Grep` (content) are allowed for discovery only. All follow-up reads go through Serena.
* `get_symbols_overview` → `find_symbol` (`include_body=false`, `depth=1`) → read only the bodies you need (`include_body=true`).
* `find_declaration` / `find_implementations` for LSP-backed jump-to-definition and implementation search; `find_referencing_symbols` for impact analysis.
* Do not `Read` whole code files for discovery. Once a full file has been read, stop re-analysing it with symbolic tools.

## Non-Code Files

Config / docs / YAML / JSON / Markdown / changelog等はSerenaのシンボル解析対象外。
標準の `Read` / `Edit` / `Write` を直接使う（`get_symbols_overview` や `replace_content` 等の
Serenaツールを通さない）。

## Editing Code

* Whole-symbol changes: `replace_symbol_body`, `insert_after_symbol`, `insert_before_symbol`.
* Few-line changes inside a larger symbol: `replace_content` (regex mode with tight `.*?` wildcards; ambiguous matches error safely).
* Same edit across many files: `replace_in_files` (use `dry_run` first, then apply all or a subset by occurrence id).
* Renames and deletions of existing symbols: `rename_symbol` / `safe_delete_symbol` — reference-aware and atomic. On success, trust the result; do not re-read files or re-run builds just to confirm propagation.
* Editing symbols you read via Serena MUST use Serena's editing tools, not built-in `Edit` — except the trivial-edit exception below.

## When Serena Is Mandatory vs Optional

* **Trivial exception**: a single-file, few-line fix with no rename and no cross-file impact (typo, literal value, one-line condition) — native `Edit` is fine, don't round-trip through Serena for it.
* **Serena mandatory**: anything touching a symbol's identity or footprint across the codebase — rename/move/delete, cross-file refactors, architecture changes, dependency-impact investigation (`find_referencing_symbols`). This is where Serena's reference-safety and atomicity have no native equivalent; skipping it here is the failure mode below, not a valid efficiency call.
* When unsure which bucket a change falls in, default to Serena — the trivial exception is narrow on purpose.

## Anti-Drift (do not bypass Serena with native tools)

Known failure mode: under time pressure a model reverts to `Grep`→`Read`→`Edit` for renames/moves/cross-file refactors instead of Serena's atomic tools — this silently discards the reference-safety and token savings the workflow exists for. Treat this as a rule violation, not a style choice:

* Rename/move/delete an existing symbol → `rename_symbol` / `safe_delete_symbol` is MANDATORY. Never hand-edit each call site with `Edit`.
* Same change repeated across files → `replace_in_files` is MANDATORY over a manual per-file loop.
* If you catch yourself about to `Grep` for call sites *in order to edit them* (not just to discover scope), stop and use the Serena equivalent instead.
* Do not use the trivial-edit exception above to rationalize skipping this on anything with cross-file or reference impact.
* This drift is also enforced outside the prompt: a `PreToolUse` hook (`serena-hooks remind`) tracks consecutive `Grep`/`Read` calls and denies the 4th in a row with a reminder to switch to symbolic tools (counter resets on any Serena tool call or after ~33min idle). If a call gets denied for this reason, that is the enforcement working as intended — switch to the Serena equivalent, don't retry the same native call.

## Disambiguating Symbols (name paths)

`find_symbol` / `rename_symbol` / `safe_delete_symbol` take a `name_path`, not a bare method name. Use `ClassName/methodName` (not just `methodName`) whenever the codebase has overloads or same-named methods on different classes — a bare name risks silently matching the wrong symbol. For languages with overloading (e.g. Java), the name_path may need to include the method signature to uniquely identify it.

## Quality Gate

Before declaring an edit task done, run `get_diagnostics_for_file` on every modified code file and resolve new errors.

## Cost Discipline

* Batch all independent tool calls in a single turn — Serena applies them safely in order; round-trips are the main cost driver.
* Acquire information step by step; never read or generate content the task does not need.

## Memory Tools

* `list_memories` / `read_memory` to load; `write_memory` only for brand-new files.
* Updates to existing memories use `edit_memory` (in-place merge), moves/promotions use `rename_memory`, removals use `delete_memory`. Never rewrite a whole memory when a targeted edit suffices.
* Cross-references between memories: write them as `` `mem:name` `` (backtick, `mem:` prefix, memory name — no `.md`). `rename_memory` rewrites every `mem:` reference to the old name automatically; a bare mention without the prefix does not get updated on rename, so always use the prefix when pointing at another memory.

## Large / Unindexed Projects

If symbol search on a large codebase is slow or times out on first use (no `.serena/cache` yet), run `serena project index` (via `Bash`) once before task work — it pre-populates the LSP symbol cache so later `find_symbol`/`get_symbols_overview` calls are fast. Not needed on repeat sessions once the cache exists.

## Research (Context7)

For library/framework/API questions: `resolve-library-id` → `query-docs`. Prefer this over answering from training data.
