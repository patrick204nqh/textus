require "timeout"

module Textus
  module Produce
    module Acquire
      # Internal ingest executor for one machine-zone intake entry. No longer a
      # public verb (ADR 0079 collapsed the `fetch` surface): used by the
      # `reconcile` sweep and `textus hook run` only — ingest is system-pushed
      # (ADR 0089 removed the read-through that once also drove it).
      class Intake
        FETCH_TIMEOUT_SECONDS = Textus::Produce::Acquire::Handler::FETCH_TIMEOUT_SECONDS

        def initialize(container:, call:)
          @container    = container
          @call         = call
          @manifest     = container.manifest
          @schemas      = container.schemas
          @rpc          = container.rpc
        end

        # call(key) is the primary entry; run is kept as an alias for
        # Orchestrator and FetchAll which call worker.run(key).
        def call(key)
          run(key)
        end

        def run(key)
          res = @manifest.resolver.resolve(key)
          mentry = res.entry
          path = res.path
          remaining = res.remaining
          raise UsageError.new("no intake declared for '#{key}'") unless mentry.intake?

          before_etag = @container.file_store.exists?(path) ? @container.file_store.etag(path) : nil
          result = fetch_with_events(key, mentry, remaining)
          persist_and_notify(key, mentry, result, before_etag)
        end

        def self.normalize_action_result(res, format:)
          res = res.transform_keys(&:to_s) if res.is_a?(Hash)
          res ||= {}
          meta_val = res["_meta"]
          body     = res["body"]
          content  = res["content"]

          case format
          when "markdown" then { meta: meta_val || {}, body: body.to_s, content: nil }
          when "text"     then { meta: {}, body: body.to_s, content: nil }
          when "json", "yaml"
            if !content.nil?
              { meta: meta_val || {}, body: nil, content: content }
            elsif !body.nil?
              { meta: {}, body: body.to_s, content: nil }
            else
              raise Textus::UsageError.new("intake for #{format} returned neither content nor body")
            end
          else
            raise Textus::UsageError.new("unknown format #{format.inspect}")
          end
        end

        private

        def fetch_events
          @fetch_events ||= Textus::Produce::Events.from(container: @container, call: @call)
        end

        # ADR 0079: a per-rule fetch_timeout_seconds override was an accepted loss
        # in the fetch:/retention: → lifecycle: collapse; the constant ceiling
        # applies to every intake.
        def fetch_timeout_for(_key)
          FETCH_TIMEOUT_SECONDS
        end

        def fetch_with_events(key, mentry, remaining)
          fetch_events.started(key)
          call_intake(key, mentry, remaining)
        end

        def call_intake(key, mentry, remaining)
          Textus::Produce::Acquire::Handler.invoke(
            caps: @container, handler: mentry.handler,
            config: mentry.config,
            args: { trigger_key: key, leaf_segments: remaining || [] },
            label: "intake", timeout: fetch_timeout_for(key)
          )
        rescue Textus::Error => e
          fetch_events.failed(key, e)
          raise
        rescue StandardError => e
          fetch_events.failed(key, e)
          raise UsageError.new("intake '#{mentry.handler}' raised: #{e.class}: #{e.message}")
        end

        def persist_and_notify(key, mentry, result, before_etag)
          normalized = self.class.normalize_action_result(result, format: mentry.format)
          Textus::Domain::Policy::GuardFactory.new(
            manifest: @manifest, schemas: @schemas,
          ).for(:reconcile, key).check!(
            Textus::Domain::Policy::Evaluation.new(
              actor: @call.role, transition: :reconcile, origin: nil,
              target: key, envelope: nil, manifest: @manifest
            ),
          )
          envelope = writer.put(
            key,
            mentry: mentry,
            payload: Textus::Envelope::IO::Writer::Payload.new(
              meta: normalized[:meta], body: normalized[:body], content: normalized[:content],
            ),
          )
          change = detect_change(before_etag, envelope)
          fetch_events.fetched(key, envelope, change)
          envelope
        end

        def detect_change(before_etag, envelope)
          if before_etag.nil? then :created
          elsif envelope.etag == before_etag then :unchanged
          else :updated
          end
        end

        def writer
          @writer ||= Textus::Envelope::IO::Writer.from(container: @container, call: @call)
        end
      end
    end
  end
end
