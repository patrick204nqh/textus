module Textus
  class CLI
    class Verb
      class Uid < Runner::Base
        self.spec = Textus::Read::Uid.contract
        parent_group Group::Key

        def invoke(store)
          key = positional.shift or raise UsageError.new("uid requires a key")
          emit({ "key" => key, "uid" => session_for(store).uid(key) })
        end
      end
    end
  end
end
