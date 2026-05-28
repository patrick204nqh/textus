module Textus
  module MCP
    # Per-connection state held by the server. Immutable; advance_cursor
    # returns a new instance.
    class Session
      attr_reader :role, :cursor, :propose_zone, :manifest_etag

      def initialize(role:, cursor:, propose_zone:, manifest_etag:)
        @role = role
        @cursor = cursor
        @propose_zone = propose_zone
        @manifest_etag = manifest_etag
      end

      def advance_cursor(new_cursor)
        self.class.new(
          role: @role, cursor: new_cursor,
          propose_zone: @propose_zone, manifest_etag: @manifest_etag
        )
      end

      def check_etag!(observed_etag)
        return if observed_etag == @manifest_etag

        raise ContractDrift.new(
          "manifest changed (was #{@manifest_etag[0, 8]}, now #{observed_etag[0, 8]}); re-run boot",
        )
      end
    end
  end
end
