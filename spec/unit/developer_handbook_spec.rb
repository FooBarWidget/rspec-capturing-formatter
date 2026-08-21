require "spec_helper"

RSpec.describe "the developer handbook" do
  let(:directory) { File.expand_path("../../devdocs", __dir__) }

  it "keeps every table-of-contents link valid" do
    table_of_contents = File.read(File.join(directory, "README.md"))
    links = table_of_contents.scan(/\]\(([^)#]+\.md)\)/).flatten

    expect(links).not_to be_empty
    links.each do |link|
      expect(File).to exist(File.join(directory, link))
    end
  end
end
