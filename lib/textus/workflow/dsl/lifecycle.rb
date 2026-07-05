module Textus
  module Workflow
    module DSL
      module Lifecycle
        VALID_EXPIRE_ACTIONS = %i[drop archive].freeze

        def ttl_value(cadence)
          return nil if cadence == :__no_arg__

          Textus::Value::Duration.seconds(cadence)
        end

        def expire_action(action = :__no_arg__)
          return nil if action == :__no_arg__

          sym = action.to_s.to_sym
          raise ArgumentError.new("on_expire must be one of drop|archive, got #{action.inspect}") unless VALID_EXPIRE_ACTIONS.include?(sym)

          sym
        end

        def max_attempts_value(n)
          n.to_i
        end

        def priority_value(n)
          n.to_i
        end
      end
    end
  end
end
