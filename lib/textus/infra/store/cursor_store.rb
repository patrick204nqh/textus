module Textus
  module Infra
    class Store
      class CursorStore < Base
        def get(role)
          result(table(:cursors).where(role:).first) || { role:, seq: 0 }
        end

        def set(role, seq)
          table(:cursors).insert_conflict(
            update: { seq:, updated_at: Time.now.utc },
          ).insert(role:, seq:, updated_at: Time.now.utc)
        end

        def get_loop(role)
          result(table(:loop_positions).where(role:).first) || { role:, index: 0 }
        end

        def set_loop(role, index)
          table(:loop_positions).insert_conflict(
            update: { index:, updated_at: Time.now.utc },
          ).insert(role:, index:, updated_at: Time.now.utc)
        end
      end
    end
  end
end
