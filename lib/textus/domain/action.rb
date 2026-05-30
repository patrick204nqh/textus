module Textus
  module Domain
    module Action
      Return = Data.define
      FetchSync  = Data.define
      FetchTimed = Data.define(:budget_ms)
    end
  end
end
