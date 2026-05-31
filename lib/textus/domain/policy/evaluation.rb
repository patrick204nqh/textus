# frozen_string_literal: true

module Textus
  module Domain
    module Policy
      # Immutable context handed to every predicate. `manifest` is the
      # manifest (pure, no I/O); `envelope` is the entry under evaluation
      # (nil when no bytes exist yet, e.g. a fresh put). `origin`/`target`
      # are dotted keys; `transition` is the verb symbol.
      Evaluation = Data.define(
        :actor, :transition, :origin, :target, :envelope, :manifest
      )
    end
  end
end
