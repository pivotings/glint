require "./glint/lib"

module Glint
  def self.run
    config = Config.new

    parser = OptionParser.new do |p|
      p.banner = "glint - GitHub OSINT tool\n\nUsage: glint [options] <username|email>"
      p.banner = "glint - GitHub OSINT tool\n\nUsage: glint [options] <username|email>\n       glint -l <file> -o <dir> [options]"

      p.on("-t TOKEN", "--token=TOKEN", "GitHub personal access token") { |t| config.token = t }
      p.on("-l FILE", "--list=FILE", "File containing list of emails/usernames (one per line)") { |f| config.list_file = f }
      p.on("-o DIR", "--output-dir=DIR", "Output directory for batch results") { |d| config.output_dir = d }
      p.on("-c N", "--concurrent=N", "Number of concurrent workers (default: 4)") { |n| config.concurrent = n.to_i32 }
      p.on("-d", "--details", "Show detailed commit info") { config.details = true }
      p.on("-s", "--secrets", "Scan for secrets in commits") { config.secrets = true }
      p.on("-i", "--interesting", "Show interesting strings") { config.interesting = true }
      p.on("-S", "--show-stargazers", "Show stargazers") { config.show_stargazers = true }
      p.on("-f", "--show-forkers", "Show forkers") { config.show_forkers = true }
      p.on("-j", "--json", "JSON output") { config.json = true }
      p.on("--csv", "CSV output") { config.csv = true }
      p.on("-p", "--profile-only", "Profile only, skip repos") { config.profile_only = true }
      p.on("-q", "--quick", "Quick mode (~50 commits/repo)") { config.quick = true }
      p.on("-T", "--timestamp-analysis", "Analyze commit timestamps") { config.timestamp_analysis = true }
      p.on("-F", "--include-forks", "Include forked repos") { config.include_forks = true }
      p.on("-v", "--version", "Show version") { puts "glint v#{VERSION}"; exit }
      p.on("-h", "--help", "Show help") { puts p; exit }

      p.invalid_option do |flag|
        STDERR.puts "Error: #{flag} is not a valid option."
        STDERR.puts p
        exit 1
      end
    end

    parser.parse

    if config.batch_mode?
      if config.output_dir.empty?
        puts parser
        exit 1
      end
    else
      target = ARGV.first?
      unless target
        puts parser
        exit 1
      end
      config.target = target
    end

    if config.token.empty?
      result = Token.detect

      if result.found?
        config.token = result.token
        STDERR.puts "\e[90mUsing token from #{Token.source_description(result.source)}\e[0m" unless config.json || config.csv
      else
        if STDIN.tty?
          if token = Token.interactive_setup
            config.token = token
          end
        else
          STDERR.puts "\e[33mWarning: No GitHub token found. API rate limits will be restricted.\e[0m"
        end
      end
    end

    orchestrator = Orchestrator.new(config)
    orchestrator.run
  rescue ex
    STDERR.puts "Error: #{ex.message}"
    exit 1
  end
end

Glint.run
