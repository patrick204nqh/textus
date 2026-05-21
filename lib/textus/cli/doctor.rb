module Textus
  class CLI
    class DoctorVerb < Verb
      option :checks, "--check=NAME"

      def call(store)
        check_list = checks&.split(",")&.map(&:strip)
        res = Textus::Doctor.run(store, checks: check_list)
        @stdout.puts(JSON.generate(res))
        res["ok"] ? 0 : 1
      end
    end
  end
end
