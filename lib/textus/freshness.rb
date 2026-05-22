require "time"

module Textus
  module Freshness
    module_function

    # Called by Reader when an envelope is stale. Applies the manifest's
    # on_stale policy. Returns the (possibly updated) envelope.
    def act_on_stale(store, mentry, key, envelope, role:)
      case mentry.on_stale
      when :warn
        envelope
      when :sync
        refresh_sync(store, key, envelope, role: role)
      when :timed_sync
        refresh_timed_sync(store, mentry, key, envelope, role: role)
      else
        envelope
      end
    end

    def refresh_sync(store, key, envelope, role:)
      Refresh.call(store, key, as: role)
      fresh = store.reader.read_raw_envelope(key)
      fresh ? fresh.merge("stale" => false, "stale_reason" => nil, "refreshing" => false) : envelope
    rescue Textus::Error => e
      envelope.merge("refresh_error" => e.message)
    end

    def refresh_timed_sync(store, _mentry, key, envelope, role:)
      # Placeholder — Task 11 implements timed_sync with fork+detach.
      refresh_sync(store, key, envelope, role: role)
    end

    # Returns :fresh, or { stale: true, reason: <string> }
    def evaluate(mentry, envelope)
      return :fresh if mentry.ttl.nil? || mentry.intake_handler.nil?

      last_str = envelope.dig("_meta", "last_refreshed_at")
      return { stale: true, reason: "never refreshed" } if last_str.nil?

      last = parse_time(last_str)
      return { stale: true, reason: "unparseable last_refreshed_at: #{last_str.inspect}" } if last.nil?

      ttl_seconds = parse_ttl(mentry.ttl)
      return :fresh if ttl_seconds.nil?

      age = Time.now - last
      return :fresh if age <= ttl_seconds

      { stale: true, reason: "ttl exceeded (age=#{age.to_i}s, ttl=#{ttl_seconds}s)" }
    end

    def parse_time(str)
      Time.parse(str.to_s)
    rescue StandardError
      nil
    end

    def parse_ttl(s)
      return nil if s.nil?

      str = s.to_s.strip
      return str.to_i if str.match?(/\A\d+\z/)

      m = str.match(/\A(\d+)\s*([smhd])\z/)
      return nil unless m

      n = m[1].to_i
      case m[2]
      when "s" then n
      when "m" then n * 60
      when "h" then n * 3600
      when "d" then n * 86_400
      end
    end
  end
end
