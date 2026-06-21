module Textus
  class Store
    module Jobs
      class Base
        def call(**)
          raise NotImplementedError.new("#{self.class}#call")
        end

        def args = {}
      end
    end
  end
end
