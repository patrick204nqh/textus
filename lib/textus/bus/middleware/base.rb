module Textus
  module Bus
    module Middleware
      class Base
        def self.inherited(subclass)
          super
          subclass.instance_variable_set(:@middleware_name, nil)
        end

        class << self
          def middleware_name(name = nil)
            if name
              @middleware_name = name.to_s
            else
              @middleware_name || name.split("::").last.downcase
            end
          end
        end

        def call(container:, command:, call:, next_handler:)
          raise NotImplementedError
        end
      end
    end
  end
end
