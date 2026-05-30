module Textus
  module Domain
    Permission = Data.define(:zone, :writers, :read_policy) do
      def allows_write?(role)
        writers.include?(role.to_s)
      end

      def allows_read?(role)
        return true if [:all, ["all"]].include?(read_policy)

        read_policy.include?(role.to_s)
      end
    end
  end
end
