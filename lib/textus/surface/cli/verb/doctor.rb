module Textus
  module Surface
    class CLI
      class Verb
        class Doctor < Verb
          command_name "doctor"
          option :checks, "--check=NAME"

          def call(store)
            Textus::VerbRegistry.for(:doctor)
            inputs = { checks: checks&.split(",")&.map(&:strip) }
            s = store.with_role(resolved_role(store))
            res = s.doctor(**inputs)
            emit(res, exit_code: res["ok"] ? 0 : 1)
          end
        end
      end
    end
  end
end
