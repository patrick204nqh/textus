module Textus
  class Operations
    class Writes
      def initialize(ctx)
        @ctx = ctx
      end

      def put     = Application::Writes::Put.new(ctx: @ctx, bus: bus)
      def delete  = Application::Writes::Delete.new(ctx: @ctx, bus: bus)
      def mv      = Application::Writes::Mv.new(ctx: @ctx, bus: bus)
      def accept  = Application::Writes::Accept.new(ctx: @ctx, bus: bus)
      def build   = Application::Writes::Build.new(ctx: @ctx, bus: bus)
      def publish = Application::Writes::Publish.new(ctx: @ctx, bus: bus)

      private

      def bus = @ctx.store.bus
    end
  end
end
