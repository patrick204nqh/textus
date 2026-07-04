# Enforces the uniform NNNN-topic-slug.md (or date-based, for scratchpad
# sessions) naming convention across every Loop node zone and scratchpad
# sub-lane. See knowledge.judgment.agent-behavior.0001-loop-behavior and
# the design doc for why this shape is strict.

Textus.workflow "loop-shape" do
  match "artifacts.doctor.loop-shape"

  node_pattern = /\A\d{4}-[a-z0-9-]+\.md\z/
  session_pattern = /\A\d{4}-\d{2}-\d{2}-[a-z0-9-]+\.md\z/

  shape "knowledge.loop.intent.*", naming: node_pattern
  shape "knowledge.loop.constraint.repo.*", naming: node_pattern
  shape "knowledge.loop.constraint.protocol.*", naming: node_pattern
  shape "knowledge.loop.judgment.engineering.*", naming: node_pattern
  shape "knowledge.loop.judgment.agent-behavior.*", naming: node_pattern
  shape "knowledge.loop.evidence.*", naming: node_pattern
  shape "knowledge.loop.execution.runbook.*", naming: node_pattern
  shape "knowledge.loop.execution.checklist.*", naming: node_pattern
  shape "knowledge.loop.execution.procedure.*", naming: node_pattern
  shape "knowledge.loop.feedback.*", naming: node_pattern
  shape "scratchpad.proposals.*", naming: node_pattern
  shape "scratchpad.sessions.*", naming: session_pattern

  publish
end
