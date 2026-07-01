module Textus
  module Handlers
    module Read
      module DepsEntry
        HANDLES = Dispatch::Contracts::DepsEntry
        NEEDS   = %i[manifest].freeze

        def self.call(command, _call, deps)
          entry = deps.manifest.data.entries.find { |e| e.key == command.key }
          deps_list = entry&.external? ? Array(entry.source&.sources).compact : []
          Value::Result.success("key" => command.key, "deps" => deps_list.uniq)
        end
      end
    end
  end
end
