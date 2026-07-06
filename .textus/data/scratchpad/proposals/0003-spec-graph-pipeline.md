---
uid: 99767e0576ecad61
---
## Proposal: Write spec file

Target: docs/superpowers/specs/2026-07-06-graph-compose-pipeline.md

## Spec: Atomic Canon + Graph + Composed Docs

### Problem

Canon entries are flat files with no relationship structure. Published docs are
hand-written or manually generated — no automated pipeline from atoms to docs.
There is no way to query "what depends on X" or "what refines Y."

ADR-0120 proposed atomic canon + composed artifacts but was never implemented.
ADR-0081 made docs canon published out but without a template/graph layer.

### Design

#### 1. Link syntax

Entry bodies can contain typed, native links as HTML comments:

```markdown
<!-- textus-link: refines knowledge.loop.evidence.0120 -->
<!-- textus-link: depends_on knowledge.loop.constraint.protocol.0014 -->
```

The <!-- textus-link: --> prefix is the marker. Format: TYPE KEY.
v1 types: refines, depends_on.

#### 2. Graph index

A SQLite `graph_edges` table maintained alongside the existing store:

```sql
CREATE TABLE graph_edges (
  source_key TEXT NOT NULL,
  edge_type TEXT NOT NULL,
  target_key TEXT NOT NULL,
  PRIMARY KEY (source_key, edge_type, target_key)
);
```

Updated atomically on every entry write/delete. Only the changed entry's links
are re-parsed (incremental). No full scan on read.

#### 3. Graph query verb

Both a Ruby API and a CLI/MCP verb:

textus graph query --edge=refines --target=evidence.0120

Returns source key, edge type, and matching entries with key + body.

Ruby API: graph.query(edge: "refines", target: "evidence.0120")

#### 4. Compose workflow

New workflow type: compose. drain runs it as a sub-pass:

1. converge — refresh external data (existing)
2. materialize — build artifacts from canon (existing)
3. compose — run templates, publish docs (new)

Workflow DSL (new compose type):

```yaml
# .textus/workflows/compose-evidence-index.yaml
type: compose
steps:
  - gather: { edges: "refines evidence.0120", sort: key }
  - render: { template: evidence-index.html.erb, output: artifacts.docs.evidence-index }
  - publish: { target: docs/architecture/decisions/index.md }
```

#### 5. Templates

ERB files in .textus/templates/. Receive graph binding for queries.

```erb
<% graph.query(edge: "refines", target: "evidence.0120").each do |entry| %>
  <h3><%= entry.key %></h3>
  <%= entry.body %>
<% end %>
```

#### 6. Files

lib/textus/graph/link_parser.rb — parse comments from body
lib/textus/graph/index.rb — SQLite graph_edges table, sync on write
lib/textus/graph/query.rb — graph query (Ruby API + verb handler)
lib/textus/surface/cli/verb/graph_query.rb — graph query verb
lib/textus/surface/cli/group/graph.rb — graph verb group
lib/textus/workflows/compose.rb — compose workflow type
.textus/templates/ — ERB templates directory

~400 lines total.
