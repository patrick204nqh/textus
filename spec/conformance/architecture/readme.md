# Architecture conformance specs

These specs enforce the structural conventions established in the
architecture-deepening PR (2026-06-21). Each spec locks a specific invariant
that would break if future code drifts from the pattern.

| Spec | Locks |
|------|-------|
| `port_shape_spec.rb` | All ports are classes (`Port::Clock`, `Port::Publisher` no longer modules) |
| `geometry_injection_spec.rb` | Writer/Reader use Geometry, not `zone_floor` |
