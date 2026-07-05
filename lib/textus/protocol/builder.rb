module Textus
  module Protocol
    class Builder
      def call(root)
        infra = Infrastructure.new.call(root)
        domain = Domain.new.call(root, layout: infra.layout)
        Runtime.new.call(infra:, domain:, root:).container
      end
    end
  end
end
