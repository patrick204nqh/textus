module Textus
  # The agent session: per-connection (MCP), per-process (CLI), or per-loop
  # (Ruby) orientation state — the audit cursor plus the contract etag and
  # propose_lane captured at boot. Immutable Data value; advance_cursor
  # returns a new instance. ADR 0036; contract_etag widened in ADR 0074.
  Session = Data.define(:role, :cursor, :propose_lane, :contract_etag) do
    # Back-compat reader while lane terminology migrates.
    def propose_zone = propose_lane

    def advance_cursor(new_cursor) = with(cursor: new_cursor)

    def check_etag!(observed_etag)
      return if observed_etag == contract_etag

      raise Textus::Surfaces::MCP::ContractDrift.new(
        "contract changed (manifest/hooks/schemas were #{short_etag(contract_etag)}, " \
        "now #{short_etag(observed_etag)}); re-run boot",
      )
    end

    private

    # First 8 hex chars after the "sha256:" prefix — a stable short id for
    # the drift diagnostic. Tolerates non-prefixed values (delete_prefix is
    # a no-op when the prefix is absent).
    def short_etag(etag) = etag.to_s.delete_prefix("sha256:")[0, 8]
  end
end
