module Textus
  module Protocol
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

      def match?(pattern, key)
        Matching.match?(pattern, key)
      end
    end
  end
end
