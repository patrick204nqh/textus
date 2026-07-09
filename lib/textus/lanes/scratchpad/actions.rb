module Textus
  module Lanes
    module Scratchpad
      module Actions
      end
    end
  end
end

Textus::Protocol::ActionRegistry.register(
  Textus::Protocol::ActionRegistry::ActionSpec.new(
    action: :session_open, summary: "Create a new agent session with workspace directories.",
    args: [], surfaces: %i[cli mcp], category: :write,
    lane: :scratchpad
  ),
)
Textus::Protocol::ActionRegistry.register(
  Textus::Protocol::ActionRegistry::ActionSpec.new(
    action: :session_close, summary: "Seal an active session by ID.",
    args: [Textus::Protocol::ActionRegistry::ArgSpec.arg(name: :session_id, required: true, positional: true,
                                                       description: "UUID of the session to close"),
           Textus::Protocol::ActionRegistry::ArgSpec.arg(name: :nodes_checked, type: Array,
                                                       description: "list of loop nodes checked during the session")],
    surfaces: %i[cli mcp], category: :write,
    lane: :scratchpad
  ),
)

Textus::Protocol::ActionRegistry.register(
  Textus::Protocol::ActionRegistry::ActionSpec.new(
    action: :propose, summary: "Write a proposal to scratchpad.proposals for human review.",
    args: [Textus::Protocol::ActionRegistry::ArgSpec.arg(name: :key, required: true, positional: true,
                                                       description: "key relative to propose_lane, e.g. 'decisions.feature-x'"),
           Textus::Protocol::ActionRegistry::ArgSpec.arg(name: :meta, type: Hash, wire_name: :_meta,
                                                       description: "frontmatter. Include a 'proposal:' block naming the target_key"),
           Textus::Protocol::ActionRegistry::ArgSpec.arg(name: :data,
                                                       description: "unified payload — String (body) or Hash (content)")],
    surfaces: %i[cli mcp], category: :write,
    lane: :scratchpad
  ),
)
Textus::Protocol::ActionRegistry.register(
  Textus::Protocol::ActionRegistry::ActionSpec.new(
    action: :accept, summary: "Apply a scratchpad.proposals entry to its target zone; requires author.",
    args: [Textus::Protocol::ActionRegistry::ArgSpec.arg(name: :pending_key, required: true, positional: true,
                                                       description: "the queued proposal's key"),
           Textus::Protocol::ActionRegistry::ArgSpec.arg(name: :dry_run, type: :boolean, default: false,
                                                       description: "when true, compute diff without promoting")],
    surfaces: %i[cli mcp], category: :write,
    lane: :scratchpad
  ),
)
Textus::Protocol::ActionRegistry.register(
  Textus::Protocol::ActionRegistry::ActionSpec.new(
    action: :reject, summary: "Discard a scratchpad.proposals entry without applying it.",
    args: [Textus::Protocol::ActionRegistry::ArgSpec.arg(name: :pending_key, required: true, positional: true,
                                                       description: "the queued proposal's key"),
           Textus::Protocol::ActionRegistry::ArgSpec.arg(name: :reason,
                                                       description: "optional explanation for the rejection")],
    surfaces: %i[cli mcp], category: :write,
    lane: :scratchpad
  ),
)
Textus::Protocol::ActionRegistry.register(
  Textus::Protocol::ActionRegistry::ActionSpec.new(
    action: :diff, summary: "Preview the diff between a scratchpad.proposals entry and its target.",
    args: [Textus::Protocol::ActionRegistry::ArgSpec.arg(name: :pending_key, required: true, positional: true,
                                                       description: "the queued proposal's key")],
    surfaces: %i[cli mcp],
    category: :read,
    lane: :scratchpad
  ),
)
