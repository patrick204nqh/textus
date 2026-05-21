require "json"
require "optparse"

module Textus
  class CLI
    # Subclasses must implement #call(store) and return an integer exit code.
    # Use #emit(obj) for normal JSON output (returns 0).
    # Subclasses that don't need a Textus store (e.g. Init) override
    # `.needs_store?` to return false; dispatch will pass nil instead.
    class Verb
      class << self
        def option(name, optspec)
          options << [name, optspec]
          attr_accessor(name)
        end

        def options
          @options ||= []
        end

        def needs_store?
          true
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@options, [])
        end
      end

      def initialize(stdin:, stdout:, stderr:)
        @stdin = stdin
        @stdout = stdout
        @stderr = stderr
      end

      def parse(argv)
        fmt = "json"
        OptionParser.new do |o|
          self.class.options.each do |name, optspec|
            o.on(optspec) { |v| public_send(:"#{name}=", v) }
          end
          o.on("--format=FMT") { |v| fmt = v }
        end.permute!(argv)
        raise UsageError.new("only --format=json is supported in v1") unless fmt == "json"

        @positional = argv.dup
      end

      attr_reader :positional

      def emit(obj)
        @stdout.puts(JSON.generate(obj))
        0
      end
    end
  end
end
