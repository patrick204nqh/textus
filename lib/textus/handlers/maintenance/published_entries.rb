module Textus
  module Handlers
    module Maintenance
      module PublishedEntries
        HANDLES = Dispatch::Contracts::PublishedEntries
        NEEDS   = %i[manifest].freeze

        def self.call(_command, _call, deps)
          Value::Result.success(deps.manifest.data.entries.reject { |entry| entry.publish_to.empty? }.map do |entry|
            { "key" => entry.key, "publish_to" => entry.publish_to }
          end)
        end
      end
    end
  end
end
