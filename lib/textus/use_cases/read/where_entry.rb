module Textus
  module UseCases
    module Read
      class WhereEntry < Base
        handles Dispatch::Contracts::WhereEntry
        needs :manifest

        def call
          res = @manifest.resolver.resolve(@command.key)
          mentry = res.entry
          success("protocol" => Textus::PROTOCOL, "key" => @command.key,
                  "lane" => mentry.lane, "path" => res.path)
        end
      end
    end
  end
end
