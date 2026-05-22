require "time"

module Textus
  module Freshness
    module_function

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
