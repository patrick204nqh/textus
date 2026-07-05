module Textus
  module Surface
    module MCP
      class CursorManager
        def initialize(store:, role:)
          @store = store
          @role = role
        end

        def resume!
          saved = @store.container.store.cursor_store.get(@role)[:seq]
          latest = @store.container.store.audit_log.latest[:seq]
          @store.advance_cursor(saved) if saved.positive? && saved <= latest
        end

        def advance!(seq:)
          @store.advance_cursor(seq)
        end
      end
    end
  end
end
