require "logger"

LOGGER = Logger.new($stdout)
LOGGER.level = Logger::INFO

RSpec.describe "logger output" do
  it "uses the retained stream proxy" do
    LOGGER.info("logger message")
  end
end
