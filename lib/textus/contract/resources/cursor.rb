module Textus
  module Contract
    module Resources
      # Reads the persisted file cursor as the `since` default when the caller
      # did not supply one, runs pulse, then persists the returned cursor.
      # Replaces CLI::Verb::Pulse's hand-coded CursorStore read/write (ADR 0068).
      #
      # A session-bearing surface (MCP) carries its own cursor via the contract's
      # `session_default: :cursor`, so this defers entirely when a session is
      # present — it is the sessionless CLI/Ruby surfaces that need the file.
      class Cursor
        def wrap(scope:, inputs:, session:)
          return yield(inputs) if session

          store = Textus::CursorStore.new(root: scope.container.root, role: scope.role)
          effective = inputs.key?(:since) ? inputs : inputs.merge(since: store.read)
          result = yield(effective)
          store.write(result["cursor"]) if result.is_a?(Hash) && result["cursor"]
          result
        end
      end
    end
  end
end

Textus::Contract::Around.register(:cursor, Textus::Contract::Resources::Cursor.new)
