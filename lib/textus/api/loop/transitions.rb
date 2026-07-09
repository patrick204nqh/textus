module Textus
  class API
    class Loop
      module Transitions
        REFLECTION_NODES = %i[intent evidence].freeze

        module_function

        def allowed?(from_path, to_path, node_names:)
          from_node = from_path&.first
          to_node = to_path&.first
          return true if from_node.nil?
          return true if forward_jump?(from_node, to_node, node_names)
          return true if backward_to_reflection_node?(to_node)

          false
        end

        def validate!(from_path, to_path, node_names:)
          return if allowed?(from_path, to_path, node_names:)

          from_node = from_path&.first
          to_node = to_path&.first
          raise Textus::UsageError.new(
            "invalid node transition: #{from_node} \u2192 #{to_node}. " \
            "Forward jumps are always allowed; backward jumps only to intent or evidence.",
          )
        end

        def forward_jump?(from_node, to_node, node_names)
          idx_from = node_names.index(from_node) || node_names.size
          idx_to = node_names.index(to_node) || node_names.size
          idx_to >= idx_from
        end

        def backward_to_reflection_node?(to_node)
          REFLECTION_NODES.include?(to_node)
        end
      end
    end
  end
end
