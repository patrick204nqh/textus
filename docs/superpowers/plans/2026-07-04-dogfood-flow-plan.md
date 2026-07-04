# Dogfood Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the dogfood flow improvements — surface session verbs, remove proposals lane, refactor feedback node to criteria, restructure execution zone, update orientation.

**Architecture:** Changes span three layers: (1) Ruby library code (verb registry, handlers), (2) .textus/ store configuration (manifest, schemas, knowledge entries, workflows), (3) generated output (CLAUDE.md/AGENTS.md via drain).

**Tech Stack:** Ruby (textus gem), YAML (schemas, manifest), Markdown (knowledge entries), ERB (orientation template)

**Spec:** `docs/superpowers/specs/2026-07-04-dogfood-flow-design.md`

---

### Task 1: Surface session verbs

**Files:**
- Modify: `spec/conformance/boot/cli_verbs_spec.rb:7-8`

- [ ] **Step 1: Remove `session` from BOOT_GUARD_INTENTIONALLY_OMITTED**

```ruby
# Change line 7-8 from:
BOOT_GUARD_INTENTIONALLY_OMITTED =
  %w[session deps rdeps graph diff init mcp reject data watch workflow].freeze

# To:
BOOT_GUARD_INTENTIONALLY_OMITTED =
  %w[deps rdeps graph diff init mcp reject data watch workflow].freeze
```

- [ ] **Step 2: Run the conformance test to verify**

Run: `bundle exec rspec spec/conformance/boot/cli_verbs_spec.rb`
Expected: All tests pass (session verb now appears in catalog)

- [ ] **Step 3: Commit**

```bash
git add spec/conformance/boot/cli_verbs_spec.rb
git commit -m "feat: surface session_open/session_close in agent boot catalog"
```

---

### Task 2: Remove proposals lane from manifest and data directory

**Files:**
- Modify: `.textus/manifest.yaml`
- Delete: `.textus/data/proposals/.gitkeep`
- Delete: `.textus/data/proposals/` (empty directory)

- [ ] **Step 1: Remove proposals block from manifest**

```yaml
# Delete these lines from .textus/manifest.yaml:
proposals:
  - key: proposals.notes
```

- [ ] **Step 2: Remove proposals data directory**

Run: `rm -rf .textus/data/proposals/`

- [ ] **Step 3: Commit**

```bash
git add .textus/manifest.yaml
git rm -r .textus/data/proposals/
git commit -m "refactor: remove proposals lane (folded into scratchpad)"
```

---

### Task 3: Clean up scratchpad manifest (remove unused entries, add proposals)

**Files:**
- Modify: `.textus/manifest.yaml`

- [ ] **Step 1: Remove unused `notes` and `scripts`, add `proposals`**

```yaml
# Change scratchpad block from:
scratchpad:
  - key: scratchpad.notes
    tracked: false
  - key: scratchpad.sessions
    tracked: false
  - key: scratchpad.scripts
    tracked: false

# To:
scratchpad:
  - key: scratchpad.proposals
    tracked: false
  - key: scratchpad.sessions
    tracked: false
```

- [ ] **Step 2: Commit**

```bash
git add .textus/manifest.yaml
git commit -m "refactor: clean up scratchpad — replace notes/scripts with proposals"
```

---

### Task 4: Update orientation template (remove proposals lane references)

**Files:**
- Modify: `.textus/templates/docs/meta/orientation.erb`

- [ ] **Step 1: Update write authority section — remove proposals lane, add proposals sub-section**

```erb
# Change line 11 from:
<% Array(boot["lanes"]).each do |z| -%>    - **<%= z["name"] %>** (<%= Array(z["writers"]).join(" ") %>)<%= z["purpose"] ? " — #{z["purpose"]}" : "" %>
<% end -%>

# To (keep same — the lanes array no longer includes proposals since we removed the lane):
# (The lane is auto-generated from manifest, so removing the manifest entry handles this)
```

- [ ] **Step 2: Remove propose recipe from boot catalog section**

```erb
# Delete these lines (the propose recipe block):
<% if (r = boot.dig("agent_protocol", "recipes", "propose")) -%>   • **propose** — <%= r["purpose"] %>
<% Array(r["agent_steps"]).each do |s| -%>     agent: `<%= s %>`
<% end -%><% Array(r["human_steps"]).each do |s| -%>     human: `<%= s %>`
<% end -%><% end -%>
```

- [ ] **Step 3: Commit**

```bash
git add .textus/templates/docs/meta/orientation.erb
git commit -m "refactor: update orientation template — remove propose recipe"
```

---

### Task 5: Delete trigger feedback entry, move solid-audit to judgment.engineering

**Files:**
- Delete: `.textus/data/knowledge/loop/feedback/0002-session-lifecycle.md`
- Move: `.textus/data/knowledge/loop/feedback/0001-solid-audit.md` → `.textus/data/knowledge/loop/judgment/engineering/0015-solid-audit.md`

- [ ] **Step 1: Delete the trigger feedback entry**

Run: `rm .textus/data/knowledge/loop/feedback/0002-session-lifecycle.md`

- [ ] **Step 2: Move solid-audit to judgment.engineering**

Run: `mv .textus/data/knowledge/loop/feedback/0001-solid-audit.md .textus/data/knowledge/loop/judgment/engineering/0015-solid-audit.md`

- [ ] **Step 3: Commit**

```bash
git rm .textus/data/knowledge/loop/feedback/0002-session-lifecycle.md
git mv .textus/data/knowledge/loop/feedback/0001-solid-audit.md .textus/data/knowledge/loop/judgment/engineering/0015-solid-audit.md
git commit -m "refactor: feedback node becomes criteria — move solid-audit to judgment.engineering"
```

---

### Task 6: Write feedback criteria entries

**Files:**
- Create: `.textus/data/knowledge/loop/feedback/0001-protocol-gap.md`
- Create: `.textus/data/knowledge/loop/feedback/0002-repetitive-task.md`
- Create: `.textus/data/knowledge/loop/feedback/0003-intent-drift.md`

- [ ] **Step 1: Create protocol-gap criteria entry**

```markdown
---
node: constraint.protocol
confidence: high
signal: behavioral_gap
summary: When the agent discovers a behavior the wire protocol doesn't cover, propose to constraint.protocol with a concrete ADR candidate.
---

If during a session the agent encounters a case where the textus/4 protocol
(SPEC.md) does not specify behavior for a situation that actually occurs,
this is a protocol gap. The agent should:

1. Document the gap with enough context to reproduce
2. Propose a new constraint.protocol entry addressing it
3. Reference the session_id where the gap was discovered

Threshold: any unaddressed gap discovered during normal operation.
```

- [ ] **Step 2: Create repetitive-task criteria entry**

```markdown
---
node: execution
confidence: medium
signal: repetition
summary: When the agent performs the same manual task 3+ times across sessions, propose a new execution entry codifying it.
---

If the same multi-step procedure is performed manually across three or more
separate sessions, the agent should propose a runbook, checklist, or procedure
entry under knowledge.loop.execution.

Threshold: 3 occurrences of the same or substantially similar task flow.
```

- [ ] **Step 3: Create intent-drift criteria entry**

```markdown
---
node: intent
confidence: high
signal: drift
summary: When observed behavior or outcomes consistently diverge from stated intent entries, propose intent amendment.
---

If across multiple sessions the agent observes that the project's actual
behavior, priorities, or trade-offs no longer match the statements in
knowledge.loop.intent.* (north-star, identity, strength-model, pitch),
this is intent drift. The agent should:

1. Summarize the divergence with specific examples
2. Propose an updated intent entry

Threshold: drift observed across 2+ sessions on the same dimension.
```

- [ ] **Step 4: Commit**

```bash
git add .textus/data/knowledge/loop/feedback/
git commit -m "feat: add feedback criteria entries — protocol-gap, repetitive-task, intent-drift"
```

---

### Task 7: Create execution schema files

**Files:**
- Create: `.textus/schemas/execution/runbook.yaml`
- Create: `.textus/schemas/execution/checklist.yaml`
- Create: `.textus/schemas/execution/procedure.yaml`
- Modify: `.textus/manifest.yaml`

- [ ] **Step 1: Create schemas/execution/ directory**

Run: `mkdir -p .textus/schemas/execution`

- [ ] **Step 2: Create runbook schema**

```yaml
# .textus/schemas/execution/runbook.yaml
name: execution/runbook
fields:
  name:
    type: string
    required: true
    maintained_by: human
  description:
    type: string
    required: true
    maintained_by: human
  steps:
    type: array
    items:
      type: string
    maintained_by: human
```

- [ ] **Step 3: Create checklist schema**

```yaml
# .textus/schemas/execution/checklist.yaml
name: execution/checklist
fields:
  name:
    type: string
    required: true
    maintained_by: human
  description:
    type: string
    required: true
    maintained_by: human
  items:
    type: array
    items:
      type: object
      fields:
        check:
          type: boolean
          maintained_by: human
        description:
          type: string
          maintained_by: human
    maintained_by: human
```

- [ ] **Step 4: Create procedure schema**

```yaml
# .textus/schemas/execution/procedure.yaml
name: execution/procedure
fields:
  name:
    type: string
    required: true
    maintained_by: human
  description:
    type: string
    required: true
    maintained_by: human
  inputs:
    type: array
    items:
      type: string
    maintained_by: human
  outputs:
    type: array
    items:
      type: string
    maintained_by: human
  steps:
    type: array
    items:
      type: string
    maintained_by: human
```

- [ ] **Step 5: Update manifest — replace flat execution with sub-families**

```yaml
# Change in .textus/manifest.yaml:
# Remove:
    - key: knowledge.loop.execution
      naming: sequential
      schema: runbook

# Add:
    - key: knowledge.loop.execution.runbook
      naming: sequential
      schema: execution/runbook
    - key: knowledge.loop.execution.checklist
      naming: sequential
      schema: execution/checklist
    - key: knowledge.loop.execution.procedure
      naming: sequential
      schema: execution/procedure
```

- [ ] **Step 6: Commit**

```bash
git add .textus/schemas/execution/ .textus/manifest.yaml
git commit -m "feat: add execution schemas — runbook, checklist, procedure"
```

---

### Task 8: Move existing runbooks to runbook/ subdirectory

**Files:**
- Move: `.textus/data/knowledge/loop/execution/0001-release.md` → `.textus/data/knowledge/loop/execution/runbook/0001-release.md`
- Move: `.textus/data/knowledge/loop/execution/0002-adr.md` → `.textus/data/knowledge/loop/execution/runbook/0002-adr.md`
- Move: `.textus/data/knowledge/loop/execution/0003-quickstart.md` → `.textus/data/knowledge/loop/execution/runbook/0003-quickstart.md`

- [ ] **Step 1: Create runbook/ directory**

Run: `mkdir -p .textus/data/knowledge/loop/execution/runbook`

- [ ] **Step 2: Move all 3 runbook files**

```bash
git mv .textus/data/knowledge/loop/execution/0001-release.md .textus/data/knowledge/loop/execution/runbook/0001-release.md
git mv .textus/data/knowledge/loop/execution/0002-adr.md .textus/data/knowledge/loop/execution/runbook/0002-adr.md
git mv .textus/data/knowledge/loop/execution/0003-quickstart.md .textus/data/knowledge/loop/execution/runbook/0003-quickstart.md
```

- [ ] **Step 3: Commit**

```bash
git commit -m "refactor: move execution entries to runbook/ subdirectory"
```

---

### Task 9: Create procedure entries (doctor, session, deploy)

**Files:**
- Create: `.textus/data/knowledge/loop/execution/procedure/0001-doctor.md`
- Create: `.textus/data/knowledge/loop/execution/procedure/0002-session.md`
- Create: `.textus/data/knowledge/loop/execution/procedure/0003-deploy.md`

- [ ] **Step 1: Create procedure/ directory**

Run: `mkdir -p .textus/data/knowledge/loop/execution/procedure`

- [ ] **Step 2: Create doctor procedure entry**

```markdown
---
name: doctor
description: Read and act on doctor workflow reports to keep the store healthy.
---
## doctor

Doctor workflows run automatically on drain and publish to `artifacts.doctor.*`.

**Reading reports:**

```sh
textus get artifacts.doctor.manifest-files
```

Each report is a JSON file with:
- `ok` — boolean, false if issues found
- `issues` — array of `{code, severity, subject, message, fix}`
- `count` — number of issues

**Common fixes:**
- `manifest.missing_file` — create the entry with `textus put <key> --stdin --as=human`
- `sentinel.drift` — re-run `textus drain --as=automation`
- `schema_violation` — update the entry's front matter to match schema

**All doctor keys:**

```sh
textus list --lane=artifacts --prefix=artifacts.doctor
```
```

- [ ] **Step 3: Create session procedure entry**

```markdown
---
name: session
description: Begin and end agent sessions, review feedback, propose changes to canon.
---
## session

**Begin a session:**

```sh
textus session_open --as=agent
```
Returns `{session_id, status: "active", workspace}`. The workspace has `notes/`, `scripts/`, `output/` subdirectories.

**Work during session:**

Use the workspace for temporary files, notes, and scripts. Write durable notes to `scratchpad.sessions.<id>.notes.*`.

**End a session:**

```sh
textus session_close <id> --as=agent
```

This seals the session and writes a feedback entry to `scratchpad.sessions.<id>.feedback` with duration, timestamps, and session metadata.

**Review feedback:**

```sh
textus get scratchpad.sessions.<id>.feedback
```

Check the feedback against criteria in `knowledge.loop.feedback.*` to decide if anything warrants proposing to canon.

**Propose upstream changes:**

```sh
textus propose scratchpad.proposals.<topic> \
  --target=knowledge.<node>.<path> \
  --body="..." --as=agent
```

Human reviews and accepts:

```sh
textus accept scratchpad.proposals.<topic> --as=human
```
```

- [ ] **Step 4: Create deploy procedure entry**

```markdown
---
name: deploy
description: Cut a textus release — bump version, update lockfile, tag, publish.
---
## deploy

**Prerequisites:** All tests passing (`bundle exec rspec`), clean lint (`bundle exec rubocop`).

**Steps:**

1. Update version in `lib/textus/version.rb` (semver)
2. Run `bundle install` to update `Gemfile.lock`
3. Commit with message format: `release: v<version>`
4. Tag: `git tag v<version>`
5. Push: `git push && git push --tags`
6. Build gem: `gem build textus.gemspec`
7. Publish: `gem push textus-<version>.gem`

**Verify:** `textus --version` should report the new version.
```

- [ ] **Step 5: Commit**

```bash
git add .textus/data/knowledge/loop/execution/procedure/
git commit -m "feat: add procedure entries — doctor, session, deploy"
```

---

### Task 10: Update boot.rb read logic for nested execution structure

**Files:**
- Modify: `.textus/workflows/config/boot.rb`

- [ ] **Step 1: Verify the existing read_family lambda handles sub-families**

The current boot.rb uses:
```ruby
read_family = lambda do |prefix|
  manifest.resolver.enumerate(prefix: prefix, include_keyless: true)
          .reject { |row| row[:key] == prefix }
          .sort_by { |row| row[:key] }
          .filter_map { |row| ctx.read(row[:key]) }
end
```

This enumerates all entries under a prefix. If we call `read_family.call("knowledge.loop.execution")`, it will enumerate ALL entries under all sub-families (runbook.*, checklist.*, procedure.*). So no code change needed — the existing lambda already handles nested structures via prefix enumeration.

No code change required.

---

### Task 11: Update loop_shape.rb to validate execution sub-families

**Files:**
- Modify: `.textus/workflows/config/loop_shape.rb`

- [ ] **Step 1: Add shape validations for execution sub-families**

```ruby
# Add after existing shape lines:
shape "knowledge.loop.execution.runbook.*", naming: node_pattern
shape "knowledge.loop.execution.checklist.*", naming: node_pattern
shape "knowledge.loop.execution.procedure.*", naming: node_pattern
```

- [ ] **Step 2: Commit**

```bash
git add .textus/workflows/config/loop_shape.rb
git commit -m "feat: add shape validation for execution sub-families"
```

---

### Task 12: Final drain and verification

**Files:**
- Regenerate: `CLAUDE.md`, `AGENTS.md` (via `textus drain`)

- [ ] **Step 1: Run drain to regenerate all artifacts**

```bash
echo '{"_meta":{"node":"feedback","confidence":"high","signal":"regen","summary":"Regenerate after dogfood flow changes"},"body":"ok"}' | bundle exec exe/textus put knowledge.loop.feedback.0001-protocol-gap --as=human --stdin
bundle exec exe/textus drain --as=automation
```

- [ ] **Step 2: Verify CLAUDE.md shows correct content**

```bash
head -40 CLAUDE.md
# Should show:
# - `# textus` project name
# - Session Lifecycle section
# - Runbooks grouped by type
# - No propose recipe
```

- [ ] **Step 3: Run test suite**

```bash
bundle exec rspec
# Expected: 0 failures
```

- [ ] **Step 4: Commit regenerated files**

```bash
git add CLAUDE.md AGENTS.md .textus/data/artifacts/
git commit -m "chore: regenerate artifacts after dogfood flow changes"
```
