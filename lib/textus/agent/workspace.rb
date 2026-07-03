module Textus
  module Agent
    class Workspace
      SCRIPTS  = "scripts"
      NOTES    = "notes"
      OUTPUT   = "output"
      CONFIG   = "config"
      RAW      = "raw"
      IGNORE   = %w[node_modules/ .venv/ *.lock .git/].freeze

      attr_reader :session_id, :root

      def initialize(session_id, root)
        @session_id = session_id
        @root = root
      end

      def scripts_dir  = File.join(@root, SCRIPTS)
      def notes_dir    = File.join(@root, NOTES)
      def output_dir   = File.join(@root, OUTPUT)
      def config_dir   = File.join(@root, CONFIG)
      def raw_dir      = File.join(@root, RAW)

      def ensure_dirs!
        [scripts_dir, notes_dir, output_dir, config_dir, raw_dir].each { |d| FileUtils.mkdir_p(d) }
      end
    end
  end
end
