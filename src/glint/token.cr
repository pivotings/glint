require "yaml"

module Glint
  module Token
    CONFIG_DIR  = Path.home / ".config" / "glint"
    CONFIG_FILE = CONFIG_DIR / "config.yml"

    enum Source
      CommandLine
      GlintConfig
      GlintApiKeyEnv
      None
    end

    struct TokenResult
      getter token : String
      getter source : Source

      def initialize(@token : String, @source : Source)
      end

      def found? : Bool
        !@token.empty? && @source != Source::None
      end
    end

    def self.detect : TokenResult
      if token = read_glint_config
        return TokenResult.new(token, Source::GlintConfig)
      end

      if token = ENV["GITHUB_GLINT_API_KEY"]?
        return TokenResult.new(token, Source::GlintApiKeyEnv) unless token.empty?
      end

      TokenResult.new("", Source::None)
    end

    private def self.read_glint_config : String?
      return nil unless File.exists?(CONFIG_FILE)

      begin
        content = File.read(CONFIG_FILE)
        yaml = YAML.parse(content)
        yaml["github_token"]?.try(&.as_s)
      rescue
        nil
      end
    end

    def self.save(token : String) : Bool
      begin
        Dir.mkdir_p(CONFIG_DIR) unless Dir.exists?(CONFIG_DIR)

        config = {"github_token" => token}
        File.write(CONFIG_FILE, config.to_yaml)

        File.chmod(CONFIG_FILE, 0o600)
        true
      rescue ex
        STDERR.puts "Failed to save config: #{ex.message}"
        false
      end
    end

    def self.interactive_setup : String?
      STDERR.puts
      STDERR.puts "\e[33m⚠  No GitHub token found.\e[0m"
      STDERR.puts
      STDERR.puts "A GitHub personal access token is required for full functionality."
      STDERR.puts "Without a token, API rate limits are very restrictive (60 req/hour)."
      STDERR.puts
      STDERR.puts "You can set a token by:"
      STDERR.puts "  1. Entering it now (will be saved to #{CONFIG_FILE})"
      STDERR.puts "  2. Setting the GITHUB_GLINT_API_KEY environment variable"
      STDERR.puts
      STDERR.puts "Create a token at: \e[4mhttps://github.com/settings/tokens\e[0m"
      STDERR.puts "Required scope: \e[1mrepo\e[0m (full repository access including delete)"
      STDERR.puts

      prompt_for_token
    end

    private def self.prompt_for_token : String?
      STDERR.print "Enter your GitHub token (or press Enter to skip): "
      STDERR.flush

      token = read_password

      if token.nil? || token.empty?
        STDERR.puts "\e[33mSkipping token setup. Rate limits will be restricted.\e[0m"
        return ""
      end

      unless token.matches?(/^(ghp_|gho_|github_pat_)[a-zA-Z0-9_]+$/) || token.matches?(/^[a-f0-9]{40}$/)
        STDERR.puts "\e[33mWarning: Token format doesn't match expected GitHub token patterns.\e[0m"
        STDERR.print "Continue anyway? [y/N]: "
        STDERR.flush
        confirm = gets
        return "" unless confirm && confirm.strip.downcase == "y"
      end

      if save(token)
        STDERR.puts "\e[32m✓ Token saved to #{CONFIG_FILE}\e[0m"
      else
        STDERR.puts "\e[31m✗ Failed to save token. Using for this session only.\e[0m"
      end

      STDERR.puts
      token
    end

    private def self.read_password : String?
      begin
        system("stty -echo")
        token = gets.try(&.strip)
        STDERR.puts
        token
      ensure
        system("stty echo")
      end
    end

    def self.source_description(source : Source) : String
      case source
      when Source::CommandLine    then "command line (-t flag)"
      when Source::GlintConfig    then CONFIG_FILE.to_s
      when Source::GlintApiKeyEnv then "GITHUB_GLINT_API_KEY env var"
      when Source::None           then "none"
      else                             "unknown"
      end
    end
  end
end
