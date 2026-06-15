module Textus
  module Workflow
    module Pattern
      def self.match?(pattern, key)
        if pattern.end_with?(".**")
          prefix = pattern.delete_suffix(".**")
          key.start_with?("#{prefix}.")
        elsif pattern.end_with?(".*")
          prefix = pattern.delete_suffix(".*")
          suffix = key.delete_prefix("#{prefix}.")
          key != suffix && !suffix.include?(".")
        else
          key == pattern
        end
      end
    end
  end
end
