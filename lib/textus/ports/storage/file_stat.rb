module Textus
  module Ports
    module Storage
      # Read-only filesystem query port. The narrow interface that pure
      # domain logic (staleness checks, sentinel value) depends on, so the
      # domain never touches File/Dir directly. FileStore owns the write side.
      class FileStat
        def exists?(path)    = File.exist?(path)
        def directory?(path) = File.directory?(path)
        def read(path)       = File.binread(path)
        def mtime(path)      = File.mtime(path)

        # Ruby 3.3+ guarantees Dir.glob returns a sorted Array; no explicit sort
        # needed, but callers can rely on ordered results for stable behaviour.
        def glob(pattern)    = Dir.glob(pattern)
      end
    end
  end
end
