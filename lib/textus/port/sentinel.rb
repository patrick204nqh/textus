require "digest"

module Textus
  module Port
    class Sentinel
      attr_reader :target, :source, :sha256, :mode

      def initialize(target:, source:, sha256:, mode:)
        @target = target
        @source = source
        @sha256 = sha256
        @mode = mode
      end

      def orphan?(file_stat) = @target.nil? || !file_stat.exists?(@target)

      def drift?(file_stat)
        return false if orphan?(file_stat)
        return false if @sha256.nil?

        Digest::SHA256.hexdigest(file_stat.read(@target)) != @sha256
      end
    end
  end
end
