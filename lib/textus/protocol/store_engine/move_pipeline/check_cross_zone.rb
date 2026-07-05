module Textus
  module Protocol
    class StoreEngine
      module MovePipeline
        module CheckCrossZone
          def self.call(ctx, _deps)
            return ctx if ctx.from_entry.lane == ctx.to_entry.lane

            raise UsageError.new("cross-zone moves forbidden (#{ctx.from_entry.lane} → #{ctx.to_entry.lane})")
          end
        end
      end
    end
  end
end
