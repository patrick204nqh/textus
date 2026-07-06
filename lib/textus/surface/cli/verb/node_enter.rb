module Textus
  module Surface
    class CLI
      class Verb
        class NodeEnter < Verb
          command_name "enter"
          parent_group Group::Node

          def call(store)
            path = positional
            raise UsageError.new("node enter requires a path (e.g. evidence)") if path.empty?

            entry = store.node_enter(path)
            emit({
              "action" => "entered",
              "path" => entry.path.map(&:to_s),
              "entered_at" => entry.entered_at.iso8601,
            })
          end
        end
      end
    end
  end
end
