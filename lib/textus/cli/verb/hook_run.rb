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

          # Validate --as resolves to a declared role (raises InvalidRole); hook
          # run has no role-scoped authority itself, so the result is discarded.
          Role.resolve(flag: as_flag, env: ENV, root: store.root)

          begin
            Textus::Write::IntakeFetch.invoke(
              caps: store.container, handler: name, config: {}, args: args, label: "hook run",
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
