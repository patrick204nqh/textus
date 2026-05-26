module Textus
  module Domain
    class Freshness
      Verdict = Data.define(:fresh, :reason) do
        def self.fresh         = new(fresh: true, reason: nil)
        def self.stale(reason) = new(fresh: false, reason: reason)
        def fresh? = fresh
        def stale? = !fresh
      end
    end
  end
end
