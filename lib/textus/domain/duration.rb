module Textus
  module Domain
    # Parses a duration value into whole seconds. Accepts a bare integer (or
    # integer-string) of seconds, or `<n><unit>` with unit s/m/h/d. Returns
    # nil for nil or any unparseable value.
    module Duration
      UNIT_SECONDS = { "s" => 1, "m" => 60, "h" => 3600, "d" => 86_400 }.freeze

      def self.seconds(value)
        return nil if value.nil?

        str = value.to_s.strip
        return str.to_i if str.match?(/\A\d+\z/)

        m = str.match(/\A(\d+)\s*([smhd])\z/)
        return nil unless m

        m[1].to_i * UNIT_SECONDS.fetch(m[2])
      end
    end
  end
end
