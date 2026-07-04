module Textus
  module Lanes
    module Scratchpad
      module Verbs
      end
    end
  end
end

Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    verb: :session_open, summary: "Create a new agent session with workspace directories.",
    args: [], surfaces: %i[cli mcp], category: :write,
    lane: :scratchpad
  ),
)
Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    verb: :session_close, summary: "Seal an active session by ID.",
    args: [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :session_id, required: true,
                                                       description: "UUID of the session to close")],
    surfaces: %i[cli mcp], category: :write,
    lane: :scratchpad
  ),
)

Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    verb: :propose, summary: "Write a proposal to scratchpad.proposals for human review.",
    args: [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :key, required: true, positional: true,
                                                       description: "key relative to propose_lane, e.g. 'decisions.feature-x'"),
           Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :meta, type: Hash, wire_name: :_meta,
                                                       description: "frontmatter. Include a 'proposal:' block naming the target_key"),
           Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :body,
                                                       description: "markdown/text payload for markdown-format entries"),
           Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :content, type: Hash,
                                                       description: "structured payload for json/yaml-format entries")],
    surfaces: %i[cli mcp], category: :write,
    lane: :scratchpad
  ),
)
Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    verb: :accept, summary: "Apply a scratchpad.proposals entry to its target zone; requires author.",
    args: [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :pending_key, required: true, positional: true,
                                                       description: "the queued proposal's key"),
           Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :dry_run, type: :boolean, default: false,
                                                       description: "when true, compute diff without promoting")],
    surfaces: %i[cli mcp], category: :write,
    lane: :scratchpad
  ),
)
Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    verb: :reject, summary: "Discard a scratchpad.proposals entry without applying it.",
    args: [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :pending_key, required: true, positional: true,
                                                       description: "the queued proposal's key"),
           Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :reason,
                                                       description: "optional explanation for the rejection")],
    surfaces: %i[cli mcp], category: :write,
    lane: :scratchpad
  ),
)
Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    verb: :diff, summary: "Preview the diff between a scratchpad.proposals entry and its target.",
    args: [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :pending_key, required: true, positional: true,
                                                       description: "the queued proposal's key")],
    surfaces: %i[cli mcp],
    category: :read,
    lane: :scratchpad
  ),
)
