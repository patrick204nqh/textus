module Textus
  class CLI
    class Group < Verb
      class << self
        def subcommands
          @subcommands ||= {}
        end

        def cli_name
          @cli_name || raise("subclass must define cli_name")
        end

        attr_writer :cli_name

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@subcommands, {})
        end

        def needs_store?
          # Delegate to the matched subcommand at parse time; default true.
          true
        end
      end

      def parse(argv)
        subname = argv.shift
        if subname.nil?
          raise UsageError.new(
            "#{self.class.cli_name} requires a subcommand: #{self.class.subcommands.keys.join(", ")}",
          )
        end

        @sub_klass = self.class.subcommands[subname]
        unless @sub_klass
          raise UsageError.new(
            "unknown #{self.class.cli_name} subcommand '#{subname}'. " \
            "Valid: #{self.class.subcommands.keys.join(", ")}",
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
