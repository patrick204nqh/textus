module Textus
  class CLI
    class Verb
      class Audit < Verb
        option :key_filter, "--key=KEY"
        option :zone, "--zone=Z"
        option :role_filter, "--role=ROLE"
        option :verb_filter, "--verb=V"
        option :since, "--since=ISO8601|RELATIVE"
        option :correlation_id, "--correlation-id=ID"
        option :limit, "--limit=N"

        def call(store)
          role = Role.resolve(flag: nil, env: ENV, root: store.root)
          ctx = Textus::Composition.context(store, role: role)
          since_time = since && Textus::Application::Reads::Audit.parse_since(since, now: ctx.now)
          rows = Textus::Composition.audit(ctx).call(
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
