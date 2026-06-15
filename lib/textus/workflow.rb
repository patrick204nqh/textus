module Textus
  module Workflow
  end

  def self.workflow(name, &block)
    collector = Workflow::Collector.current
    raise "Textus.workflow called outside Workflow::Loader.load_all context" unless collector

    defn = Workflow::DSL::Definition.new(name)
    defn.instance_eval(&block)
    collector.register(defn)
  end
end
