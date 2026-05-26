module Textus
  class Manifest
    class Entry
      module Validators
        # Filled in as validators are added.
        REGISTERED = [].freeze

        def self.run_all(entry)
          REGISTERED.each { |v| v.call(entry) }
          nil
        end
      end
    end
  end
end
