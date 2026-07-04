module Textus
  module Infra
    class Store
      class CursorStore
        def initialize(database)
          @db = database
        end

        def read(role)
          row = @db[:cursors].where(role:).first
          row ? row[:seq] : 0
        end

        def write(role, seq)
          @db[:cursors].insert_conflict(
            update: { seq:, updated_at: Time.now.utc },
          ).insert(role:, seq:, updated_at: Time.now.utc)
        end

        def read_loop_position(role)
          row = @db[:loop_positions].where(role:).first
          row ? row[:index] : 0
        end

        def write_loop_position(role, index)
          @db[:loop_positions].insert_conflict(
            update: { index:, updated_at: Time.now.utc },
          ).insert(role:, index:, updated_at: Time.now.utc)
        end
      end
    end
  end
end
