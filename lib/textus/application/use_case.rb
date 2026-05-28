module Textus
  module Application
    # Registry mapping verb symbols to use-case modules. Each entry says
    # which caps slice the use case needs (:read or :write); Session
    # uses this to define one method per verb.
    module UseCase
      Entry = Data.define(:verb, :mod, :caps_kind)

      @entries = []

      class << self
        attr_reader :entries

        def register(verb, mod, caps:)
          @entries << Entry.new(verb: verb.to_sym, mod: mod, caps_kind: caps.to_sym)
        end

        def each(&) = @entries.each(&)
      end
    end
  end
end
