module Textus
  class CLI
    class Verb
      class HookRun < Verb
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
            when /\A--format=/           then next
            when /\A--([\w-]+)=(.*)\z/   then args[::Regexp.last_match(1)] = ::Regexp.last_match(2)
            else
              raise UsageError.new("unknown arg to 'hook run #{name}': #{tok}")
            end
          end

          role = Role.resolve(flag: as_flag, env: ENV, root: store.root)
          callable = store.registry.rpc_callable(:intake, name)
          view = Store::View.new(store, writable: true, as: role)

          begin
            Timeout.timeout(Textus::Refresh::FETCH_TIMEOUT_SECONDS) do
              callable.call(config: {}, store: view, args: args)
            end
          rescue Timeout::Error
            raise UsageError.new(
              "hook run '#{name}' exceeded #{Textus::Refresh::FETCH_TIMEOUT_SECONDS}s timeout",
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
