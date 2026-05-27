module Textus
  module Application
    module Policy
      # Promotion evaluates a list of named predicates against a pending-proposal
      # entry and returns a Result indicating whether all requirements are met.
      #
      # Lives in Application because the predicates it wires up read live state
      # from explicit ports (schemas, manifest, role). The Domain-side rule
      # statement ("this policy requires predicates X and Y") is captured by
      # Textus::Domain::Policy::Promote.
      class Promotion
        Result = Struct.new(:ok?, :reasons, keyword_init: true)

        REGISTRY = {
          "schema_valid" => -> { Predicates::SchemaValid.new },
          "accept_authority_signed" => -> { Predicates::HumanAccept.new },
          # Legacy alias — kept so manifests written against the pre-0.20.1
          # vocabulary keep resolving. The Domain Promote DSL normalizes the
          # symbol; this entry covers callers that pass the raw string.
          "human_accept" => -> { Predicates::HumanAccept.new },
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
            pred.call(role: role, entry: entry)
          else
            # Default shape: schema-style predicates that need entry + schemas + manifest.
            pred.call(entry: entry, schemas: schemas, manifest: manifest)
          end
        end
      end
    end
  end
end
