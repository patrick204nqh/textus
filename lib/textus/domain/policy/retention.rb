module Textus
  module Domain
    module Policy
      # Lifetime policy for queue/quarantine leaves. Both windows are optional
      # durations (see Domain::Duration). `expire_after` deletes; `archive_after`
      # moves the leaf aside. When both are set, expire wins once its (longer)
      # window is exceeded.
      class Retention
        attr_reader :expire_after, :archive_after

        def initialize(expire_after: nil, archive_after: nil)
          @expire_after  = Textus::Domain::Duration.seconds(expire_after)
          @archive_after = Textus::Domain::Duration.seconds(archive_after)
        end

        # :expire | :archive | nil for a leaf of the given age (seconds).
        def action_for(age_seconds)
          return :expire  if @expire_after  && age_seconds > @expire_after
          return :archive if @archive_after && age_seconds > @archive_after

          nil
        end
      end
    end
  end
end
