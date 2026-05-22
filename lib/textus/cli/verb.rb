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

      def initialize(stdin:, stdout:, stderr:, cwd: nil)
        @stdin = stdin
        @stdout = stdout
        @stderr = stderr
        @cwd = cwd
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

      # Hashes get "protocol" => PROTOCOL prepended unless they already
      # carry one (Store envelopes do). Caller's value wins on collision.
      def emit(obj, exit_code: 0)
        payload = obj.is_a?(Hash) ? { "protocol" => PROTOCOL }.merge(obj) : obj
        @stdout.puts(JSON.generate(payload))
        exit_code
      end

      # Resolves the active role for this invocation. Honors the verb's
      # `--as` flag if declared, then TEXTUS_ROLE, then the project default.
      def resolved_role(store)
        flag = respond_to?(:as_flag) ? as_flag : nil
        Role.resolve(flag: flag, env: ENV, root: store.root)
      end

      # Returns an Application::Context bound to the resolved role.
      # Convenience for verbs whose only pre-call boilerplate is
      # resolving the role and wrapping it in a context.
      def context_for(store)
        Textus::Composition.context(store, role: resolved_role(store))
      end
    end
  end
end
