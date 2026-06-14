module Textus
  module Dispatch
    module Runtime
      class Watch
        def initialize(container:, call:)
          @container = container
          @call = call
          @queue = Textus::Ports::Queue.new(root: container.root)
        end

        def tick
          fire_scheduled_retention
          @queue.reclaim(now: Textus::Ports::Clock.new.now)
          Textus::Dispatch::Runtime::Worker.for(container: @container, queue: @queue).drain
        end

        def run(poll: nil)
          interval = poll || @container.manifest.data.worker_config[:poll]
          lock = Textus::Ports::WatcherLock.new(@container.root)
          lock.acquire
          begin
            loop do
              tick
              sleep(interval)
            end
          ensure
            lock.release
          end
        end

        private

        def fire_scheduled_retention
          event = Textus::Dispatch::Event.new(
            name: Textus::Dispatch::Catalog::Events::SCHEDULED_RETENTION,
            actor: Textus::Role::AUTOMATION,
            target: nil,
            payload: {},
            actions: [
              Textus::Action::Enqueue.new(
                type: "sweep",
                args: { "scope" => { "prefix" => nil, "lane" => nil } },
              ),
            ],
            correlation_id: SecureRandom.uuid,
          )
          Textus::Dispatch::Gate.new(@container).fire(event)
        end
      end
    end
  end
end
