# frozen_string_literal: true

module Textus
  module ContainerHelpers
    def manifest   = container.manifest
    def repo_root  = File.dirname(container.root)
    def store_root = container.root
  end
end
