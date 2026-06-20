module Textus
  module Surface
    class CLI
      class Group < Verb
        class << self
          # Subcommands are auto-derived: any Verb descendant whose
          # `parent_group` is this group counts as a subcommand. Sorted
          # alphabetically by command_name for stable help output.
          def subcommands
            Textus::Surface::CLI::Runner.install!
            Verb.descendants
                .select { |k| k.parent_group == self && k.command_name }
                .sort_by(&:command_name)
                .to_h { |k| [k.command_name, k] }
          end

          def needs_store?
            # Delegate to the matched subcommand at parse time; default true.
            true
          end
        end

        def parse(argv)
          subs = self.class.subcommands
          subname = argv.shift
          if subname.nil?
            raise UsageError.new(
              "#{self.class.command_name} requires a subcommand: #{subs.keys.join(", ")}",
            )
          end

          @sub_klass = subs[subname]
          unless @sub_klass
            raise UsageError.new(
              "unknown #{self.class.command_name} subcommand '#{subname}'. " \
              "Valid: #{subs.keys.join(", ")}",
            )
          end

          @sub = @sub_klass.new(stdin: @stdin, stdout: @stdout, stderr: @stderr, cwd: @cwd)
          @sub.parse(argv)
        end

        def call(store)
          @sub.call(@sub_klass.needs_store? ? store : nil)
        end
      end
    end
  end
end
