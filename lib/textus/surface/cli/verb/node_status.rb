module Textus
  module Surface
    class CLI
      class Verb
        class NodeStatus < Verb
          command_name "status"
          parent_group Group::Node

          def call(store)
            emit(store.node_status)
          end
        end
      end
    end
  end
end
