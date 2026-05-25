Textus.on(:build_completed, :stamp_log) do |key:, envelope:, sources:, **|
  line = "#{Time.now.utc.iso8601} #{key} from=#{sources.join(',')} etag=#{envelope['etag'][0..11]}\n"
  File.write(File.expand_path(".textus/last-build.log"), line, mode: "a")
end
