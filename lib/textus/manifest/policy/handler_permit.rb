module Textus
  class Manifest
    class Policy
      class HandlerPermit
        attr_reader :handlers

        def initialize(handlers:)
          @handlers = Array(handlers).map(&:to_s).freeze
        end

        def permits?(handler)
          @handlers.include?(handler.to_s)
        end
      end
    end
  end
end
