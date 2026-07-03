module Textus
  class Store
    module Retention
      Plan = Data.define(:steps, :warnings) do
        def to_h
          { "steps" => steps, "warnings" => warnings }
        end
      end
    end
  end
end
