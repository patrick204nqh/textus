module Textus
  module Key
    module Grammar
      SEGMENT = /\A[a-z0-9][a-z0-9-]*\z/
      MAX_SEGMENTS = 8
      MAX_SEGMENT_LEN = 64

      module_function

      def validate!(key) # rubocop:disable Naming/PredicateMethod
        raise UsageError.new("key must be a String") unless key.is_a?(String)
        raise UsageError.new("empty key") if key.empty?

        segs = key.split(".")
        raise UsageError.new("key '#{key}' has #{segs.length} segments (max #{MAX_SEGMENTS})") if segs.length > MAX_SEGMENTS

        segs.each do |seg|
          if seg.empty?
            raise UsageError.new("empty segment in key '#{key}'")
          elsif seg.length > MAX_SEGMENT_LEN
            raise UsageError.new("segment '#{seg}' in key '#{key}' exceeds #{MAX_SEGMENT_LEN} chars")
          elsif !seg.match?(SEGMENT)
            raise UsageError.new(
              "invalid key segment '#{seg}' in '#{key}': must match [a-z0-9][a-z0-9-]* " \
              "(lowercase, digits, hyphens; no underscores or uppercase)",
            )
          end
        end
        true
      end
    end
  end
end
