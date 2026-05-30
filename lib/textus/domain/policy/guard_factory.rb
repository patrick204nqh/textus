# frozen_string_literal: true

module Textus
  module Domain
    module Policy
      # Builds the effective Guard for (transition, key): base floor ++
      # the predicates declared under rules[].guard[transition]. The single
      # place the closed floor and the open ceiling are composed.
      class GuardFactory
        def initialize(manifest:, schemas:, extra: {})
          @manifest = manifest
          @schemas  = schemas
          @extra    = extra # transient per-call params, e.g. { if_etag: "..." }
        end

        def for(transition, key)
          specs = BaseGuards.for(transition) + composed(transition, key)
          predicates = specs.map { |spec| build(spec) }.uniq(&:name)
          Guard.new(predicates)
        end

        private

        def composed(transition, key)
          guard_map = @manifest.rules.for(key).guard
          return [] if guard_map.nil?

          Array(guard_map[transition.to_s])
        end

        def build(spec)
          # etag_match takes a per-call param rather than a manifest one.
          return Predicates::EtagMatch.new(if_etag: @extra[:if_etag]) if spec == "etag_match"

          Predicates::Registry.build(spec, schemas: @schemas)
        end
      end
    end
  end
end
