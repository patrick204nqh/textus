module Textus
  module Workflow
    module DSL
      Step = Data.define(:name, :callable, :timeout)
      Parallel = Data.define(:steps)
      PublishTarget = Data.define(:to, :template, :tree, :inject_boot)

      class Definition
        include Textus::Workflow::Helpers

        attr_reader :name, :steps, :on_patterns, :save_key, :notify_keys,
                    :publish_block, :publish_targets,
                    :handled_events, :workflow_type

        def self.register(defn)
          @definitions ||= []
          @definitions << defn
        end

        def self.definitions
          @definitions || []
        end

        def self.clear_registered
          @definitions = []
        end

        def initialize(name)
          @name                = name
          @steps               = []
          @on_patterns         = []
          @save_key            = nil
          @notify_keys         = []
          @publish_block       = nil
          @publish_targets     = []
          @priority            = 0
          @handled_events      = []
          @max_attempts        = 3
          @workflow_type       = name
        end

        # ── Event handling (internal) ──
        def handles(*event_types)
          @handled_events.concat(event_types.map(&:to_s).freeze)
        end

        def type
          @workflow_type
        end

        def max_attempts(n = nil)
          return @max_attempts if n.nil?

          @max_attempts = n.to_i
        end

        # ── Trigger ──
        def on(*patterns)
          @on_patterns = patterns
        end

        # ── Steps ──
        def step(name, callable = nil, timeout: nil, &block)
          if callable.is_a?(Hash)
            raise ArgumentError.new(
              "step :#{name} no longer accepts options hash; pass timeout: keyword instead",
            )
          end

          resolved = if callable.respond_to?(:call)
                       callable
                     elsif block
                       block
                     else
                       raise ArgumentError.new("step :#{name} requires a block or a callable (got neither)")
                     end

          @steps << Step.new(name: name, callable: resolved, timeout: timeout)
        end

        def check(name, naming: nil, scope: nil, &block)
          if naming
            raise ArgumentError.new("check :#{name} requires a scope: for naming checks") unless scope

            @steps << Step.new(
              name: :"check_#{name}",
              callable: lambda do |data, ctx|
                entries = ctx.container.manifest.resolver.enumerate.select do |row|
                  Pattern.match?(scope, row[:key].to_s)
                end

                new_issues = check_naming(
                  entries,
                  pattern: naming,
                  code: "check.#{name}",
                  fix: "rename to match #{naming.inspect}",
                )
                existing_issues = Array(data&.dig("content", "issues"))
                issues = existing_issues + new_issues

                {
                  "content" => {
                    "ok" => issues.empty?,
                    "issues" => issues,
                    "count" => issues.size,
                  },
                }
              end,
              timeout: nil,
            )
          elsif block
            @steps << Step.new(
              name: :"check_#{name}",
              callable: lambda do |data, ctx|
                issues = block.call(ctx) || []
                existing_issues = Array(data&.dig("content", "issues"))
                all = existing_issues + issues

                {
                  "content" => {
                    "ok" => all.empty?,
                    "issues" => all,
                    "count" => all.size,
                  },
                }
              end,
              timeout: nil,
            )
          else
            raise ArgumentError.new("check :#{name} requires naming: or a block")
          end
        end

        def parallel(&)
          saved = @steps
          @steps = []
          instance_eval(&)
          parallel_steps = @steps.dup
          @steps = saved << Parallel.new(steps: parallel_steps)
        end

        # ── Output ──
        def publish(to: nil, template: nil, tree: nil, inject_boot: nil, &block)
          if block
            @publish_block = block
          elsif to || tree
            @publish_targets << PublishTarget.new(to: to, template: template, tree: tree, inject_boot: inject_boot)
          else
            raise ArgumentError.new("publish requires to: (file), tree:, or a block; use save to: for store keys")
          end
        end

        def save(to:)
          @save_key = to
        end

        def notify(key)
          @notify_keys << key
        end

        # ── Ordering ──
        def priority(n = nil)
          return @priority if n.nil?

          @priority = n.to_i
        end

        # ── Lifecycle ──
        def ttl(duration_string)
          @ttl = Textus::Value::Duration.seconds(duration_string)
        end

        def on_expire(action)
          actions = %i[drop archive]
          sym = action.to_s.to_sym
          raise ArgumentError.new("on_expire must be one of #{actions.join("|")}, got #{action.inspect}") unless actions.include?(sym)

          @on_expire = sym
        end

        # ── Matching (internal) ──
        def match?(key)
          return false unless @on_patterns&.any?

          @on_patterns.any? { |p| Pattern.match?(p, key) }
        end

        def multi_match?
          @on_patterns&.any? { |p| p.end_with?("**") }
        end
      end
    end
  end
end
