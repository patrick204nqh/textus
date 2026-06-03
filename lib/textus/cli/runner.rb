module Textus
  class CLI
    # Generates CLI::Verb (and CLI::Group) subclasses from per-verb contracts,
    # so the CLI surface is a projection of the contract — the operator-facing
    # mirror of MCP::Catalog (ADR 0063).
    module Runner
      # Subclassable base for contract-projected verbs. Carries the verb's
      # contract (class attr `spec`) and the generic dispatch, exposing one
      # overridable seam, #invoke, that defaults to the generic projection.
      # Escape-hatch verbs subclass this and override #invoke to add behavior
      # (suggestions, --stdin, BuildLock, multi-dispatch) WITHOUT restating the
      # verb name — `spec.verb` remains the single source of dispatch.
      class Base < Verb
        class << self
          attr_accessor :spec

          # ADR 0064: derive the CLI command name from the contract's cli_leaf
          # when not set explicitly, so an escape-hatch class never restates its
          # own name. The reconciliation spec proves command_name == cli_leaf for
          # every such class, so this is an equivalence, not a behavior change.
          def command_name(name = nil)
            return super if name

            super() || spec&.cli_leaf
          end
        end

        def spec = self.class.spec

        def call(store)
          invoke(store)
        end

        # Default: pure contract projection. Override in subclasses for behavior.
        def invoke(store)
          Runner.dispatch(self, store, spec)
        end

        def flag_values(s = spec)
          s.args.reject(&:positional).each_with_object({}) do |a, h|
            raw = respond_to?(a.name) ? public_send(a.name) : nil
            next if raw.nil?

            h[a.name] = Runner.coerce(a, raw)
          end
        end
      end

      module_function

      # Normalize parsed CLI input into the uniform by-name inputs hash and
      # dispatch through RoleScope's single bind+invoke site. A missing required
      # arg becomes a UsageError phrased in the operator's command path (parity
      # with the hand-written verbs).
      def dispatch(verb_instance, store, spec)
        inputs = Textus::Contract::Binder.inputs_from_ordered(
          spec, verb_instance.positional, verb_instance.flag_values(spec)
        )
        inputs = inputs.merge(Textus::Contract::Sources.from_stdin(spec, verb_instance.stdin)) if spec.cli_stdin
        inputs = Textus::Contract::Sources.acquire(spec, inputs)
        inputs = apply_cli_defaults(spec, inputs)
        scope = verb_instance.session_for(store)
        begin
          result = scope.dispatch_bound(spec.verb, inputs)
        rescue Textus::Contract::MissingArgs => e
          raise UsageError.new("#{spec.cli_path} requires #{e.missing.first.wire}")
        end
        verb_instance.emit(shape(spec, result, inputs))
      end

      # Fill CLI-specific defaults (cli_default:) for args the operator did not
      # pass, where the CLI default diverges from the contract default the agent
      # surfaces use — e.g. migrate/zone_mv apply by default on the CLI but plan
      # by default for agents (ADR 0068). The divergence is legible in the
      # contract, not hidden in a hand class.
      def apply_cli_defaults(spec, inputs)
        spec.args.each_with_object(inputs.dup) do |a, h|
          next if a.cli_default == :__unset || h.key?(a.name)

          h[a.name] = a.cli_default
        end
      end

      # Shape the use-case result for the CLI wire via the verb's :cli view
      # (falling back to the default view). The view is called uniformly as
      # (result, inputs); an inputs-aware view echoes an input such as the key
      # (ADR 0067).
      def shape(spec, result, inputs)
        Textus::Contract::View.render(spec, :cli, result, inputs)
      end

      # The default the CLI flag is generated against — `cli_default:` when the
      # operator-facing default diverges from the contract default the agent
      # surfaces use, else the contract `default`. This drives boolean flag
      # polarity so a verb that applies-by-default on the CLI but plans-by-default
      # for agents (migrate, zone_mv) gets a `--dry-run` flag, not `--no-dry-run`.
      def effective_default(arg)
        arg.cli_default == :__unset ? arg.default : arg.cli_default
      end

      def flagspec_for(arg)
        wire = arg.wire.to_s.tr("_", "-")
        if arg.type == :boolean
          effective_default(arg) == true ? "--no-#{wire}" : "--#{wire}"
        else
          "--#{wire}=VALUE"
        end
      end

      # NB: compare arg.type by equality, not `case`/`===` — `Integer === arg.type`
      # is false when arg.type is the Integer *class* (it tests instance-of), so a
      # `when Integer` branch would silently never coerce.
      def coerce(arg, raw)
        return effective_default(arg) != true if arg.type == :boolean
        return Integer(raw) if arg.type == Integer

        raw
      end

      def ensure_group(name)
        const = name.split("_").map(&:capitalize).join
        return Group.const_get(const, false) if Group.const_defined?(const, false)

        g = Class.new(Group) { command_name name }
        Group.const_set(const, g)
        g
      end

      # Contract verbs whose CLI behavior is a genuine `< Runner::Base` override
      # — behavior the generic projection cannot express (ADR 0068/0069):
      #   get   — raises UnknownKey with resolver suggestions (a CLI-only
      #           affordance; the agent surface deliberately returns nil)
      #   put   — IntakeFetch read-through orchestration on --fetch
      #   build — auto-resolves the build-capability actor role (not --as) and
      #           serializes under BuildLock; the role resolution is policy, not
      #           a projection (around: covers only the lock)
      BEHAVIORAL_HATCHES = %i[get put build].freeze

      # Contract verbs whose CLI is a plain `< Verb` command, not a projection at
      # all — worker verbs and composite reports assembled outside the contract:
      #   fetch, fetch_all — background intake workers (not request/response)
      #   boot, doctor     — composite reports
      NON_PROJECTED_CLI = %i[fetch fetch_all boot doctor].freeze

      # The installer skips generation for either category.
      HAND_AUTHORED_VERBS = (BEHAVIORAL_HATCHES + NON_PROJECTED_CLI).freeze

      def hand_authored?(verb) = HAND_AUTHORED_VERBS.include?(verb)

      def install!
        @installed ||= {}
        Textus::Dispatcher::VERBS.each_value do |klass|
          next unless klass.respond_to?(:contract?) && klass.contract?

          spec = klass.contract
          next unless spec.cli?
          next if hand_authored?(spec.verb)
          next if @installed[spec.verb]

          install_for(spec)
          @installed[spec.verb] = true
        end
      end

      def install_for(spec)
        group = spec.cli_group ? ensure_group(spec.cli_group) : nil
        leaf  = spec.cli_leaf
        non_positional = spec.args.reject(&:positional)

        klass = Class.new(Base)
        klass.spec = spec
        klass.command_name leaf
        klass.parent_group group if group
        klass.option :as_flag, "--as=ROLE"
        klass.option :use_stdin, "--stdin" if spec.cli_stdin
        non_positional.each { |a| klass.option a.name, Runner.flagspec_for(a) }

        # Anchor the anonymous class to a constant so descendants discovery is
        # stable. Name it after the verb under a Generated namespace.
        const_name = spec.verb.to_s.split("_").map(&:capitalize).join
        gen = "Gen#{const_name}"
        Verb.const_set(gen, klass) unless Verb.const_defined?(gen, false)
        klass
      end
    end
  end
end
