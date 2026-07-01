module Textus
  module Domain
    module Key
      module_function

      Resolution = ::Data.define(:entry, :remaining)

      def resolve(key, entries)
        entry = entries.find { |e| e.key == key }
        return Resolution.new(entry:, remaining: []) if entry

        candidates = entries.select { |e| e.nested? && key.start_with?("#{e.key}.") }
        return nil if candidates.empty?

        best = candidates.max_by { |e| e.key.length }
        tail = key.delete_prefix("#{best.key}.")
        Resolution.new(entry: best, remaining: tail.split("."))
      end

      def suggestions_for(key, entries, limit: 5)
        candidates = entries.map(&:key)
        distances = candidates.map { |ck| [ck, distance(ck, key)] }
        distances.sort_by(&:last)
                 .reject { |_k, d| d > 3 }
                 .first(limit)
                 .map(&:first)
      end

      def distance(left, right)
        Textus::Key::Distance.call(left, right)
      end

      def match?(pattern, key)
        Textus::Key::Matching.match?(pattern, key)
      end
    end
  end
end
