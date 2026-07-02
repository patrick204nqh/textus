# SOLID Audit (July 2026)

Grades: S(C) O(B) L(A) I(A) D(C)

## S — Single Responsibility: C
- Store: 7 responsibilities (discovery, context building, dispatch, session, transitions, proxy building, etag drift)
- Boot: 4 responsibilities (verb catalog, agent protocol, artifact reading, envelope building)
- Fix: Extract Store::Builder, split Boot module

## O — Open/Closed: B
- VERB_TO_CONTRACT is manual hash (verb_registry.rb:62-95)
- Middleware, ports, doctor checks are pluggable

## L — Liskov Substitution: A
- Middleware call signature is uniform
- Entry hierarchy has sensible defaults
- Port interfaces guarantee substitutability

## I — Interface Segregation: A
- Handler NEEDS mechanism: each use case declares only fields it needs
- ContainerProxy is a thinner interface

## D — Dependency Inversion: C
- Store#build_ctx instantiates 14+ concretions
- Three use cases duplicate ContainerProxy construction
- Middleware depends on callable next_handler (good)
