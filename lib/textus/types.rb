# frozen_string_literal: true

require "dry/types"

module Textus
  module Types
    include Dry.Types()

    RoleName   = Types::String.constrained(included_in: Textus::Role::NAMES)
    Cursor     = Types::Integer.constrained(gteq: 0)
    FormatName = Types::String.constrained(
      included_in: %w[markdown json yaml text], # must match Format::STRATEGIES.keys
    )
  end
end
