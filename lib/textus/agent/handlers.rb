module Textus
  module Agent
    module Handlers
      def self.session_open(store)
        session = Session.new
        { session_id: session.id, created_at: session.created_at }
      end

      def self.session_close(store, session_id)
        { session_id:, status: :sealed }
      end

      def self.exec(store, session_id, script_path)
        Runner.new.exec(script_path)
      end

      def self.propose_from_session(store, session_id, target_key:, note: nil)
        evidence = Evidence.new(session_id, store)
        evidence.attach(target_key, note:)
        evidence.trace
      end
    end
  end
end
