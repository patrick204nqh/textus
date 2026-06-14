# frozen_string_literal: true

require "securerandom"

module Textus
  module Surfaces
    class Watcher
      def initialize(container:)
        @container = container
        @queue = Textus::Ports::Queue.new(root: container.root)
      end

      def tick
        self.class.seed_scheduled_jobs(@container, @queue)
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

      def self.seed_scheduled_jobs(container, queue)
        call_obj = Textus::Call.build(role: Textus::Role::AUTOMATION)
        queue.enqueue(Textus::Core::Jobs::Job.new(
                        type: "sweep",
                        args: { "scope" => { "prefix" => nil, "lane" => nil } },
                        enqueued_by: call_obj.role,
                      ))
        Textus::Core::Freshness::Evaluator.new(
          manifest: container.manifest,
          file_stat: Textus::Ports::Storage::FileStat.new,
          clock: Textus::Ports::Clock.new,
        ).stale_intake_keys(prefix: nil, lane: nil).each do |key|
          queue.enqueue(Textus::Core::Jobs::Job.new(
                          type: "refresh", args: { "key" => key }, enqueued_by: call_obj.role,
                        ))
        end
      rescue StandardError => e
        warn "[Textus::Surfaces::Watcher] seed error: #{e.message}"
      end
    end
  end
end
