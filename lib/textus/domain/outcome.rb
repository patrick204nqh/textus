module Textus
  module Domain
    module Outcome
      Skipped   = Data.define
      Refreshed = Data.define(:envelope)
      Detached  = Data.define
      Failed    = Data.define(:error)
    end
  end
end
