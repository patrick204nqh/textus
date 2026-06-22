module Textus
  # Bus is the dispatch infrastructure — middleware pipeline, pluggable
  # predicates, and the Pipeline class that wires them together.
  #
  # Surfaces dispatch commands through a Pipeline instance; each middleware
  # layer handles one cross-cutting concern (auth, audit, cascade, binder).
  # Predicates are registered per command type for fine-grained auth.
  module Bus
  end
end
