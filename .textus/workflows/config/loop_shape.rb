# Enforces the uniform NNNN-topic-slug.md (or date-based, for scratchpad
# sessions) naming convention across every Loop node zone and scratchpad
# sub-lane. See knowledge.judgment.agent-behavior.0001-loop-behavior and
# the design doc for why this shape is strict.

Textus.workflow "loop-shape" do
  match "artifacts.doctor.loop-shape"

  node_pattern = /\A\d{4}-[a-z0-9-]+\.md\z/
  script_pattern = /\A\d{4}-[a-z0-9-]+\.\w+\z/
  session_pattern = /\A\d{4}-\d{2}-\d{2}-[a-z0-9-]+\.md\z/

  shape "knowledge.intent.*", naming: node_pattern
  shape "knowledge.constraint.repo.*", naming: node_pattern
  shape "knowledge.constraint.protocol.*", naming: node_pattern
  shape "knowledge.judgment.engineering.*", naming: node_pattern
  shape "knowledge.judgment.agent-behavior.*", naming: node_pattern
  shape "knowledge.evidence.*", naming: node_pattern
  shape "knowledge.execution.*", naming: node_pattern
  shape "knowledge.feedback.*", naming: node_pattern
  shape "scratchpad.sessions.*", naming: session_pattern
  shape "scratchpad.notes.*", naming: node_pattern
  shape "scratchpad.scripts.*", naming: script_pattern

  publish
end
