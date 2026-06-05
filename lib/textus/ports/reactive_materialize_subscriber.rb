# frozen_string_literal: true

module Textus
  module Ports
    # Wires the reactive half of ADR 0087 to the canon-write event. On every
    # `:entry_put`, re-materialize the derived entries that depend on the
    # written key (rdeps ∩ derived). Attached at Store boot, alongside
    # AuditSubscriber.
    #
    # Dispatch model: Hooks::EventBus#publish runs each subscriber inline
    # (it spawns a per-subscriber thread and joins it before publish returns),
    # so this handler executes *within* the originating write call. That gives
    # the sync materialize policy its fresh-on-return guarantee for free — the
    # write does not return until the inline rebuild completes. The async policy
    # spawns a tracked, join-before-exit thread (ReactiveMaterialize::AsyncRunner)
    # so it returns promptly without blocking the write yet still completes
    # before the process exits.
    #
    # The handler reconstructs the originating Call from the event ctx (a
    # Hooks::Context carrying role + correlation_id), so the rebuild runs under
    # the same actor/correlation as the write that triggered it.
    class ReactiveMaterializeSubscriber
      def initialize(container)
        @container = container
      end

      def attach(bus)
        bus.on(:entry_put, :reactive_materialize) do |ctx:, key:, **|
          call = Textus::Call.build(role: ctx.role, correlation_id: ctx.correlation_id)
          Textus::Maintenance::ReactiveMaterialize.new(container: @container).on_write(key: key, call: call)
        end
        self
      end
    end
  end
end
