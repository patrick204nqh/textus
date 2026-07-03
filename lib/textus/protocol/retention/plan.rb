module Textus
  module Protocol
    module Retention
      Plan = Data.define(:steps, :warnings) do
        def to_h
          { "steps" => steps, "warnings" => warnings }
        end
      end
    end
  end
end
