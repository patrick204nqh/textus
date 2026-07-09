module Textus
  module Adapters
    Response = Data.define(:payload, :error) do
      def success? = error.nil?
    end
  end
end
