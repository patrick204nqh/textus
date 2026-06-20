# frozen_string_literal: true

require "dry-struct"

module Textus
  # The agent session: per-connection (MCP), per-process (CLI), or per-loop
  # (Ruby) orientation state — the audit cursor plus the contract etag and
  # propose_lane captured at boot. Immutable Dry::Struct::Value; advance_cursor
  # and with return new instances. ADR 0036; contract_etag widened in ADR 0074.
  class Session < Dry::Struct
    attribute :role,          Value::Types::RoleName
    attribute :cursor,        Value::Types::Cursor
    attribute :propose_lane,  Value::Types::String.optional
    attribute :contract_etag, Value::Types::String

    def with(**attrs) = self.class.new(to_h.merge(attrs))

    def advance_cursor(new_cursor) = with(cursor: new_cursor)

    def check_etag!(observed_etag)
      return if observed_etag == contract_etag

      raise Textus::ContractDrift.new(
        "contract changed (manifest/hooks/schemas were #{short_etag(contract_etag)}, " \
        "now #{short_etag(observed_etag)}); re-run boot",
      )
    end

    private

    # First 8 hex chars after the "sha256:" prefix — a stable short id for
    # the drift diagnostic.
    def short_etag(etag) = etag.to_s.delete_prefix("sha256:")[0, 8]
  end
end
