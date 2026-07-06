module Textus
  module Surface
    class CLI
      class Verb
        class NodeBack < Verb
          command_name "back"
          parent_group Group::Node

          def call(store)
            entry = store.back_node
            current = store.current_node
            emit({
              "action" => "back",
              "popped" => entry.path.map(&:to_s),
              "current" => current&.path&.map(&:to_s),
            })
          end
        end
      end
    end
  end
end
