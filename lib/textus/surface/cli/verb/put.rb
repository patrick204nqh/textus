module Textus
  module Surface
    class CLI
      class Verb
        class Put < Runner::Base
          self.spec = Textus::Action::Put.contract
          option :as_flag, "--as=ROLE"
          option :use_stdin, "--stdin"

          def invoke(store)
            key = positional.shift or raise UsageError.new("put requires a key")
            raise UsageError.new("put requires --stdin in v1") unless use_stdin

            payload = JSON.parse(@stdin.read)
            cmd = Textus::Value::Command.new(
              verb: :put,
              params: { key: key, meta: payload["_meta"] || {}, body: payload["body"] || "",
                        content: nil, if_etag: payload["if_etag"] },
              role: resolved_role(store),
            )
            result = store.gate.dispatch(cmd)
            emit(result.to_h_for_wire)
          end
        end
      end
    end
  end
end
