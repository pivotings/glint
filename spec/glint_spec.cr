require "./spec_helper"

describe Glint::Config do
  it "has correct default values" do
    config = Glint::Config.new
    config.token.should eq("")
    config.target.should eq("")
    config.details.should be_false
    config.secrets.should be_false
    config.interesting.should be_false
    config.json.should be_false
    config.csv.should be_false
    config.profile_only.should be_false
    config.quick.should be_false
    config.timestamp_analysis.should be_false
    config.include_forks.should be_false
  end

  it "returns correct output format" do
    config = Glint::Config.new
    config.output_format.should eq(:text)

    config.json = true
    config.output_format.should eq(:json)

    config.json = false
    config.csv = true
    config.output_format.should eq(:csv)
  end
end
