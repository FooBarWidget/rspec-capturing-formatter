RSpec.describe "encoded output" do
  it "splits a UTF-8 character across writes" do
    $stdout.write(String.new("price \xE2", encoding: Encoding::UTF_8))
    $stdout.puts String.new("\x82\xAC", encoding: Encoding::UTF_8)
  end
end
