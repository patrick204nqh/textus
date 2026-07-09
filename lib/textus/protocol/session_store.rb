module Textus
  module Protocol
    class SessionStore
      def initialize(database)
        @db = database
      end

      def find(id)
        row = @db[:sessions].where(id:).first
        row ? { id: row[:id], role: row[:role], surface_id: row[:surface_id],
                cursor_seq: row[:cursor_seq], contract_etag: row[:contract_etag],
                expires_at: row[:expires_at], created_at: row[:created_at] } : nil
      end

      def create(id:, role:, surface_id: nil, expires_at: nil)
        @db[:sessions].insert(
          id:, role: role.to_s,
          surface_id:,
          expires_at: expires_at || Time.now.utc + 86400,
          created_at: Time.now.utc,
        )
        find(id)
      end

      def save(id, cursor_seq: nil, contract_etag: nil)
        updates = {}.tap do |u|
          u[:cursor_seq] = cursor_seq if cursor_seq
          u[:contract_etag] = contract_etag if contract_etag
        end
        @db[:sessions].where(id:).update(updates) unless updates.empty?
      end

      def sweep_expired!
        @db[:sessions].where { expires_at < Time.now.utc }.delete
      end
    end
  end
end
