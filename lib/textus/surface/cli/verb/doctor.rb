module Textus
  module Surface
    class CLI
      class Verb
        class Doctor < Verb
          command_name "doctor"
          option :checks, "--check=NAME"

          def call(store)
            spec = Textus::VerbRegistry.for(:doctor)
            inputs = { checks: checks&.split(",")&.map(&:strip) }
            res = store.gate.dispatch(spec: spec, inputs: inputs, role: resolved_role(store))
            emit(res, exit_code: res["ok"] ? 0 : 1)
          end
        end
      end
    end
  end
end
