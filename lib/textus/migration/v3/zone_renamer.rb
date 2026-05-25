require "fileutils"

module Textus
  module Migration
    module V3
      module ZoneRenamer
        def self.run(root:)
          inbox  = File.join(root, ".textus/zones/inbox")
          intake = File.join(root, ".textus/zones/intake")
          return unless Dir.exist?(inbox)

          raise "Refusing to migrate: both inbox/ and intake/ exist. Resolve manually." if Dir.exist?(intake)

          FileUtils.mv(inbox, intake)
        end
      end
    end
  end
end
