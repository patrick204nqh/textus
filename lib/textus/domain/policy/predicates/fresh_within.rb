# frozen_string_literal: true

require "time"

module Textus
  module Domain
    module Policy
      module Predicates
        # Parameterized predicate: the entry must have been written within
        # `duration` of now. Duration strings ("1h", "30m", "7d") parse via
        # Domain::Duration.seconds. Passes when no envelope exists yet.
        class FreshWithin
          attr_reader :reason

          def initialize(duration:, now: nil)
            @seconds = Textus::Domain::Duration.seconds(duration)
            @now = now
          end

          def name = "fresh_within"

          def call(eval)
            return true if eval.envelope.nil? || @seconds.nil?

            written = written_at(eval.envelope)
            return true if written.nil?

            now = @now || Textus::Ports::Clock.now
            return true if now - written <= @seconds

            @reason = "entry older than #{@seconds}s (written #{written.iso8601})"
            false
          end

          private

          # Domain-pure: reads the stored write timestamp from the envelope's
          # freshness (checked_at) or meta (last_fetched_at/generated_at) and
          # parses the stored ISO-8601 string. Parsing a stored string is not
          # I/O (allowed in domain, ADR 0024).
          def written_at(envelope)
            raw = envelope.freshness&.checked_at ||
                  envelope.meta&.dig("last_fetched_at") ||
                  envelope.meta&.dig("generated_at")
            return raw if raw.is_a?(Time)
            return nil if raw.nil?

            begin
              Time.parse(raw.to_s)
            rescue StandardError
              nil
            end
          end
        end
      end
    end
  end
end
