module Textus
  module Format
    module Shared
      ENFORCE_NAME_RE = /\.(md|json|yaml|yml|txt)\z/i

      def self.enforce_name_match!(path, meta, extensions)
        return unless meta.is_a?(Hash) && meta["name"]

        ext = extensions.first
        basename = File.basename(path, ext)
        return if meta["name"] == basename

        raise BadFrontmatter.new(path, "name '#{meta["name"]}' does not match basename '#{basename}'")
      end
    end
  end
end
