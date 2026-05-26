# ADR 0012 — Explicit hook registration

**Date:** 2026-05-27
**Status:** Accepted
**Depends on:** [ADR 0011](./0011-authorize-bang-in-context.md)

## Context

Hook files under `.textus/hooks/**/*.rb` had a simple-looking top-level
DSL:

```ruby
Textus.on(:entry_put, :audit) { |store:, key:, **| ... }
```

The simplicity was a thin layer over the only mutable global in the
library. `Textus.on` looked up `Loader.current_registry`, which was a
`Thread.current` thread-local. `Store#load_hooks` set the thread-local
inside a `Textus.with_registry(@registry) { load file }` block, ran
`load(file)` (which executed the `Textus.on` call, which read the
thread-local, which got the right registry), then restored the prior
value.

The mechanism worked, but it had a real cost:

1. **Test isolation was tricky.** Two specs that registered hooks
   through different registries could collide if test ordering or
   threading wasn't carefully managed. Several flaky tests had been
   patched with `around { |ex| Textus.with_registry(reg) { ex.run } }`
   blocks, accepting the thread-local shape rather than fixing it.
2. **Concurrent multi-store loads were unsafe.** A process loading two
   `Textus::Store` instances from two threads simultaneously could
   register hooks against the wrong registry — `Thread.current` is
   per-thread, but the `Textus.with_registry` block ran inside whichever
   thread called `Store#initialize`, and `load(file)` could trigger
   re-entrant hook loads.
3. **`Doctor::Check::Hooks`** and the gem's own initialization in
   `Hooks::Builtin.register_all` both leaned on the thread-local
   indirectly. Code reading any of those files needed to keep the
   global side-channel in mind.
4. **The shape was wrong for the layering.** `Textus.on` is a
   namespace-level call that pretends to be context-free, but it
   *requires* an ambient context to do anything useful. The
   thread-local was the workaround for that mismatch.

## Decision

Replace the thread-local with explicit, scoped block registration.

Each hook file declares a `Textus.hook { |reg| ... }` block. The block
receives the store's `Hooks::Registry` and calls `reg.on(event, name,
**opts, &blk)` directly:

```ruby
# .textus/hooks/audit.rb
Textus.hook do |reg|
  reg.on(:entry_put, :audit) { |store:, key:, **| ... }
end
```

`Textus.hook` itself does not register anything against any registry.
It appends the supplied block to a module-level queue guarded by a
`Mutex`:

```ruby
def self.hook(&blk)
  raise UsageError.new("hook block required") unless blk
  @hook_mutex ||= Mutex.new
  @hook_mutex.synchronize { (@hook_blocks ||= []) << blk }
end

def self.drain_hook_blocks
  @hook_mutex ||= Mutex.new
  @hook_mutex.synchronize { taken = @hook_blocks || []; @hook_blocks = []; taken }
end
```

`Hooks::Loader` becomes a per-store class. Constructed with a
registry, its `#load_dir(path)` walks the directory, `load`s each
file (each is expected to call `Textus.hook { ... }`), then drains
the queue and invokes every collected block with the registry:

```ruby
class Loader
  def initialize(registry:) = @registry = registry

  def load_dir(dir)
    return unless File.directory?(dir)
    Textus.drain_hook_blocks # discard any pending leftovers
    Dir.glob(File.join(dir, "**/*.rb")).sort.each { |f| load(f) }
    Textus.drain_hook_blocks.each { |blk| blk.call(@registry) }
  end
end
```

`Textus.on`, `Textus.with_registry`, and `Loader.current_registry` are
removed.

`Hooks::Builtin.register_all` takes a registry argument and registers
its built-in parsers (`json`, `csv`, `markdown-links`, `ical-events`,
`rss`) directly via `registry.on(...)`. No thread-local read.

`Doctor::Check::Hooks` walks `store.registry` directly — no thread-
local indirection.

`Hooks::Dispatcher`, `Loader` (its draining contract), and `Registry`
boundaries are otherwise unchanged. `Registry#on` is the canonical
instance API and has been since 0.11.

## Consequences

- **Public Ruby API breaks.** Every hook file in every textus-using
  project needs a one-line wrap. The CHANGELOG ships the migration
  pattern; it's mechanical.
- **No mutable globals.** The hook-block queue is a process-level
  list, but its lifetime is bounded by `Loader#load_dir` (drained
  on every call). Two threads loading two stores concurrently each
  see only their own blocks because each `load_dir` drains before
  it walks files and again after.
- **Test isolation is clean.** Specs instantiate
  `Hooks::Registry.new` and either call `reg.on(...)` directly or
  exercise the loader against a fixture directory. No `around` block,
  no thread-local cleanup.
- **`Doctor::Check::Hooks`, `Hooks::Builtin`, and the loader** no
  longer depend on global state. Each reads the registry handed to it
  at construction.
- **Concurrent multi-store loads safe.** The mutex around the queue
  serializes append/drain pairs. Each store's loader drains a fresh
  list and invokes against its own registry.

## Out of scope

- Reshaping `Hooks::Registry` itself. Its `#on`, `#listeners`,
  `#rpc_callable` API is unchanged.
- Reshaping `Hooks::Dispatcher`. The `on_error` callback added in
  ADR 0009 stays exactly as it was.
- Moving hooks discovery away from filesystem `Dir.glob`. Plugin-
  level hook registration (e.g., a gem declaring hooks via a
  manifest) is deferred — possibly to ADR 0013 once a real
  consumer needs it.

## Alternatives considered

- **Pass the registry as a positional argument to every hook file's
  top-level call.** Rejected: every hook file ends up with the same
  five-line boilerplate. The block form keeps the registry binding
  implicit-in-block-scope, explicit-at-the-DSL-boundary.
- **Singleton registry per process.** Rejected: defeats the whole
  point of per-store isolation. Embedders running two stores in one
  process is a supported scenario.
- **Fiber-local instead of thread-local.** Rejected: same shape,
  same problem. The mismatch was global-via-side-channel vs.
  explicit, not which side-channel.
- **`Textus.hook(registry, &blk)`** — pass the registry directly.
  Rejected: the registry isn't constructed until `Store#initialize`,
  but hook files are loaded *during* `Store#initialize`. The block-
  collector pattern lets the hook files declare without needing to
  know how the registry is wired.
