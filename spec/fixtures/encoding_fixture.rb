RSpec.describe "encoded output" do
  it "splits a UTF-8 character across writes" do
    $stdout.write("price \xE2".force_encoding(Encoding::UTF_8))
    $stdout.puts "\x82\xAC".force_encoding(Encoding::UTF_8)
  end
end
