module Textus
  class Orchestration
    ListKeysQuery = Data.define(:prefix, :lane)
    MoveKeyCommand = Data.define(:old_key, :new_key, :if_etag, :dry_run)
    DeleteKeyCommand = Data.define(:key, :if_etag)
    AuditQuery = Data.define(:seq_since, :key, :lane, :role, :verb, :since, :correlation_id, :limit)

    def initialize(list_keys:, move_key:, delete_key:, audit_entries:)
      @list_keys = list_keys
      @move_key = move_key
      @delete_key = delete_key
      @audit_entries = audit_entries
    end

    def list_keys(prefix:, lane:, call:)
      query = ListKeysQuery.new(prefix: prefix, lane: lane)
      normalize(@list_keys.call(query, call), key: "rows")
    end

    def move_key(old_key:, new_key:, call:, if_etag: nil, dry_run: false)
      command = MoveKeyCommand.new(old_key: old_key, new_key: new_key, if_etag: if_etag, dry_run: dry_run)
      normalize(@move_key.call(command, call), key: "move")
    end

    def delete_key(key:, call:, if_etag: nil)
      command = DeleteKeyCommand.new(key: key, if_etag: if_etag)
      normalize(@delete_key.call(command, call), key: "delete")
    end

    # rubocop:disable Metrics/ParameterLists
    def audit_entries(call:, seq_since: nil, key: nil, lane: nil, role: nil, verb: nil, since: nil, correlation_id: nil, limit: nil)
      query = AuditQuery.new(
        seq_since: seq_since,
        key: key,
        lane: lane,
        role: role,
        verb: verb,
        since: since,
        correlation_id: correlation_id,
        limit: limit,
      )
      normalize(@audit_entries.call(query, call), key: "rows")
    end
    # rubocop:enable Metrics/ParameterLists

    private

    def normalize(result, key:)
      return result unless result.is_a?(Value::Result)
      return result if result.failure?

      Value::Result.success({ key => result.value })
    end
  end
end
