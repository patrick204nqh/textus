module Textus
  class Store
    module Jobs
      class Base
        def self.inherited(subclass)
          super
          return unless subclass.name

          TracePoint.new(:end) do |tp|
            if tp.self == subclass
              Textus::Jobs.register(subclass)
              tp.disable
            end
          end.enable
        end

        def call(**)
          raise NotImplementedError.new("#{self.class}#call")
        end

        def args = {}
      end
    end
  end
end
