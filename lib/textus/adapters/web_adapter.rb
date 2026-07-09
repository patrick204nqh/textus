module Textus
  module Adapters
    class WebAdapter
      def initialize(api:)
        @api = api
      end

      def call(action, params: {}, session:)
        @api.send(action, **params, session:)
      end
    end
  end
end
