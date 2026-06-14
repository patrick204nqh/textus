# frozen_string_literal: true

require "time"

module Textus
  module Dispatch
    module Actions
      class Pulse
        class Scanner
          def initialize(prefix: nil, lane: nil)
            @prefix = prefix
            @lane   = lane
          end

          def call(container:, call:)
            @container  = container
            @call       = call
            @manifest   = container.manifest
            @file_store = container.file_store

            rows = []
            @manifest.data.entries.each do |mentry|
              next if @prefix && !mentry.key.start_with?(@prefix)
              next if @lane   && mentry.lane != @lane

              rows << row_for(mentry)
            end
            rows
          end

          private

          def row_for(mentry)
            envelope = safe_get(mentry.key)
            last = envelope&.meta&.dig("last_fetched_at")
            ttl, action = policy_for(mentry)
            return base_row(mentry, last).merge(status: :no_policy) if ttl.nil?

            basis = basis_for(mentry)
            expired = expired?(mentry, basis, ttl)
            base_row(mentry, last).merge(
              ttl_seconds: ttl,
              action: action,
              status: expired ? :expired : :fresh,
              next_due_at: basis.nil? ? nil : (basis + ttl).utc.iso8601,
            )
          end

          def policy_for(mentry)
            if mentry.intake?
              ttl = mentry.source.ttl_seconds
              return [ttl, :refresh] unless ttl.nil?
            end
            ret = @manifest.rules.for(mentry.key).retention
            return [ret.ttl_seconds, ret.action] unless ret.nil?

            [nil, nil]
          end

          def basis_for(mentry)
            return evaluator.intake_basis(mentry) if mentry.intake? && mentry.source.ttl_seconds

            mtime_for(mentry.key)
          end

          def expired?(mentry, basis, ttl)
            if mentry.intake? && mentry.source.ttl_seconds
              evaluator.verdict(mentry).stale
            else
              basis.nil? || Textus::Core::Retention::Sweep.expired?(ttl_seconds: ttl, mtime: basis, now: @call.now)
            end
          end

          def evaluator
            @evaluator ||= Textus::Core::Freshness::Evaluator.new(
              manifest: @manifest,
              file_stat: Textus::Ports::Storage::FileStat.new,
              clock: @call,
            )
          end

          def mtime_for(key)
            path = @manifest.resolver.resolve(key).path
            @file_store.exists?(path) ? Textus::Ports::Storage::FileStat.new.mtime(path) : nil
          rescue Textus::Error
            nil
          end

          def base_row(mentry, last)
            {
              key: mentry.key,
              lane: mentry.lane,
              last_fetched_at: last,
              age_seconds: last ? (@call.now - Time.parse(last)).to_i : nil,
            }
          end

          def safe_get(key)
            res = @manifest.resolver.resolve(key)
            return nil unless @file_store.exists?(res.path)

            raw = @file_store.read(res.path)
            parsed = Textus::Entry.for_format(res.entry.format).parse(raw, path: res.path)
            Textus::Envelope.build(
              key: key,
              mentry: res.entry,
              path: res.path,
              meta: parsed["_meta"],
              body: parsed["body"],
              etag: Textus::Etag.for_bytes(raw),
              content: parsed["content"],
            )
          rescue Textus::Error
            nil
          end
        end
      end
    end
  end
end
