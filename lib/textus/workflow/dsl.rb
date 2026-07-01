module Textus
  module Workflow
    module DSL
      Step = Data.define(:name, :callable, :timeout)
      Parallel = Data.define(:steps)

      class Definition
        attr_reader :name, :steps, :match_pattern, :publish_block

        def initialize(name)
          @name          = name
          @steps         = []
          @match_pattern = nil
          @publish_block = nil
        end

        def match(pattern)
          @match_pattern = pattern
        end

        def step(name, callable_or_opt = nil, timeout: nil, &block)
          callable = if callable_or_opt.respond_to?(:call)
                       callable_or_opt
                     elsif block
                       block
                     else
                       raise ArgumentError.new("step :#{name} requires a block or a callable (got neither)")
                     end
          t = callable_or_opt.is_a?(Hash) ? callable_or_opt[:timeout] : timeout
          @steps << Step.new(name: name, callable: callable, timeout: t)
        end

        def parallel(&block)
          saved = @steps
          @steps = []
          instance_eval(&block)
          parallel_steps = @steps.dup
          @steps = saved << Parallel.new(steps: parallel_steps)
        end

        def publish(&block)
          @publish_block = block || :default
        end

        def match?(key)
          return false unless @match_pattern

          Pattern.match?(@match_pattern, key)
        end
      end
    end
  end
end
