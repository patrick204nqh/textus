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

        # Declarative CLI name. Reader returns the registered name (or nil
        # for verbs that aren't directly invokable, like the abstract
        # Verb/Group base classes). Writer registers it.
        def command_name(name = nil)
          if name.nil?
            @command_name
          else
            @command_name = name.to_s
          end
        end

        # Declares that this verb is a subcommand of `group_klass`. When
        # set, the verb is NOT a top-level CLI verb — it's listed under
        # the group's subcommands instead.
        def parent_group(group_klass = nil)
          if group_klass.nil?
            @parent_group
          else
            @parent_group = group_klass
          end
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@options, [])
          subclass.instance_variable_set(:@command_name, nil)
          subclass.instance_variable_set(:@parent_group, nil)
        end

        # Recursive subclass enumeration. Ruby 3.1 ships Class#subclasses
        # but not Class#descendants, so we expand it ourselves.
        def descendants
          subclasses.flat_map { |k| [k] + k.descendants }
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
          o.on("--output=FMT") { |v| fmt = v }
          o.on("--format=FMT") { |_v| raise FlagRenamed.new("--format", "--output") }
        end.permute!(argv)
        raise UsageError.new("only --output=json is supported in v1") unless fmt == "json"

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
        store.session(role: resolved_role(store)).ctx
      end

      # Returns a Session instance bound to the resolved role.
      def operations_for(store)
        store.session(role: resolved_role(store))
      end
    end
  end
end
