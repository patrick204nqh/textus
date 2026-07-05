module Textus
  module Protocol
    module Format
      class Ruby < Script
        def self.extensions = [".rb"]
        def self.nested_ext(*) = ".rb"
      end
    end
  end
end
