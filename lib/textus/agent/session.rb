module Textus
  module Agent
    class Session
      attr_reader :id, :created_at, :status

      def initialize(id: SecureRandom.uuid, store: nil)
        @id = id
        @store = store
        @created_at = Time.now.utc
        @status = :active
      end

      def close
        @status = :sealed
      end

      def active? = @status == :active
      def sealed? = @status == :sealed
    end
  end
end
