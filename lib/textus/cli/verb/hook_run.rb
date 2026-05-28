module Textus
  class CLI
    class Verb
      class HookRun < Verb
        command_name "run"
        parent_group Group::Hook

        def parse(argv)
          @raw_argv = argv
        end

        def call(store)
          name = @raw_argv.shift
          raise UsageError.new("hook run requires a name") if name.nil?

          as_flag = nil
          args = {}
          @raw_argv.each do |tok|
            case tok
            when /\A--as=(.+)\z/         then as_flag = ::Regexp.last_match(1)
            when /\A--output=/           then next
            when /\A--format=/           then raise FlagRenamed.new("--format", "--output")
            when /\A--([\w-]+)=(.*)\z/   then args[::Regexp.last_match(1)] = ::Regexp.last_match(2)
            else
              raise UsageError.new("unknown arg to 'hook run #{name}': #{tok}")
            end
          end

          Role.resolve(flag: as_flag, env: ENV, root: store.root)

          begin
            Timeout.timeout(Textus::Application::Refresh::Worker::FETCH_TIMEOUT_SECONDS) do
              store.rpc.invoke(:resolve_intake, name, caps: nil, config: {}, args: args)
            end
          rescue Timeout::Error
            raise UsageError.new(
              "hook run '#{name}' exceeded #{Textus::Application::Refresh::Worker::FETCH_TIMEOUT_SECONDS}s timeout",
            )
          rescue Textus::Error
            raise
          rescue StandardError => e
            raise UsageError.new("hook run '#{name}' raised: #{e.class}: #{e.message}")
          end

          emit({ "action" => name, "ok" => true })
        end
      end
    end
  end
end
