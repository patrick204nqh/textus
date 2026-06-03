module Textus
  class CLI
    class Verb
      class Audit < Runner::Base
        self.spec = Textus::Read::Audit.contract
        command_name "audit"

        option :key_filter, "--key=KEY"
        option :zone, "--zone=Z"
        option :role_filter, "--role=ROLE"
        option :verb_filter, "--verb=V"
        option :since, "--since=ISO8601|RELATIVE"
        option :seq_since, "--seq-since=N"
        option :correlation_id, "--correlation-id=ID"
        option :limit, "--limit=N"

        def invoke(store)
          ops = session_for(store)
          since_time = since && Textus::Read::Audit.parse_since(since, now: Time.now)
          rows = ops.audit(
            key: key_filter,
            zone: zone,
            role: role_filter,
            verb: verb_filter,
            since: since_time,
            seq_since: seq_since&.to_i,
            correlation_id: correlation_id,
            limit: limit&.to_i,
          )
          emit({ "verb" => "audit", "rows" => rows })
        end
      end
    end
  end
end
