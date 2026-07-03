module Textus
  module Agent
    class Evidence
      attr_reader :session_id, :entries

      def initialize(session_id, store)
        @session_id = session_id
        @store = store
        @entries = []
      end

      def attach(key, note: nil)
        @entries << { key:, note:, attached_at: Time.now.utc.iso8601 }
      end

      def trace
        { session_id:, entries: @entries.dup }
      end
    end
  end
end
