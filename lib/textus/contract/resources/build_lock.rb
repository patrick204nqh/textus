module Textus
  module Contract
    module Resources
      # Serializes builds across every surface (CLI, MCP, Ruby). Previously the
      # CLI verb wrapped each build in a BuildLock by hand; lifting it into the
      # contract means the MCP surface inherits the single-writer guarantee and
      # cannot collide with a concurrent CLI or background build.
      class BuildLock
        def wrap(scope:, inputs:, session: nil) # rubocop:disable Lint/UnusedMethodArgument
          Textus::Ports::BuildLock.with(root: scope.container.root) { yield(inputs) }
        end
      end
    end
  end
end

Textus::Contract::Around.register(:build_lock, Textus::Contract::Resources::BuildLock.new)
