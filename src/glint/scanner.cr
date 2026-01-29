module Glint
  class Scanner
    SECRET_PATTERNS = {
      "AWS Access Key"      => /\b((?:AKIA|ABIA|ACCA)[A-Z0-9]{16})\b/,
      "GitHub Token"        => /\b((?:ghp|gho|ghu|ghs|ghr|github_pat)_[a-zA-Z0-9_]{36,255})\b/,
      "Private Key"         => /-----\s*?BEGIN[ A-Z0-9_-]*?PRIVATE KEY\s*?-----[\s\S]*?----\s*?END[ A-Z0-9_-]*? PRIVATE KEY\s*?-----/i,
      "Generic Secret"      => /(pass|token|cred|secret|key)(\b[\x21-\x7e]{16,64}\b)/i,
      "Stripe Key"          => /[rs]k_live_[a-zA-Z0-9]{20,247}/,
      "Slack Bot Token"     => /xoxb\-[0-9]{10,13}\-[0-9]{10,13}[a-zA-Z0-9\-]*/,
      "Slack User Token"    => /xoxp\-[0-9]{10,13}\-[0-9]{10,13}[a-zA-Z0-9\-]*/,
      "Azure Storage Key"   => /(?:Access|Account|Storage)[_.-]?Key.{0,25}?([a-zA-Z0-9+\/-]{86,88}={0,2})/i,
      "GCP Service Account" => /\{[^{]+auth_provider_x509_cert_url[^}]+\}/,
      "MongoDB URI"         => /mongodb(?:\+srv)?:\/\/\S{3,50}:\S{3,88}@[-.%\w]+(?::\d{1,5})?/,
      "PostgreSQL URI"      => /postgres(?:ql)?:\/\/\S+/i,
    }

    INTERESTING_PATTERNS = [
      /[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}/,
      /[A-Z]{2,6}\-[0-9]{2,6}/,
      /\b[A-Fa-f0-9]{64}\b/,
      /https?:\/\/[^\s<>"]+/,
      /([0-9A-F]{2}[:-]){5}([0-9A-F]{2})/i,
      /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/,
    ]

    struct Match
      property type : Symbol
      property name : String
      property value : String

      def initialize(@type, @name, @value)
      end
    end

    def initialize(@check_secrets : Bool = false, @show_interesting : Bool = false)
    end

    def scan(text : String) : Array(Match)
      matches = [] of Match

      if @check_secrets
        SECRET_PATTERNS.each do |name, pattern|
          text.scan(pattern) do |m|
            matches << Match.new(:secret, name, m[0])
          end
        end
      end

      if @show_interesting
        INTERESTING_PATTERNS.each do |pattern|
          text.scan(pattern) do |m|
            matches << Match.new(:interesting, "Pattern", m[0])
          end
        end
      end

      matches
    end
  end
end
