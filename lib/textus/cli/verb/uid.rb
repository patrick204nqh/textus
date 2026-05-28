module Textus
  class CLI
    class Verb
      class Uid < Verb
        command_name "uid"
        parent_group Group::Key

        def call(store)
          key = positional.shift or raise UsageError.new("uid requires a key")
          emit({ "key" => key, "uid" => session_for(store).uid(key) })
        end
      end
    end
  end
end
