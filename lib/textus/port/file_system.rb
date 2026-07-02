module Textus
  module Port
    class FileSystem
      module Interface
        def read(path) = raise NotImplementedError
        def write(path, bytes) = raise NotImplementedError
        def delete(path) = raise NotImplementedError
        def exists?(path) = raise NotImplementedError
        def etag(path) = raise NotImplementedError
        def size(path) = raise NotImplementedError
        def mkdir_p(path) = raise NotImplementedError
        def rmdir(path) = raise NotImplementedError
        def dir_empty?(dir) = raise NotImplementedError
        def glob(pattern) = raise NotImplementedError
        def mv(from, to) = raise NotImplementedError
        def copy(source, target) = raise NotImplementedError
        def symlink?(path) = raise NotImplementedError
        def identical?(a, b) = raise NotImplementedError
        def mtime(path) = raise NotImplementedError
        def directory?(path) = raise NotImplementedError
        def flock_exclusive(path, nonblock: false, &) = raise NotImplementedError
      end
      include Interface
    end
  end
end
