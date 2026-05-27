require_relative "predicates/schema_valid"
require_relative "predicates/accept_authority_signed"

module Textus
  module Application
    module Policy
      class Promotion
        Result = Struct.new(:ok?, :reasons, keyword_init: true)

        REGISTRY = {
          "schema_valid" => -> { Predicates::SchemaValid.new },
          "accept_authority_signed" => -> { Predicates::AcceptAuthoritySigned.new },
          # Legacy alias — pre-0.20.1 manifests / callers passing the raw string.
          # Domain::Policy::Promote already normalizes the symbol form.
          "human_accept" => -> { Predicates::AcceptAuthoritySigned.new },
        }.freeze

        def self.from_names(names)
          predicates = Array(names).map do |n|
            ctor = REGISTRY[n.to_s] or raise Textus::UsageError.new(
              "unknown promotion predicate: '#{n}' (known: #{REGISTRY.keys.join(", ")})",
            )
            ctor.call
          end
          new(predicates: predicates)
        end

        attr_reader :predicates

        def initialize(predicates:)
          @predicates = predicates
        end

        def predicate_names
          @predicates.map(&:name)
        end

        def evaluate(entry:, schemas:, manifest:, role:)
          reasons = []
          @predicates.each do |pred|
            ok = invoke(pred, entry: entry, schemas: schemas, manifest: manifest, role: role)
            reasons << "#{pred.name}: #{pred.reason || "predicate failed"}" unless ok
          end
          Result.new(ok?: reasons.empty?, reasons: reasons)
        end

        private

        def invoke(pred, entry:, schemas:, manifest:, role:)
          case pred.name
          when "accept_authority_signed"
            pred.call(role: role, manifest: manifest, entry: entry)
          else
            pred.call(entry: entry, schemas: schemas, manifest: manifest)
          end
        end
      end
    end
  end
end
