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
