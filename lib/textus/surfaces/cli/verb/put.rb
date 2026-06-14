module Textus
  module Surfaces
    class CLI
      class Verb
        class Put < Runner::Base
          self.spec = Textus::Action::Put.contract

          option :as_flag, "--as=ROLE"
          option :use_stdin, "--stdin"

          def invoke(store)
            key = positional.shift or raise UsageError.new("put requires a key")
            raise UsageError.new("put requires --stdin in v1") unless use_stdin

            role = resolved_role(store)

            # put only stores the stdin JSON (ADR 0089): no transform-on-write.
            # Ingest (running a handler over bytes) is system-pushed via drain/serve
            # and hook run, never a put flag.
            payload = JSON.parse(@stdin.read)

            meta = payload["_meta"] || {}
            body = payload["body"] || ""
            if_etag = payload["if_etag"]
            result = store.as(role).put(key, meta: meta, body: body, if_etag: if_etag)
            emit(result.to_h_for_wire)
          end
        end
      end
    end
  end
end
