module Textus
  module UseCases
    module Read
      class DepsEntry < Base
        handles Dispatch::Contracts::DepsEntry
        needs :manifest

        def call
          entry = @manifest.data.entries.find { |e| e.key == @command.key }
          deps_list = entry&.external? ? Array(entry.source&.sources).compact : []
          success("key" => @command.key, "deps" => deps_list.uniq)
        end
      end
    end
  end
end
