require "./spec_helper"

describe Glint::Scanner do
  describe "#scan" do
    it "detects AWS access keys" do
      scanner = Glint::Scanner.new(check_secrets: true)
      matches = scanner.scan("Found key: AKIAIOSFODNN7EXAMPLE")
      matches.size.should eq(1)
      matches[0].name.should eq("AWS Access Key")
      matches[0].value.should eq("AKIAIOSFODNN7EXAMPLE")
    end

    it "detects GitHub tokens" do
      scanner = Glint::Scanner.new(check_secrets: true)
      matches = scanner.scan("ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
      # May also match Generic Secret, so check we got at least one GitHub Token
      github_matches = matches.select { |m| m.name == "GitHub Token" }
      github_matches.size.should eq(1)
    end

    it "detects private keys" do
      scanner = Glint::Scanner.new(check_secrets: true)
      key = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA...\n-----END RSA PRIVATE KEY-----"
      matches = scanner.scan(key)
      matches.size.should eq(1)
      matches[0].name.should eq("Private Key")
    end

    it "detects Stripe keys" do
      scanner = Glint::Scanner.new(check_secrets: true)
      matches = scanner.scan("sk_live_abcdefghijklmnopqrst")
      stripe_matches = matches.select { |m| m.name == "Stripe Key" }
      stripe_matches.size.should eq(1)
    end

    it "detects Slack tokens" do
      scanner = Glint::Scanner.new(check_secrets: true)
      matches = scanner.scan("xoxb-1234567890123-1234567890123-abcd")
      slack_matches = matches.select { |m| m.name == "Slack Bot Token" }
      slack_matches.size.should eq(1)
    end

    it "detects MongoDB URIs" do
      scanner = Glint::Scanner.new(check_secrets: true)
      matches = scanner.scan("mongodb://user:password@host.example.com:27017")
      matches.size.should eq(1)
      matches[0].name.should eq("MongoDB URI")
    end

    it "detects PostgreSQL URIs" do
      scanner = Glint::Scanner.new(check_secrets: true)
      matches = scanner.scan("postgres://user:pass@host:5432/db")
      matches.size.should eq(1)
      matches[0].name.should eq("PostgreSQL URI")
    end

    it "finds no secrets in clean text" do
      scanner = Glint::Scanner.new(check_secrets: true)
      matches = scanner.scan("This is just normal text with no secrets")
      matches.size.should eq(0)
    end

    it "finds UUIDs when interesting mode is on" do
      scanner = Glint::Scanner.new(check_secrets: false, show_interesting: true)
      matches = scanner.scan("id=550e8400-e29b-41d4-a716-446655440000")
      matches.size.should eq(1)
      matches[0].type.should eq(:interesting)
    end

    it "finds IP addresses when interesting mode is on" do
      scanner = Glint::Scanner.new(check_secrets: false, show_interesting: true)
      matches = scanner.scan("server: 192.168.1.100")
      matches.size.should eq(1)
    end

    it "finds URLs when interesting mode is on" do
      scanner = Glint::Scanner.new(check_secrets: false, show_interesting: true)
      matches = scanner.scan("visit https://example.com/api")
      matches.size.should eq(1)
    end

    it "returns nothing when both modes are off" do
      scanner = Glint::Scanner.new(check_secrets: false, show_interesting: false)
      matches = scanner.scan("AKIAIOSFODNN7EXAMPLE https://example.com")
      matches.size.should eq(0)
    end

    it "finds multiple secrets in one text" do
      scanner = Glint::Scanner.new(check_secrets: true)
      text = "AKIAIOSFODNN7EXAMPLE ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
      matches = scanner.scan(text)
      # Count unique secret types found
      aws_matches = matches.select { |m| m.name == "AWS Access Key" }
      github_matches = matches.select { |m| m.name == "GitHub Token" }
      aws_matches.size.should eq(1)
      github_matches.size.should eq(1)
    end
  end
end
