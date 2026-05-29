module Textus
  module MCP
    # Per-connection state held by the server. Immutable Data value;
    # advance_cursor returns a new instance via #with.
    Session = Data.define(:role, :cursor, :propose_zone, :manifest_etag) do
      def advance_cursor(new_cursor) = with(cursor: new_cursor)

      def check_etag!(observed_etag)
        return if observed_etag == manifest_etag

        raise ContractDrift.new(
          "manifest changed (was #{short_etag(manifest_etag)}, now #{short_etag(observed_etag)}); re-run boot",
        )
      end

      private

      # First 8 hex chars after the "sha256:" prefix — a stable short id for
      # the drift diagnostic. Tolerates non-prefixed values (delete_prefix is
      # a no-op when the prefix is absent).
      def short_etag(etag) = etag.to_s.delete_prefix("sha256:")[0, 8]
    end
  end
end
