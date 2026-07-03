module Textus
  module Lanes
    module Ingest
      module KeyBuilder
        CONTENT_HASH_ALGO = "sha256"
  
        module_function
  
        def derive_key(now, kind, slug)
          date = now.strftime("%Y.%m.%d")
          "raw.#{date}.#{kind}-#{slug}"
        end
  
        def compute_hash(kind:, url: nil, path: nil)
          digest = Digest::SHA256.new
          case kind
          when "url"
            raise ArgumentError.new("url required") unless url
  
            digest.update(url)
          when "file", "asset"
            raise ArgumentError.new("path required") unless path
  
            digest.file(path)
          else
            raise ArgumentError.new("unknown kind: #{kind}")
          end
          "#{CONTENT_HASH_ALGO}:#{digest.hexdigest}"
        end
      end
    end
  end
end
  