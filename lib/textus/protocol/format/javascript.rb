module Textus
  module Protocol
    module Format
      class Javascript < Script
        def self.extensions = [".js"]
        def self.nested_ext(*) = ".js"
      end
    end
  end
end
