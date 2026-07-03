module Textus
  module Ingest
    module EntryTypes
      module Asset
        module_function

        def build(path:, lane:, time:, layout:, label: nil, **)
          asset_rel = copy(path, lane:, time:, layout:)
          { "source" => { "kind" => "asset", "label" => label || File.basename(path) },
            "asset" => asset_rel, "body" => nil }
        end

        def copy(path, lane:, time:, layout:)
          date_path = time.strftime("%Y/%m/%d")
          filename  = File.basename(path)
          assets_dir = layout.asset_raw_dir(date_path, lane)
          FileUtils.mkdir_p(assets_dir)
          FileUtils.cp(path, File.join(assets_dir, filename))
          sentinel = layout.asset_sentinel_path
          File.write(sentinel, "*\n") unless File.exist?(sentinel)
          "raw/#{date_path}/#{lane}/#{filename}"
        end

        def move(old_rel, lane, layout)
          old_path = layout.asset_resolve(old_rel)
          return unless File.exist?(old_path)

          now = Time.now.utc
          date_path = now.strftime("%Y/%m/%d")
          filename = File.basename(old_path)
          new_dir = layout.asset_raw_dir(date_path, lane)
          new_path = File.join(new_dir, filename)
          return if old_path == new_path

          FileUtils.mkdir_p(new_dir)
          FileUtils.mv(old_path, new_path)
        rescue Errno::ENOENT, Errno::EACCES => e
          warn "[textus ingest] could not move asset #{old_rel}: #{e.message}"
        end
      end
    end
  end
end
