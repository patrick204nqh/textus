# frozen_string_literal: true

module Textus
  module Workflow
    Context = Data.define(:key, :entry, :config, :lane, :container, :call) do
      def manifest   = container.manifest
      def repo_root  = File.dirname(container.root)
      def store_root = container.root
    end
  end
end
