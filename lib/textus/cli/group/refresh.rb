module Textus
  class CLI
    class Group
      class Refresh < Group
        command_name "refresh"

        def parse(argv)
          if argv.first == "stale"
            argv.shift
            @sub_klass = Verb::RefreshStale
          else
            @sub_klass = Verb::Refresh
          end
          @sub = @sub_klass.new(stdin: @stdin, stdout: @stdout, stderr: @stderr, cwd: @cwd)
          @sub.parse(argv)
        end
      end
    end
  end
end
