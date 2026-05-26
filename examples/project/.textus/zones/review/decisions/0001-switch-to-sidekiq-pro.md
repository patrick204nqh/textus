---
name: "0001-example"
status: proposed
date: "2026-05-26"
context: |
  Example ADR proposal showing the agent → human accept flow. Run
  `textus accept review.decisions.0001-example --as=human` to promote
  this to identity (or wherever the proposal's target_key points).
proposal:
  target_key: identity.decision-0001
  action: put
---

This is a placeholder ADR body. In a real project, an agent would write
this entry and a human would review and `textus accept` to promote it.
