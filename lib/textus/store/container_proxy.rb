module Textus
  class Store
    ContainerProxy = Data.define(
      :manifest, :file_store, :schemas, :audit_log, :job_store,
      :layout, :workflows, :pipeline, :root
    )
  end
end
