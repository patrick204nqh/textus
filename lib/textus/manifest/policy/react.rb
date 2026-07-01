module Textus
  class Manifest
    class Policy
      class React
        ALLOWED_KEYS = %w[on when do scope budget idempotency observe priority].freeze

        attr_reader :raw

        def initialize(raw:)
          raise Textus::BadManifest.new("react: must be a map") unless raw.is_a?(Hash)

          raw = raw.each_with_object({}) do |(key, value), out|
            normalized = key == true ? "on" : key.to_s
            out[normalized] = value
          end
          raise Textus::BadManifest.new("react.ttl is invalid; ttl belongs only to source.ttl or retention.ttl") if raw.key?("ttl")

          unknown = raw.keys - ALLOWED_KEYS
          raise Textus::BadManifest.new("react: unknown key(s): #{unknown.join(", ")}") unless unknown.empty?

          Array(raw["on"]).each { |trigger| Textus::Manifest::TriggerCatalog.validate_trigger!(trigger) }
          Array(raw["do"]).each { |action| Textus::Manifest::TriggerCatalog.validate_action!(action) }

          @raw = raw
        end

        def to_h
          @raw
        end
      end
    end
  end
end
