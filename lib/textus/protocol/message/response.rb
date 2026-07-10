module Textus
  module Protocol
    module Message
      Response = Data.define(:payload, :error) do
        def success? = error.nil?
      end
    end
  end
end
