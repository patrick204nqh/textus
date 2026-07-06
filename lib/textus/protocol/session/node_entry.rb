Textus::Protocol::Session::NodeEntry = Class.new do
  attr_reader :path, :entered_at
  attr_accessor :exited_at

  def initialize(path:, entered_at: Time.now.utc, exited_at: nil)
    @path = path.map { |s| s.is_a?(String) && !s.match?(/\A[0-9]|-/) ? s.to_sym : s }
    @entered_at = entered_at
    @exited_at = exited_at
  end

  def current?
    @exited_at.nil?
  end

  def duration
    current? ? (Time.now.utc - @entered_at).to_i : (@exited_at - @entered_at).to_i
  end

  def node
    @path.first
  end

  def topic
    @path[1]
  end

  def item
    @path[2]
  end
end
