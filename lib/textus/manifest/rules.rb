module Textus
  class Manifest
    class Rules
      # Every structural member here derives from Schema::FIELD_REGISTRY (WS3),
      # so a new rule field is added in one place. `in_pick` selects the fields
      # that participate in the most-specific `for(key)` resolution.
      PICK_FIELDS = Schema::FIELD_REGISTRY.select { |_, m| m[:in_pick] }.keys.freeze

      RuleSet = ::Data.define(*PICK_FIELDS)
      EMPTY_SET = RuleSet.new(**PICK_FIELDS.to_h { |f| [f, nil] })

      def self.parse(raw)
        new(Array(raw).map { |b| Block.new(b) })
      end

      def initialize(blocks)
        @blocks = blocks
      end

      attr_reader :blocks

      def for(key)
        for_with_trace(key).first
      end

      def for_with_trace(key)
        candidates = @blocks.map do |b|
          matched     = Textus::Manifest::Policy::Matcher.matches?(b.match, key)
          specificity = matched ? Textus::Manifest::Policy::Matcher.specificity(b.match) : 0
          { "pattern" => b.match, "matched" => matched, "specificity" => specificity }
        end

        winning_blocks = @blocks
                         .select { |b| Textus::Manifest::Policy::Matcher.matches?(b.match, key) }
                         .sort_by { |b| [-Textus::Manifest::Policy::Matcher.specificity(b.match), b.match.length, b.match] }

        ruleset = build_ruleset_from(winning_blocks, key)

        trace = Manifest::RuleTrace.new(
          key:,
          candidates:,
          winners: winning_blocks.map do |b|
            {
              "pattern" => b.match,
              "specificity" => Textus::Manifest::Policy::Matcher.specificity(b.match),
              "fields" => PICK_FIELDS.each_with_object({}) { |f, h| h[f.to_s] = b.public_send(f) if b.public_send(f) },
            }
          end,
          ruleset_fields: ruleset.to_h,
        )

        [ruleset, trace]
      end

      def explain(key)
        @blocks.select { |b| Textus::Manifest::Policy::Matcher.matches?(b.match, key) }
      end

      private

      def build_ruleset_from(_winning_blocks, key)
        slots = PICK_FIELDS.to_h { |f| [f, []] }
        @blocks.each do |b|
          next unless Textus::Manifest::Policy::Matcher.matches?(b.match, key)

          slots.each_key { |slot| slots[slot] << b if b.public_send(slot) }
        end
        RuleSet.new(**slots.to_h { |slot, blocks| [slot, pick(blocks, slot, key)] })
      end

      def pick(blocks, slot, key)
        return nil if blocks.empty?

        globs = blocks.map(&:match)
        winning = Textus::Manifest::Policy::Matcher.pick_most_specific(globs, key: key)
        blocks.find { |b| b.match == winning }&.public_send(slot)
      end

      class Block
        attr_reader :match, *Schema::FIELD_REGISTRY.keys

        def initialize(raw)
          @match = raw["match"] or raise Textus::UsageError.new("rule block missing match:")
          Schema::FIELD_REGISTRY.each do |field, meta|
            instance_variable_set("@#{field}", parse_field(meta, raw[meta[:yaml_key]]))
          end
        end

        private

        # One dispatch over the registry, replacing the four bespoke parse_*
        # methods. :deferred carries the raw Hash after a shape check (its
        # contents validate later — guard predicates at Dispatch::Auth check time,
        # ADR 0031); :immediate instantiates the policy class now. :tagged passes
        # the raw Hash straight to a policy class that is a tagged union and
        # dispatches on its discriminator field (e.g. upkeep's on:). A mapping
        # field (sub_keys) splats its nested keys as kwargs; a scalar/array
        # field passes its raw value under arg_key.
        def parse_field(meta, value)
          return nil if value.nil?

          if meta[:validation] == :deferred
            raise Textus::BadManifest.new("#{meta[:yaml_key]}: must be a map of transition => [predicates]") unless value.is_a?(Hash)

            return value
          end

          return meta[:policy_class].new(value) if meta[:validation] == :tagged

          if meta[:sub_keys]
            meta[:policy_class].new(**meta[:sub_keys].to_h { |k| [k.to_sym, value[k]] })
          else
            meta[:policy_class].new(meta[:arg_key] => value)
          end
        end
      end
    end
  end
end
