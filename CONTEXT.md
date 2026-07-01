# Textus Context

Textus is a coordination space where humans, agents, and automation write to different lanes under explicit capability rules. This glossary defines the canonical language used when discussing architecture and seams.

## Language

**Lane**:
A write-authority partition that groups entries by trust and ownership intent.
_Avoid_: Zone, bucket

**Role**:
A named writer identity that holds a capability set used to authorize transitions.
_Avoid_: Actor type, user class

**Capability**:
A verb-level authority token that allows a role to perform a class of writes.
_Avoid_: Permission flag, access bit

**Proposal Trust Path**:
The transition path where a proposal is queued by `propose` and promoted to canon only by `author`.
_Avoid_: Fast path, direct write

**VerbDispatch Module**:
The module that resolves a verb token into one dispatched operation through a single interface for all adapters.
_Avoid_: Router service, command boundary

**Invocation**:
The per-request pair of command intent and call context that crosses the dispatch seam.
_Avoid_: Request bag, context blob

**Infrastructure Module**:
The unified dependency module that replaces the old container seam and supplies collaborators to dispatch and use-case modules.
_Avoid_: Container bag, dependency blob

**Dependency Adoption Gate**:
The rule module that every new external dependency must pass before adoption, based on seam clarity, interface depth, and exit cost.
_Avoid_: Gem trial, convenience install

**Dependency Adapter Module**:
An adapter module that exposes the published interface textus depends on while hiding dependency-specific implementation details.
_Avoid_: Direct gem call, vendor lock-in seam
