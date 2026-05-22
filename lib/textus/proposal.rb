module Textus
  module Proposal
    # Deprecated as of 0.9.1: use Textus::Application::Writes::Accept (via
    # Textus::Composition.writes_accept).
    def self.accept(store, pending_key, as:)
      ctx = Textus::Composition.context(store, role: as)
      Textus::Application::Writes::Accept.new(ctx: ctx, bus: store.bus).call(pending_key)
    end
  end
end
