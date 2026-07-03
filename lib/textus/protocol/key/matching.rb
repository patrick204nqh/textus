module Textus
  module Protocol
    module Key
      module Matching
        module_function

        def matches_prefix?(key, prefix, nested: false)
          return true if key == prefix || key.start_with?("#{prefix}.")

          nested && prefix.start_with?("#{key}.")
        end

        def match?(pattern, key)
          segs = pattern.split(".")
          key_segs = key.split(".")
          return false if segs.length != key_segs.length

          segs.zip(key_segs).all? { |p, k| p == "*" || p == k }
        end
      end
    end
  end
end
