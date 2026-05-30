module Textus
  module Domain
    Permission = Data.define(:zone, :writers) do
      def allows_write?(role) = writers.include?(role.to_s)
    end
  end
end
