module Textus
  module Workflow
    module DSL
      Step = Data.define(:name, :callable, :timeout)
      Parallel = Data.define(:steps)
      PublishTarget = Data.define(:to, :template, :tree, :inject_boot)

      class Definition
        include Textus::Workflow::Helpers
        include StepBuilder
        include PatternMatcher
        include Lifecycle

        attr_reader :name, :steps, :on_patterns, :save_to, :notify_keys,
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
          @save_to             = nil
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

          @max_attempts = max_attempts_value(n)
        end

        # ── Trigger ──
        def on(*patterns)
          @on_patterns = patterns
        end

        # ── Steps ──
        def step(name, callable = nil, timeout: nil, &block)
          @steps << build_step(name, callable, timeout:, &block)
        end

        def check(name, naming: nil, scope: nil, &block)
          callable = build_check(name, naming:, scope:, &block)
          @steps << Step.new(name: :"check_#{name}", callable: callable, timeout: nil)
        end

        def parallel(&)
          saved = @steps
          @steps = []
          instance_eval(&)
          parallel_steps = @steps.dup
          @steps = saved << build_parallel(parallel_steps)
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
          @save_to = to
        end

        def notify(key)
          @notify_keys << key
        end

        # ── Ordering ──
        def priority(n = nil)
          return @priority if n.nil?

          @priority = priority_value(n)
        end

        # ── Lifecycle ──
        def every(cadence = :__no_arg__)
          @ttl = ttl_value(cadence)
        end

        alias ttl every

        def on_expire(action = :__no_arg__)
          @on_expire = expire_action(action)
        end

        # ── Matching (internal) ──
        def match?(key)
          return false unless @on_patterns&.any?

          @on_patterns.any? { |p| match_pattern?(p, key) }
        end

        def multi_match?
          @on_patterns&.any? { |p| p.end_with?("**") }
        end
      end
    end
  end
end
