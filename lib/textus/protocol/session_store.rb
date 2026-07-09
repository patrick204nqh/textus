module Textus
  module Protocol
    class SessionStore
      def initialize(database)
        @db = database
      end

      def find(id)
        row = @db[:sessions].where(id:).first
        return nil unless row
        {
          id: row[:id], role: row[:role], surface_id: row[:surface_id],
          cursor_seq: row[:cursor_seq], contract_etag: row[:contract_etag],
          expires_at: row[:expires_at], created_at: row[:created_at],
          status: row[:status], correlation_id: row[:correlation_id],
          payload: row[:payload] ? JSON.parse(row[:payload]) : {},
        }
      end

      def create(id:, role:, surface_id: nil, expires_at: nil)
        @db[:sessions].insert(
          id:, role: role.to_s,
          surface_id:,
          status: "active",
          correlation_id: SecureRandom.uuid,
          payload: "{}",
          expires_at: expires_at || Time.now.utc + 86400,
          created_at: Time.now.utc,
          updated_at: Time.now.utc,
        )
        find(id)
      end

      def save(id, cursor_seq: nil, contract_etag: nil)
        updates = { updated_at: Time.now.utc }.tap do |u|
          u[:cursor_seq] = cursor_seq if cursor_seq
          u[:contract_etag] = contract_etag if contract_etag
        end
        @db[:sessions].where(id:).update(updates) unless updates.empty?
      end

      def seal(id)
        @db[:sessions].where(id:).update(status: "sealed", updated_at: Time.now.utc)
      end

      def update_payload(id, payload_hash)
        @db[:sessions].where(id:).update(
          payload: JSON.generate(payload_hash),
          updated_at: Time.now.utc,
        )
      end

      def active_for_role(role)
        @db[:sessions].where(role:, status: "active").order(Sequel.desc(:created_at)).first
      end

      def sweep_expired!
        @db[:sessions].where { expires_at < Time.now.utc }.delete
      end
    end
  end
end
