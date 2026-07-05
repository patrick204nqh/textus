module Textus
  module Surface
    class CLI
      class Verb
        class Put < Runner::Base
          self.spec = Textus::Protocol::VerbRegistry.for(:put)
          option :as_flag, "--as=ROLE"
          option :use_stdin, "--stdin"
          option :as_format, "--as-format=FORMAT"

          def invoke(store)
            key = positional.shift or raise UsageError.new("put requires a key")
            raise UsageError.new("put requires --stdin in v1") unless use_stdin

            payload = JSON.parse(@stdin.read)
            Textus::Protocol::VerbRegistry.for(:put)
            inputs = { key: key, meta: payload["_meta"] || {}, data: payload["data"],
                       if_etag: payload["if_etag"] }
            inputs[:format] = as_format if as_format
            s = store.with_role(resolved_role(store))
            emit(s.put(**inputs))
          end
        end
      end
    end
  end
end
