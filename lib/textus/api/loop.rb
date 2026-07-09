require_relative "loop/transitions"

module Textus
  class API
    class Loop
      NodeEntry = Data.define(:path, :entered_at, :exited_at) do
        def node   = path.first
        def topic  = path[1]
        def item   = path[2]
        def current? = exited_at.nil?
        def duration  = (exited_at || Time.now.utc) - entered_at
      end

      def initialize(node_names, store:, session:, gate: nil)
        @node_names = node_names
        @store = store
        @session = session
        @gate = gate
        @stack = restore_stack(session.payload)
      end

      def enter(path)
        segments = path.map { |s| s.is_a?(String) && !s.match?(/\A[0-9]|-/) ? s.to_sym : s }
        Loop::Transitions.validate!(current_node&.path, segments, node_names: @node_names)

        current = current_node
        changing_node = current&.current? && current.node != segments.first
        fire_node_exit(current) if changing_node

        entry = NodeEntry.new(path: segments, entered_at: Time.now.utc, exited_at: nil)
        @stack.push(entry)

        fire_node_enter(entry) if changing_node || @stack.size == 1
        persist
        self
      end

      def exit
        entry = current_node
        raise Textus::UsageError.new("no node to exit") unless entry

        to_remove = @stack.reverse_each.with_object([]) do |e, acc|
          break acc if e.node != entry.node
          acc << e
        end

        to_remove.each { |e| @stack.delete(e) }
        fire_node_enter(current_node) if current_node
        persist
      end

      def back
        entry = current_node
        raise Textus::UsageError.new("no node to step back from") unless entry

        @stack.delete(entry)
        fire_node_enter(current_node) if current_node&.current?
        persist
      end

      def switch(path)
        exit
        enter(path)
      end

      def first
        enter([@node_names.first])
      end

      def status
        { current_node: current_node&.node&.to_s,
          current_topic: current_node&.topic&.to_s,
          current_item: current_node&.item&.to_s,
          stack: summary, available_nodes: @node_names.map(&:to_s) }
      end

      def current = current_node

      def to_h = { stack: @stack.map { |e| e.path.map(&:to_s) } }

      private

      def current_node
        @stack.reverse_each.find(&:current?) || @stack.last
      end

      def summary
        @stack.map do |e|
          { path: e.path.map(&:to_s), entered_at: e.entered_at.iso8601,
            exited_at: e.exited_at&.iso8601, current: e.current?, duration_s: e.duration }
        end
      end

      def restore_stack(payload)
        (payload["stack"] || []).map do |path|
          NodeEntry.new(path: path.map(&:to_sym), entered_at: Time.now.utc, exited_at: nil)
        end
      end

      def persist
        @store.update_payload(@session.id, to_h)
      end

      def fire_node_enter(entry)
        return unless @gate

        request = Adapters::Request.new(
          action: :node_entered, params: { path: entry.path.map(&:to_s) },
          role: @session.role, session_id: @session.id,
        )
        @gate.dispatch(request)
      rescue StandardError
        nil
      end

      def fire_node_exit(entry)
        return unless @gate

        entry.exited_at = Time.now.utc
        request = Adapters::Request.new(
          action: :node_exited, params: { path: entry.path.map(&:to_s) },
          role: @session.role, session_id: @session.id,
        )
        @gate.dispatch(request)
      rescue StandardError
        nil
      end
    end
  end
end
