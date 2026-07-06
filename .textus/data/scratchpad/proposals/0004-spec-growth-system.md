---
uid: 34b783cfd10f196d
---
## Proposal: Write spec file

Target: docs/superpowers/specs/2026-07-06-growth-doctor-checks.md

## Spec: Growth System — Detection + Alerts via Doctor Checks

### Problem

The loop calls growth "judgment-driven, not mechanically enforced."
Repeated patterns go undetected. Dead constraints accumulate. Sessions skip
nodes without visibility. The system does not improve itself.

This is Layer 3 — depends on Layer 1 (session node stack) and Layer 2 (graph
index) being built first. The checks below consume data from both.

### Design

Three new doctor checks that inspect session data and the graph:

#### 1. skipped_nodes

Inspects closed sessions. Flags any that closed without visiting constraint.repo
or evidence but authored new entries or wrote code.

```ruby
module Textus
  module Doctor
    module Check
      module SkippedNodes
        module_function

        def run(ctx)
          findings = []
          closed_sessions(ctx).each do |session|
            nodes = session.node_stack.map { |e| e.path.first }
            next if nodes.include?(:constraint) && nodes.include?(:evidence)

            findings << Finding.new(
              check: "skipped_nodes",
              severity: :warning,
              message: "Session #{session.id} skipped constraint.repo or evidence",
              detail: "Visited: #{nodes.join(', ')}",
            )
          end
          findings
        end
      end
    end
  end
end
```

#### 2. repeated_patterns

Inspects scratchpad entries across sessions. If the same topic appears 3+
times in scratchpad across 2+ sessions, suggests promotion to canon.

Heuristic: count scratchpad entries with similar key patterns. Not exact
dedup — looks for same prefix (e.g., scratchpad.sessions.*.notes.error-handling).

#### 3. dead_constraints

Queries the graph_edges table (Layer 2). Finds constraint entries (entries
under knowledge.loop.constraint.*) that have zero incoming refines or
depends_on edges. If nobody references it, it may be dead.

#### Output

Each check writes a doctor finding — same workflow as existing doctor:

```
Growth checks:
  ⚠ skipped_nodes: Session 2026-07-06-xxx skipped constraint.repo
  ⚠ repeated_patterns: "error-handling" in 3 sessions
  ℹ dead_constraints: constraint.repo.0008 has zero references
```

Findings are advisory. Human reviews and decides whether to act.

#### Files

lib/textus/doctor/check/skipped_nodes.rb — new
lib/textus/doctor/check/repeated_patterns.rb — new
lib/textus/doctor/check/dead_constraints.rb — new

~200 lines total. Reuses existing doctor framework.
