module Textus
  module Domain
    module Policy
      # Promotion evaluates a list of named predicates against a pending-proposal
      # entry and returns a Result indicating whether all requirements are met.
      class Promotion
        Result = Struct.new(:ok?, :reasons, keyword_init: true)

        REGISTRY = {
          "schema_valid" => -> { Predicates::SchemaValid.new },
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

        def evaluate(entry:, store:)
          reasons = []
          @predicates.each do |pred|
            ok = pred.call(entry: entry, store: store)
            reasons << "#{pred.name}: #{pred.reason || "predicate failed"}" unless ok
          end
          Result.new(ok?: reasons.empty?, reasons: reasons)
        end
      end
    end
  end
end
