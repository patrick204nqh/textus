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
