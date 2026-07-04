module Textus
  module Protocol
    module Events
      class Consumer
        def drain(event_store:, registry:, container:, call:)
          queue = Async::Queue.new(event_store)
          completed = 0
          failed = 0

          loop do
            row = queue.consume_one(registry:, container:, call:)
            break unless row

            if row[:state] == "done"
              completed += 1
            elsif row[:state] == "failed"
              failed += 1
            end
          end

          { completed:, failed: }
        end
      end
    end
  end
end
