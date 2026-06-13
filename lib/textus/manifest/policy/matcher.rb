module Textus
  class Manifest
    class Policy
      module Matcher
        module_function

        def matches?(glob, key)
          glob_segs = glob.split(".")
          key_segs  = key.split(".")
          consume(glob_segs, key_segs)
        end

        def specificity(glob)
          glob.split(".").reduce(0) do |s, seg|
            s + case seg
                when "**" then 0
                when "*"  then 1
                else 10
                end
          end
        end

        def pick_most_specific(globs, key:)
          matching = globs.select { |g| matches?(g, key) }
          return nil if matching.empty?

          matching.max_by { |g| [specificity(g), -g.length, g] }
        end

        def self.consume(glob_segs, key_segs)
          return key_segs.empty? if glob_segs.empty?

          head = glob_segs.first
          rest = glob_segs[1..]

          if head == "**"
            return true if rest.empty?

            (0..key_segs.length).any? { |i| consume(rest, key_segs[i..]) }
          elsif key_segs.empty?
            false
          elsif head == "*" || head == key_segs.first
            consume(rest, key_segs[1..])
          else
            false
          end
        end
      end
    end
  end
end
