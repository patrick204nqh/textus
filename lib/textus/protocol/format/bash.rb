module Textus
  module Protocol
    module Format
      class Bash < Script
        def self.extensions = [".sh"]
        def self.nested_ext(*) = ".sh"
      end
    end
  end
end
