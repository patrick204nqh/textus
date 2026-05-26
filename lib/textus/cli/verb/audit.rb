module Textus
  class CLI
    class Verb
      class Audit < Verb
        command_name "audit"

        option :key_filter, "--key=KEY"
        option :zone, "--zone=Z"
        option :role_filter, "--role=ROLE"
        option :verb_filter, "--verb=V"
        option :since, "--since=ISO8601|RELATIVE"
        option :correlation_id, "--correlation-id=ID"
        option :limit, "--limit=N"

        def call(store)
          ops = operations_for(store)
          since_time = since && Textus::Application::Reads::Audit.parse_since(since, now: ops.ctx.now)
          rows = ops.reads.audit.call(
            key: key_filter,
            zone: zone,
            role: role_filter,
            verb: verb_filter,
            since: since_time,
            correlation_id: correlation_id,
            limit: limit&.to_i,
          )
          emit({ "verb" => "audit", "rows" => rows })
        end
      end
    end
  end
end
