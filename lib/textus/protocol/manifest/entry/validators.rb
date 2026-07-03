module Textus
  module Protocol
  class Manifest
    class Entry
      module Validators
        REGISTERED = [
          Publish,
          FormatMatrix,
        ].freeze

        def self.run_all(entry, policy:)
          REGISTERED.each { |v| v.call(entry, policy: policy) }
          nil
        end
      end
    end
  end
  end
end
