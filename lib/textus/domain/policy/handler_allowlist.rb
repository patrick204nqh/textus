module Textus
  module Domain
    module Policy
      class HandlerAllowlist
        attr_reader :handlers

        def initialize(handlers:)
          @handlers = Array(handlers).map(&:to_s).freeze
        end

        def allows?(handler)
          @handlers.include?(handler.to_s)
        end
      end
    end
  end
end
