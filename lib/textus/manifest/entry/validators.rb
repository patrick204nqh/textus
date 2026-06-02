module Textus
  class Manifest
    class Entry
      module Validators
        REGISTERED = [
          Events,
          Publish,
          InjectBoot,
          Ignore,
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
