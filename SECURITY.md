# Security

## Supported versions

Only the latest `0.x` release line receives fixes. Once `1.0` ships, the policy will be revisited.

## Reporting a vulnerability

Email **patrick204nqh@gmail.com** with subject prefix `[textus security]`. Include:

- a description of the issue and its impact,
- a minimal reproducer if possible,
- the affected version (`textus --version` or the gem version),
- any disclosure timeline you have in mind.

You can expect an acknowledgement within 72 hours and a fix or rejection within two weeks for most reports.

Please do not file public issues for security-sensitive matters until a fix is released.

## Scope

textus stores data on the local filesystem and writes a single append-only audit log. It does not make network calls of its own — only registered actions do, and they run with the role permissions declared in the manifest. In-scope issues include:

- credential or token leakage through actions, hooks, or extensions,
- audit-log tampering paths,
- role-gate bypass on `put`, `delete`, `mv`, `accept`, or `build`,
- path traversal via `publish_to:` or `publish_each:` templates,
- arbitrary code execution through extension loading or template rendering.

Out of scope: vulnerabilities in user-supplied extension code, actions calling untrusted endpoints, or downstream consumers of the published artifacts.
