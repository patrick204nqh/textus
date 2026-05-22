module Textus
  module Domain
    Permission = Data.define(:zone, :writable_by, :readable_by) do
      def allows_write?(role)
        writable_by.include?(role.to_s)
      end

      def allows_read?(role)
        return true if readable_by == :all

        readable_by.include?(role.to_s)
      end
    end
  end
end
