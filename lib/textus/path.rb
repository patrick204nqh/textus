module Textus
  module Path
    # Returns the absolute filesystem path for a manifest entry (the leaf file,
    # not a nested directory). Adds the format's primary extension when the
    # manifest entry's `path:` is extensionless.
    def self.resolve(manifest, mentry)
      primary_ext = Entry.for_format(mentry.format).extensions.first
      if File.extname(mentry.path) == ""
        File.join(manifest.root, "zones", mentry.path + primary_ext)
      else
        File.join(manifest.root, "zones", mentry.path)
      end
    end
  end
end
