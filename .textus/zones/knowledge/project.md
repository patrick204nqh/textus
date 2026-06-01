---
name: textus
description: A coordination space for humans, AI, and automation — durable, multi-writer repo memory that survives the session, the model, and the vendor.
repo: https://github.com/patrick204nqh/textus
---

textus is a Ruby gem (≥ 3.3) implementing the `textus/3` wire protocol: a
durable, multi-writer context store where three actors — humans, agents, and
automation — each write into their own zone, and low-trust input climbs to
canon only by passing a guarded transition (an agent's `propose` needs a human
`accept`). Lanes are enforced at the protocol level, not by convention.

The normative contract is `SPEC.md`. The friendly guides live in `docs/`.
Every load-bearing decision is an ADR under
`docs/architecture/decisions/`; `repo-conventions.md` indexes how the repo
itself is shaped.

This store is textus dogfooding itself (ADR 0041): the repo's own development
context lives in `.textus/`, and the Claude Code / MCP wiring in `.mcp.json`
drives the **working tree** (`bundle exec exe/textus`), not the released gem —
so the agent that helps develop textus runs the code under review.

This file is the slow-changing root identity entry. Only humans can write to
the `knowledge` (canon) zone. Edit this file, then run `textus build` to
rebuild the projected `CLAUDE.md` and `AGENTS.md` at the repo root.
