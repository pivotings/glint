require "json"
require "csv"

module Glint
  class Display
    RESET  = "\e[0m"
    BOLD   = "\e[1m"
    RED    = "\e[31m"
    GREEN  = "\e[32m"
    YELLOW = "\e[33m"
    BLUE   = "\e[34m"
    CYAN   = "\e[36m"
    WHITE  = "\e[37m"

    def initialize(@config : Config)
    end

    def info(msg : String)
      return if structured_output?
      puts "#{BLUE}#{msg}#{RESET}"
    end

    def success(msg : String)
      return if structured_output?
      puts "#{GREEN}#{msg}#{RESET}"
    end

    def warn(msg : String)
      return if structured_output?
      puts "#{YELLOW}#{msg}#{RESET}"
    end

    def error(msg : String)
      STDERR.puts "#{RED}#{msg}#{RESET}"
    end

    def progress(msg : String)
      return if structured_output?
      print "\r#{CYAN}#{msg}#{RESET}".ljust(60)
    end

    def progress_bar(label : String, current : Int32, total : Int32, detail : String = "")
      return if structured_output?

      pct = (current.to_f / total.to_f * 100).to_i
      filled = (pct / 10).to_i
      bar = "#{GREEN}#{"#" * filled}#{RESET}#{WHITE}#{"-" * (10 - filled)}#{RESET}"

      detail_str = detail.empty? ? "" : " #{detail}"
      print "\r#{CYAN}#{label}#{RESET} #{pct.to_s.rjust(3)}% [#{bar}] (#{current}/#{total})#{detail_str}".ljust(100)
      puts if current == total
    end

    def user_info(user : Models::User, is_org : Bool)
      return if structured_output?

      puts
      if is_org
        puts "#{CYAN}#{BOLD}ORGANIZATION: #{user.login}#{RESET}"
      else
        puts "#{CYAN}#{BOLD}USER: #{user.login}#{RESET}"
      end

      puts "#{WHITE}Name:#{RESET} #{user.name}" unless user.name.empty?
      puts "#{WHITE}Email:#{RESET} #{user.email}" unless user.email.empty?
      puts "#{WHITE}Company:#{RESET} #{user.company}" unless user.company.empty?
      puts "#{WHITE}Location:#{RESET} #{user.location}" unless user.location.empty?
      puts "#{WHITE}Bio:#{RESET} #{user.bio}" unless user.bio.empty?
      puts "#{WHITE}Website:#{RESET} #{user.blog}" unless user.blog.empty?
      puts "#{WHITE}Twitter:#{RESET} @#{user.twitter_username}" unless user.twitter_username.empty?

      puts
      puts "#{WHITE}Repos:#{RESET} #{user.public_repos}  #{WHITE}Gists:#{RESET} #{user.public_gists}  #{WHITE}Followers:#{RESET} #{user.followers}  #{WHITE}Following:#{RESET} #{user.following}"
      puts "#{WHITE}Created:#{RESET} #{user.created_at.to_s("%Y-%m-%d")}  #{WHITE}Updated:#{RESET} #{user.updated_at.to_s("%Y-%m-%d")}"
      puts
    end

    def results(emails : Hash(String, Models::EmailDetails), user : Models::User, is_org : Bool, identifiers : Set(String))
      print "\r".ljust(60) # Clear progress
      puts if !structured_output?

      case @config.output_format
      when :json
        output_json(emails, user, is_org)
      when :csv
        output_csv(emails)
      else
        output_text(emails, identifiers)
      end
    end

    def rate_limit(rl : Models::RateLimit)
      return if structured_output?

      pct = (rl.remaining.to_f / rl.limit.to_f * 100).round(1)
      color = case
              when pct > 50 then GREEN
              when pct > 20 then YELLOW
              else               RED
              end

      puts
      puts "-" * 50
      puts "#{color}API: #{rl.remaining}/#{rl.limit} (#{pct}%)#{RESET}"
      puts "#{BLUE}Resets: #{rl.reset_at.to_local.to_s("%Y-%m-%d %H:%M:%S")}#{RESET}"
    end

    private def structured_output? : Bool
      @config.json || @config.csv
    end

    private def output_text(emails : Hash(String, Models::EmailDetails), identifiers : Set(String))
      sorted = emails.to_a.sort_by { |_, d| -d.commit_count }

      # Email domain distribution
      output_email_domains(sorted)

      # Main email list
      sorted.each do |email, details|
        is_target = details.is_target
        is_similar = details.is_similar && !details.is_target

        color = if is_target
                  GREEN
                elsif is_similar
                  YELLOW
                else
                  WHITE
                end
        marker = if is_target
                   "[TARGET] "
                 elsif is_similar
                   "[SIMILAR] "
                 else
                   ""
                 end

        puts "#{color}#{marker}#{email} (#{details.commit_count} commits)#{RESET}"
        puts "  Names: #{details.names.join(", ")}" unless details.names.empty?

        if @config.details || @config.secrets
          details.commits.each do |repo, commits|
            puts "  #{CYAN}#{repo}#{RESET}"
            commits.first(5).each do |c|
              puts "    #{c.hash[0, 8]} #{c.author_date.to_s("%Y-%m-%d %H:%M")}"
              puts "      #{c.message.lines.first? || ""}"[0, 60]
              c.secrets.each do |s|
                puts "      #{RED}SECRET: #{s}#{RESET}"
              end
            end
            puts "    ... and #{commits.size - 5} more" if commits.size > 5
          end
        end
        puts
      end

      if @config.timestamp_analysis
        output_timestamp_analysis(emails, identifiers)
      end

      # External contributions section
      output_external_contributions(sorted, identifiers)

      # Summary section with target, similar, and stats
      output_summary(sorted, identifiers)
    end

    private def output_email_domains(sorted : Array(Tuple(String, Models::EmailDetails)))
      domain_counts = Hash(String, Int32).new(0)

      sorted.each do |email, _|
        if email.includes?("@")
          domain = email.split("@").last
          domain_counts[domain] += 1
        end
      end

      return if domain_counts.empty?

      puts "#{CYAN}#{BOLD}EMAIL DOMAINS#{RESET} (Top 10)"
      domain_counts.to_a.sort_by { |_, c| -c }.first(10).each do |domain, count|
        puts "  #{WHITE}#{domain}:#{RESET} #{count} contributors"
      end
      puts
    end

    private def output_external_contributions(sorted : Array(Tuple(String, Models::EmailDetails)), identifiers : Set(String))
      # Collect target emails with external contributions
      external_data = [] of Tuple(String, Models::EmailDetails)

      sorted.each do |email, details|
        is_target = details.is_target || identifiers.includes?(email.downcase)
        if is_target && details.external_commit_count > 0
          external_data << {email, details}
        end
      end

      return if external_data.empty?

      total_external_repos = external_data.sum { |_, d| d.external_commits.size }
      total_external_commits = external_data.sum { |_, d| d.external_commit_count }
      total_own_commits = external_data.sum { |_, d| d.own_commit_count }
      total_commits = total_external_commits + total_own_commits
      external_pct = total_commits > 0 ? (total_external_commits.to_f / total_commits * 100).round(1) : 0.0

      puts
      puts "#{CYAN}#{BOLD}EXTERNAL CONTRIBUTIONS#{RESET}"
      puts "-" * 60
      puts "#{WHITE}External repositories:#{RESET} #{total_external_repos}"
      puts "#{WHITE}External commits:#{RESET} #{total_external_commits}"
      puts "#{WHITE}Own repo commits:#{RESET} #{total_own_commits}"
      puts "#{WHITE}External %:#{RESET} #{external_pct}%"
      puts

      external_data.each do |email, details|
        puts "#{GREEN}#{email}#{RESET}"
        puts "  Names: #{details.names.join(", ")}"
        puts "  #{WHITE}Repositories (#{details.external_commit_count} commits total):#{RESET}"
        details.external_commits.each do |repo, commits|
          puts "    - #{repo} (#{commits.size} commits)"
        end
        puts
      end
    end

    private def output_summary(sorted : Array(Tuple(String, Models::EmailDetails)), identifiers : Set(String))
      target_emails = sorted.select { |_, d| d.is_target }
      similar_emails = sorted.select { |_, d| d.is_similar && !d.is_target }

      total_target_commits = target_emails.sum { |_, d| d.commit_count }

      puts
      puts "#{CYAN}#{BOLD}SUMMARY#{RESET}"
      puts "-" * 60

      # Target accounts
      if target_emails.any?
        puts
        puts "#{GREEN}#{BOLD}Target Accounts:#{RESET}"
        target_emails.each do |email, details|
          puts "#{GREEN}#{email}#{RESET}"
          puts "  Names: #{details.names.join(", ")}"
        end
      end

      # Similar accounts (share names with target)
      if similar_emails.any?
        puts
        puts "#{YELLOW}#{BOLD}Similar Accounts:#{RESET} (share names with target)"
        similar_emails.first(10).each do |email, details|
          puts "#{YELLOW}#{email}#{RESET}"
          puts "  Names: #{details.names.join(", ")}"
        end
        if similar_emails.size > 10
          puts "  ... and #{similar_emails.size - 10} more similar accounts"
        end
      end

      puts
      puts "#{WHITE}Target accounts:#{RESET} #{target_emails.size}"
      puts "#{WHITE}Similar accounts:#{RESET} #{similar_emails.size}"
      puts "#{WHITE}Total target commits:#{RESET} #{total_target_commits}"
      puts "#{WHITE}Total contributors:#{RESET} #{sorted.size}"
    end

    private def output_timestamp_analysis(emails : Hash(String, Models::EmailDetails), identifiers : Set(String))
      all_commits = [] of Models::CommitInfo

      emails.each do |email, details|
        next unless details.is_target || identifiers.includes?(email.downcase)
        details.commits.each_value do |commits|
          all_commits.concat(commits)
        end
      end

      return if all_commits.empty?

      patterns = Timestamp.get_patterns(all_commits)

      puts
      puts "#{CYAN}#{BOLD}TIMESTAMP ANALYSIS#{RESET} (#{patterns.total_commits} commits)"
      puts "-" * 40
      puts "#{YELLOW}Unusual hours (10pm-6am):#{RESET} #{patterns.unusual_hour_pct}%"
      puts "#{CYAN}Weekend commits:#{RESET} #{patterns.weekend_pct}%"
      puts "#{BLUE}Night owl (10pm-2am):#{RESET} #{patterns.night_owl_pct}%"
      puts "#{GREEN}Early bird (5am-7am):#{RESET} #{patterns.early_bird_pct}%"
      puts "#{WHITE}Most active hour:#{RESET} #{patterns.most_active_hour}:00"
      puts "#{WHITE}Most active day:#{RESET} #{patterns.most_active_day}"

      if patterns.timezone_distribution.size > 1
        puts "#{YELLOW}Timezones: #{patterns.timezone_distribution.size} detected#{RESET}"
        patterns.timezone_distribution.to_a.sort_by { |_, c| -c }.first(3).each do |tz, count|
          puts "  #{tz}: #{count} commits"
        end
      end

      if patterns.total_commits >= 10
        puts
        puts "#{WHITE}Hourly activity:#{RESET}"
        max_count = patterns.hour_distribution.values.max? || 1
        (0..23).each do |hour|
          count = patterns.hour_distribution[hour]? || 0
          bar_len = (count.to_f / max_count * 30).to_i
          bar = "#" * bar_len
          color = case hour
                  when 22..23, 0..2 then RED
                  when 5..7         then GREEN
                  when 9..17        then BLUE
                  else                   YELLOW
                  end
          printf "%02d:00 |%s%s%s %d\n", hour, color, bar.ljust(30), RESET, count
        end
      end
      puts
    end

    private def output_json(emails : Hash(String, Models::EmailDetails), user : Models::User, is_org : Bool)
      sorted = emails.to_a.sort_by { |_, d| -d.commit_count }

      JSON.build(STDOUT, indent: 2) do |json|
        json.object do
          json.field "target", @config.target
          json.field "is_org", is_org
          json.field "user" { user.to_json_output(json) }
          json.field "emails" do
            json.array do
              sorted.each do |email, details|
                json.object do
                  json.field "email", email
                  details.to_json(json)
                end
              end
            end
          end
          json.field "total_commits", sorted.sum { |_, d| d.is_target ? d.commit_count : 0 }
          json.field "total_contributors", emails.size
        end
      end
      puts
    end

    private def output_csv(emails : Hash(String, Models::EmailDetails))
      sorted = emails.to_a.sort_by { |_, d| -d.commit_count }

      CSV.build(STDOUT) do |csv|
        csv.row "email", "names", "is_target", "commit_count", "repository", "commit_hash", "commit_url", "author_name", "author_email", "author_date", "secrets_found"

        sorted.each do |email, details|
          names = details.names.join("; ")
          details.commits.each do |repo, commits|
            commits.each do |c|
              secrets = c.secrets.join(" | ")
              csv.row email, names, details.is_target, details.commit_count, repo, c.hash, c.url, c.author_name, c.author_email, c.author_date.to_rfc3339, secrets
            end
          end
        end
      end
    end
  end
end
