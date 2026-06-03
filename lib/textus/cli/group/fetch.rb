module Textus
  class CLI
    class Group
      class Fetch < Group
        command_name "fetch"

        def parse(argv)
          if argv.first == "all"
            argv.shift
            @sub_klass = Verb::FetchAll
          else
            @sub_klass = Verb::Fetch
          end
          @sub = @sub_klass.new(stdin: @stdin, stdout: @stdout, stderr: @stderr, cwd: @cwd)
          @sub.parse(argv)
        end
      end
    end
  end
end
