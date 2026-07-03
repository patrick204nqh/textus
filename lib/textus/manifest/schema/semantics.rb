# frozen_string_literal: true

module Textus
  class Manifest
    module Schema
      # Cross-field checks called by Validator.validate!
      # AFTER the structural dry-schema Contract passes. Operates on the raw hash.
      module Semantics
        module_function

        def check!(raw); end

        def walk(raw, allowed, path)
          raw.each_key do |k|
            raise BadManifest.new("unknown key '#{k}' at '#{path}'") unless allowed.include?(k)
          end
        end
      end
    end
  end
end
