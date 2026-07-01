Textus.workflow "federation-sync" do
  match "artifacts.system.federation"

  step :sync do |_data, ctx|
    sanitize = ->(path) {
      File.basename(path.to_s)
          .gsub(/[^a-z0-9-]/i, "-")
          .gsub(/-+/, "-")
          .gsub(/\A-+|-+\z/, "")
          .downcase
    }

    manifest = ctx.container.manifest
    federation = manifest.data.raw["federation"] || []
    writer = Textus::Store::Entry::Writer.from(container: ctx.container, call: ctx.call)

    synced = []

    federation.each do |peer|
      remote_root = File.expand_path(peer["from"], manifest.data.root)
      prefix = peer["mount"] || ""
      alias_seg = sanitize.call(peer["from"])

      unless File.directory?(remote_root) && File.exist?(File.join(remote_root, "manifest.yaml"))
        synced << { "peer" => peer["from"], "status" => "unreachable" }
        next
      end

      remote = Textus::Store.new(remote_root, correlation_id: ctx.call.correlation_id)
      list_args = prefix.empty? ? {} : { prefix: }
      rows = remote.list(**list_args)

      rows.each do |row|
        local_key = "artifacts.federation.#{alias_seg}.#{row["key"]}"

        env = remote.get(key: row["key"])
        next unless env

        local_env = ctx.container.read_family(local_key).first

        if local_env && local_env.etag == env.etag
          synced << { "key" => local_key, "status" => "unchanged" }
          next
        end

        mentry = ctx.container.manifest.resolver.resolve("artifacts.federation").entry
        writer.put(
          local_key,
          mentry:,
          payload: Textus::Value::Payload.new(
            meta: env.meta,
            body: env.body,
            content: env.content,
          ),
          if_etag: local_env&.etag,
        )
        synced << { "key" => local_key, "status" => "synced" }
      end
    end

    {
      "content" => {
        "ok" => true,
        "peers" => federation.size,
        "synced" => synced.size,
        "details" => synced,
      },
    }
  end

  publish
end
