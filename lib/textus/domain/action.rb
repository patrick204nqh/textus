module Textus
  module Domain
    module Action
      Return       = Data.define
      RefreshSync  = Data.define
      RefreshTimed = Data.define(:budget_ms)
    end
  end
end
