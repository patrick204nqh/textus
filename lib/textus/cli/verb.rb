require "json"
require "optparse"

module Textus
  class CLI
    class Verb
      class << self
        def option(name, optspec)
          options << [name, optspec]
          attr_accessor(name)
        end

        def options
          @options ||= []
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
            o.on(optspec) { |v| public_send("#{name}=", v) }
          end
          o.on("--format=FMT") { |v| fmt = v }
        end.permute!(argv)
        raise UsageError.new("only --format=json is supported in v1") unless fmt == "json"

        @positional = argv
      end

      attr_reader :positional

      def emit(obj)
        @stdout.puts(JSON.generate(obj))
        0
      end
    end
  end
end
