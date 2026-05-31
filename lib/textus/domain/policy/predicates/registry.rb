# frozen_string_literal: true

module Textus
  module Domain
    module Policy
      module Predicates
        # The single source of truth for the predicate vocabulary
        # (ADR 0031 §3). Replaces both Promote::KNOWN and Promotion::REGISTRY.
        # Each entry is name => ->(params:, schemas:) { predicate }.
        module Registry
          ENTRIES = {
            "zone_writable_by" => ->(**) { ZoneWritableBy.new },
            "author_held" => ->(**) { AuthorHeld.new },
            "target_is_canon" => ->(**) { TargetIsCanon.new },
            "schema_valid" => ->(schemas:, **) { SchemaValid.new(schemas: schemas) },
            "etag_match" => ->(params:, **) { EtagMatch.new(if_etag: params) },
            "fresh_within" => ->(params:, **) { FreshWithin.new(duration: params) },
          }.freeze

          # Accepts either "name" or { "name" => params }.
          def self.build(spec, schemas:)
            name, params =
              if spec.is_a?(Hash)
                spec.first
              else
                [spec.to_s, nil]
              end
            ctor = ENTRIES[name.to_s] or raise Textus::UsageError.new(
              "unknown guard predicate: '#{name}' (known: #{ENTRIES.keys.join(", ")})",
            )
            ctor.call(params: params, schemas: schemas)
          end

          def self.known = ENTRIES.keys
        end
      end
    end
  end
end
