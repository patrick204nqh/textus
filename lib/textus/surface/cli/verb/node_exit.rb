module Textus
  module Surface
    class CLI
      class Verb
        class NodeExit < Verb
          command_name "exit"
          parent_group Group::Node

          def call(store)
            entry = store.node_exit
            emit({
              "action" => "exited",
              "path" => entry.path.map(&:to_s),
              "entered_at" => entry.entered_at.iso8601,
              "duration_s" => entry.duration,
            })
          end
        end
      end
    end
  end
end
