module Textus
  module Protocol
    module ActionRegistry
      module NodeActions
      end
    end
  end
end

Textus::Protocol::ActionRegistry.register(
  Textus::Protocol::ActionRegistry::ActionSpec.new(
    action: :node_enter,
    summary: "Enter a loop node: 'node enter <path>' (e.g. 'node enter evidence'). Pushes to the node stack.",
    args: [Textus::Protocol::ActionRegistry::ArgSpec.arg(name: :path, type: Array, required: true,
                                                       description: "path segments: node, topic, item")],
    surfaces: %i[cli mcp],
    category: :write,
  ),
)
Textus::Protocol::ActionRegistry.register(
  Textus::Protocol::ActionRegistry::ActionSpec.new(
    action: :node_exit,
    summary: "Exit the current loop node, returning to the previous node.",
    args: [],
    surfaces: %i[cli mcp],
    category: :write,
  ),
)
Textus::Protocol::ActionRegistry.register(
  Textus::Protocol::ActionRegistry::ActionSpec.new(
    action: :node_back,
    summary: "Pop one level from the node stack (item → topic → node).",
    args: [],
    surfaces: %i[cli mcp],
    category: :write,
  ),
)
Textus::Protocol::ActionRegistry.register(
  Textus::Protocol::ActionRegistry::ActionSpec.new(
    action: :node_switch,
    summary: "Exit the current node and enter a new one in one action.",
    args: [Textus::Protocol::ActionRegistry::ArgSpec.arg(name: :path, type: Array, required: true,
                                                       description: "target path segments")],
    surfaces: %i[cli mcp],
    category: :write,
  ),
)
Textus::Protocol::ActionRegistry.register(
  Textus::Protocol::ActionRegistry::ActionSpec.new(
    action: :node_status,
    summary: "Show current loop node, topic, item, stack, and available nodes.",
    args: [],
    surfaces: %i[cli mcp],
    category: :read,
  ),
)
