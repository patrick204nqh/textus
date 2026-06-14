module Textus
  module Surfaces
    class CLI
      class Verb
        class Doctor < Verb
          command_name "doctor"
          option :checks, "--check=NAME"

          def call(store)
            cmd = Textus::Command::Doctor.new(
              checks: checks&.split(",")&.map(&:strip),
              role: resolved_role(store),
            )
            res = store.gate.dispatch(cmd)
            emit(res, exit_code: res["ok"] ? 0 : 1)
          end
        end
      end
    end
  end
end
