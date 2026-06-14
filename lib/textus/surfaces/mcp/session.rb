module Textus
  module Surfaces
    module MCP
      # The session value now lives in core (ADR 0036); retained here as an
      # alias so existing MCP references keep resolving.
      Session = Textus::Session
    end
  end
end
