# Anti-Pattern Catalog

## P0 — boot.rb upward layer violation
Boot.build calls Surface::MCP::Catalog (boot.rb:114-115)
Fix: Pass verb lists as parameters

## P0 — InfrastructureProxy naming
Not a proxy pattern. Different field set. Aliased as ContainerProxy
Fix: Rename to UseCaseContainer

## P1 — Store SRP violation
7 responsibilities. build_ctx instantiates 14+ concretions
Fix: Extract Store::Builder

## P1 — Container duality
Two DI containers with different fields. Silent hazard
Fix: Unify into single container

## P2 — HANDLES_ALL vestigial code
Code path exists in HandlerResolver but banned by tests
Fix: Remove HANDLES_ALL code path

## P2 — Ctx alias
Ctx = Infrastructure is dangerously generic
Fix: Drop Ctx alias

## P2 — "contract" collision
Dispatch::Contracts vs @contract_etag
Fix: Rename @contract_etag → @config_etag

## P2 — Input binding duality
Three binding strategies with double default resolution on CLI
Fix: Single binding in Binder middleware

## P3 — Reader/Writer bypass use cases
6 callers bypass for direct I/O
Fix: Route through use cases or document as intentional

## P3 — Store::Layout cross-coupling
6 port files depend on Store::Layout
Fix: Extract to standalone class
