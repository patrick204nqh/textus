module Textus
  class Manifest
    class Policy
      module Predicates
        class LaneDeletableBy
          def self.call(manifest:, actor:, action:, key:, schemas: nil, envelope: nil, extra: {})
            return { pass: true } if key.nil?

            mentry = manifest.resolver.resolve(key).entry
            is_raw = mentry.lane.to_s == "raw"
            writers = manifest.policy.writers_for(mentry.lane.to_s)
            author_writers = manifest.policy.writers_for("knowledge")

            pass = if is_raw
                     author_writers.include?(actor.to_s)
                   else
                     writers.include?(actor.to_s) || author_writers.include?(actor.to_s)
                   end
            return { pass: true } if pass

            holders = (writers + author_writers).uniq
            { pass: false, error: Textus::WriteForbidden.new(mentry.key, mentry.lane, holders:) }
          rescue Textus::UnknownKey
            { pass: true }
          end
        end
      end
    end
  end
end
