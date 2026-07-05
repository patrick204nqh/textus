module Textus
  module Protocol
    module Format
      class Python < Script
        def self.extensions = [".py"]
        def self.nested_ext(*) = ".py"
      end
    end
  end
end
