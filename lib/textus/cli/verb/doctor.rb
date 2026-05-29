module Textus
  class CLI
    class Verb
      class Doctor < Verb
        command_name "doctor"

        option :checks, "--check=NAME"

        def call(store)
          check_list = checks&.split(",")&.map(&:strip)
          res = store.doctor(checks: check_list)
          emit(res, exit_code: res["ok"] ? 0 : 1)
        end
      end
    end
  end
end
