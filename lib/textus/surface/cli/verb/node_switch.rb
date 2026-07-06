module Textus
  module Surface
    class CLI
      class Verb
        class NodeSwitch < Verb
          command_name "switch"
          parent_group Group::Node

          def call(store)
            path = positional
            raise UsageError.new("node switch requires a path (e.g. evidence)") if path.empty?

            entry = store.switch_node(path)
            emit({
              "action" => "switched",
              "path" => entry.path.map(&:to_s),
              "entered_at" => entry.entered_at.iso8601,
            })
          end
        end
      end
    end
  end
end
