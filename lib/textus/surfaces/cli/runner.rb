module Textus
  module Surfaces
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

        # Build a Command from the spec + parsed inputs, dispatch through Gate.
        def dispatch(verb_instance, store, spec)
          inputs = Textus::Contract::Binder.inputs_from_ordered(
            spec, verb_instance.positional, verb_instance.flag_values(spec)
          )
          inputs = inputs.merge(Textus::Contract::Sources.from_stdin(spec, verb_instance.stdin)) if spec.cli_stdin
          inputs = Textus::Contract::Sources.acquire(spec, inputs)
          inputs = apply_cli_defaults(spec, inputs)
          role = verb_instance.resolved_role(store)

          invoke = lambda do |effective_inputs|
            cmd = build_command(spec, effective_inputs, role)
            store.gate.dispatch(cmd, container: store.container)
          end

          result = if spec.around
                     scope = store.as(role)
                     Textus::Contract::Around.with(spec.around, scope: scope, inputs: inputs, session: nil, &invoke)
                   else
                     invoke.call(inputs)
                   end
          verb_instance.emit(shape(spec, result, inputs))
        rescue Textus::Contract::MissingArgs => e
          raise UsageError.new("#{spec.cli_path} requires #{e.missing.first.wire}")
        end

        def build_command(spec, inputs, role)
          cmd_class = Textus::Gate::VERB_COMMAND.fetch(spec.verb) do
            raise Textus::UsageError.new("no Command for verb: #{spec.verb}")
          end
          defaults = {}
          spec.args.each do |a|
            next if a.default == :__unset || inputs.key?(a.name)
            next if a.default.nil? && a.required

            defaults[a.name] = a.default
          end
          kwargs = defaults.merge(inputs)
          kwargs[:role] = role if cmd_class.members.include?(:role) && !inputs.key?(:role) && spec.verb != :audit
          missing = cmd_class.members - kwargs.keys
          raise Textus::Contract::MissingArgs.new(spec, missing.map { |m| Struct.new(:wire, :name).new(m.to_s, m) }) unless missing.empty?

          cmd_class.new(**kwargs.slice(*cmd_class.members))
        end

        # Fill CLI-specific defaults (cli_default:) for args the operator did not
        # pass, where the CLI default diverges from the contract default the agent
        # surfaces use — e.g. migrate/data_mv apply by default on the CLI but plan
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
        # for agents (migrate, data_mv) gets a `--dry-run` flag, not `--no-dry-run`.
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
        #   put   — reads the entry JSON from --stdin (ADR 0089: just stores bytes,
        #           no --fetch transform)
        # (build removed in ADR 0087: materialization is system-pushed via drain/serve)
        BEHAVIORAL_HATCHES = %i[get put].freeze

        # Contract verbs whose CLI is a plain `< Verb` command, not a projection at
        # all — composite reports assembled outside the contract.
        # (boot removed: its contract carries surfaces :cli + the :lean arg, so the
        # generic projection now generates it; the hand-authored CLI::Verb::Boot is
        # deleted in ADR 0101.)
        # (doctor retained: hand-authored to preserve --check=NAME flag spelling and
        # the exit_code: res["ok"] ? 0 : 1 behavior — two things the generic
        # projection cannot yet express; kept in ADR 0101 pending a future pass.)
        # (fetch/fetch_all were removed in ADR 0079: Produce::Acquire::Intake is now internal,
        # driven by the converge sweep (drain/serve) and hook run — ADR 0089 removed the
        # read-through that once also drove it.)
        NON_PROJECTED_CLI = %i[doctor].freeze

        # The installer skips generation for either category.
        HAND_AUTHORED_VERBS = (BEHAVIORAL_HATCHES + NON_PROJECTED_CLI).freeze

        def hand_authored?(verb) = HAND_AUTHORED_VERBS.include?(verb)

        def install!
          @installed ||= {}
          Textus::Gate::ROUTES.each_key do |cmd_class|
            verb = Textus::Gate::VERB_COMMAND.key(cmd_class)
            next unless verb

            action_class = Textus::Gate::ROUTES[cmd_class].first
            next unless action_class.respond_to?(:contract?) && action_class.contract?

            spec = action_class.contract
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
end
