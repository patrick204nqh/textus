---
uid: adc9d742383d787d
---
# Bounded Use-Case Objects

Based on the architectural patterns of Rodrigo Serradura, textus adopts the Bounded Use-Case Object pattern to ensure the codebase remains simple to change as it grows.

## The Core Philosophy
The goal is to minimize the cost of change by maximizing locality. A developer (or agent) should be able to understand the full impact of a change by looking at a single, small file.

## The Pattern
Instead of grouping related actions into large "Service" or "Use-Case" modules with internal dispatchers, every action is its own first-class object.

### 1. One Class Per Contract
Every Dispatch::Contract must map to exactly one UseCase class.
- Bad: UseCases::EntryRead.call(command, deps) -> if command.is_a?(GetEntry) ...
- Good: UseCases::Read::GetEntry.call(command, deps)

### 2. Uniform Interface
All use cases must implement a uniform call method:
```ruby
def self.call(command, call, deps)
  # implementation
end
```

### 3. Isolated Dependencies
Dependencies are not shared at the module level. Each use case explicitly declares or uses only the slice of the container it requires. This prevents "dependency bloat" where a module requires 10 ports just because one of its 20 methods needs one of them.

### 4. No Central Dispatcher
The Gate or Dispatcher should resolve the use-case class directly from the contract mapping, eliminating the need for if/elsif or case statements within the use-case layer.

## Benefits for AI Agents
- Context Efficiency: Agents only need to read the specific use-case class, not a 500-line module.
- Reduced Regression Risk: Changes to one use-case cannot accidentally break another through shared private methods.
- Clearer Navigation: The file system becomes a direct map of the application's capabilities.
