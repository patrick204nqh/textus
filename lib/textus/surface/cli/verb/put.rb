module Textus
  module Surface
    class CLI
      class Verb
        class Put < Runner::Base
          self.spec = Textus::Protocol::VerbRegistry.for(:put)
          option :as_flag, "--as=ROLE"
          option :use_stdin, "--stdin"

          def invoke(store)
            key = positional.shift or raise UsageError.new("put requires a key")
            raise UsageError.new("put requires --stdin in v1") unless use_stdin

            payload = JSON.parse(@stdin.read)
            Textus::Protocol::VerbRegistry.for(:put)
            inputs = { key: key, meta: payload["_meta"] || {}, body: payload["body"] || "",
                       content: nil, if_etag: payload["if_etag"] }
            s = store.with_role(resolved_role(store))
            emit(s.put(**inputs))
          end
        end
      end
    end
  end
end
