require "rspec"
require_relative "../lib/rspec/capturing_formatter"

RSpec.configure do |config|
  config.disable_monkey_patching! if config.respond_to?(:disable_monkey_patching!)
end
