require "option_parser"
require "http/client"
require "json"
require "csv"
require "uri"

require "./models"
require "./scanner"
require "./github"
require "./display"
require "./timestamp"
require "./token"

module Glint
  VERSION = "0.1.0"

  class ResultsStore
    def initialize(@output_dir : String, @config : Config)
      Dir.mkdir_p(@output_dir) unless Dir.exists?(@output_dir)
    end

    def save_result(target : String, result : Hash(String, Models::EmailDetails), user : Models::User?, is_org : Bool?, error : String?)
      safe_name = target.gsub(/[^a-zA-Z0-9]/, "_")
      json_path = File.join(@output_dir, "#{safe_name}.json")
      txt_path = File.join(@output_dir, "#{safe_name}.txt")

      JSON.build(File.open(json_path)) do |json|
        json.object do
          json.field "target", target
          json.field "timestamp", Time.utc.to_s
          json.field "error", error if error
          if user && !error
            json.field "found", true
            json.field "is_org", is_org
            json.field "user" { user.to_json_output(json) }
            json.field "results" do
              json.array do
                result.each do |email, details|
                  json.object do
                    json.field "email", email
                    details.to_json(json)
                  end
                end
              end
            end
          end
        end
      end

      unless error || user.nil?
        File.open(txt_path, "w") do |f|
          f.puts "Target: #{target}"
          f.puts "=" * 50
          if is_org
            f.puts "Organization: #{user.login}"
          else
            f.puts "User: #{user.login}"
          end
          f.puts "Name: #{user.name}" unless user.name.empty?
          f.puts "Email: #{user.email}" unless user.email.empty?
          f.puts
          f.puts "Contributors: #{result.size}"
          f.puts "-" * 50
          result.each do |email, details|
            marker = details.is_target ? "[TARGET]" : (details.is_similar ? "[SIMILAR]" : "")
            f.puts "#{marker} #{email} (#{details.commit_count} commits)"
            f.puts "  Names: #{details.names.join(", ")}" unless details.names.empty?
          end
        end
      end
    end

    def save_summary(summary : Array(Tuple(String, Bool, String?)))
      summary_path = File.join(@output_dir, "_summary.json")
      JSON.build(File.open(summary_path)) do |json|
        json.object do
          json.field "generated_at", Time.utc.to_s
          json.field "total_targets", summary.size
          json.field "successful", summary.count { |_, found, _| found }
          json.field "failed", summary.count { |_, found, _| !found }
          json.field "targets" do
            json.array do
              summary.each do |target, found, error|
                json.object do
                  json.field "target", target
                  json.field "found", found
                  json.field "error", error if error
                end
              end
            end
          end
        end
      end
    end
  end

  class Config
    property token : String = ""
    property target : String = ""
    property list_file : String = ""
    property output_dir : String = ""
    property concurrent : Int32 = 4
    property details : Bool = false
    property secrets : Bool = false
    property interesting : Bool = false
    property show_stargazers : Bool = false
    property show_forkers : Bool = false
    property json : Bool = false
    property csv : Bool = false
    property profile_only : Bool = false
    property quick : Bool = false
    property timestamp_analysis : Bool = false
    property include_forks : Bool = false

    def batch_mode? : Bool
      !@list_file.empty?
    end

    def output_format : Symbol
      return :json if @json
      return :csv if @csv
      :text
    end
  end

  class Orchestrator
    def initialize(@config : Config)
      @client = GitHub::Client.new(@config.token)
      @display = Display.new(@config)
    end

    def run
      if @config.batch_mode?
        run_batch
      else
        run_single
      end
    end

    def run_batch
      list_path = @config.list_file
      unless File.exists?(list_path)
        @display.error("List file not found: #{list_path}")
        return
      end

      targets = File.read_lines(list_path).map(&.strip).reject(&.empty?)
      if targets.empty?
        @display.error("No targets found in list file")
        return
      end

      @display.info("Batch mode: #{targets.size} targets from #{list_path}")
      @display.info("Output directory: #{@config.output_dir}")
      @display.info("Concurrent workers: #{@config.concurrent}")

      store = ResultsStore.new(@config.output_dir, @config)
      channel = Channel(Tuple(String, Bool, String?)).new

      batch_size = ((targets.size + @config.concurrent - 1) / @config.concurrent).to_i32
      targets.each_slice(batch_size) do |batch|
        spawn do
          batch.each do |target|
            result = process_target(target)
            channel.send(result)
          end
        end
      end

      completed = 0
      total = targets.size
      results = [] of Tuple(String, Bool, String?)

      total.times do
        result = channel.receive
        results << result
        completed += 1
        @display.progress("Processing: #{completed}/#{total}")
      end

      store.save_summary(results)

      puts
      @display.success("Completed #{completed}/#{total} targets")
      @display.info("Results saved to: #{@config.output_dir}")
    end

    def run_single
      target = @config.target
      lookup_email = ""

      if target.includes?("@")
        lookup_email = target
        @display.info("Target Email: #{target}")
        user = @client.search_user_by_email(target)
        if user
          target = user.login
          @display.success("Found GitHub account: #{target}")
        else
          @display.warn("Email not public, attempting reverse lookup...")
          if username = @client.resolve_email_by_spoof(target)
            target = username
            @display.success("Found GitHub account: #{target}")
          else
            @display.error("No GitHub user found for email: #{target}")
            return {target, false, "User not found"}
          end
        end
      else
        @display.info("Target Username: #{target}")
      end

      user = @client.get_user(target)
      unless user
        @display.error("User not found: #{target}")
        return {target, false, "User not found"}
      end

      is_org = user.type == "Organization"
      @display.user_info(user, is_org)

      return {target, true, nil} if @config.profile_only

      repos = if is_org
                @client.get_org_repos(target, @config.include_forks)
              else
                @client.get_user_repos(target, @config.include_forks)
              end

      if repos.empty?
        @display.warn("No repositories found")
        return {target, true, nil}
      end

      @display.info("Found #{repos.size} repositories")

      emails = {} of String => Models::EmailDetails
      user_identifiers = build_user_identifiers(target, lookup_email, user)

      total_repos = repos.size
      repos.each_with_index do |repo, idx|
        @display.progress_bar("Processing repositories", idx + 1, total_repos, repo.full_name)
        commits = @client.get_commits(repo.owner, repo.name, @config.quick)

        is_external_repo = repo.owner.downcase != target.downcase

        commits.each do |commit|
          if @config.secrets || @config.interesting
            scan_commit(commit, repo)
          end

          if @config.timestamp_analysis
            commit.timestamp_analysis = Timestamp.analyze(commit.author_date)
          end

          email = commit.author_email
          next if email.empty?

          details = emails[email]? || Models::EmailDetails.new
          details.names.add(commit.author_name) unless commit.author_name.empty?

          if is_external_repo
            commit.is_external = true
            details.external_commits[repo.full_name] ||= [] of Models::CommitInfo
            details.external_commits[repo.full_name] << commit
            details.external_commit_count += 1
          else
            commit.is_own_repo = true
            details.commits[repo.full_name] ||= [] of Models::CommitInfo
            details.commits[repo.full_name] << commit
            details.own_commit_count += 1
          end

          details.commit_count += 1
          details.is_target = user_identifiers.includes?(email.downcase) ||
                              user_identifiers.includes?(commit.author_name.downcase)
          emails[email] = details
        end
      end

      mark_similar_accounts(emails, user_identifiers)

      if emails.empty?
        @display.warn("No commits found")
      end

      @display.results(emails, user, is_org, user_identifiers)
      @display.rate_limit(@client.rate_limit)
      {target, true, nil}
    end

    private def process_target(target : String) : Tuple(String, Bool, String?)
      client = GitHub::Client.new(@config.token)
      display = Display.new(@config)

      lookup_email = ""

      if target.includes?("@")
        lookup_email = target
        display.info("Target Email: #{target}")
        user = client.search_user_by_email(target)
        if user
          target = user.login
          display.success("Found GitHub account: #{target}")
        else
          display.warn("Email not public, attempting reverse lookup...")
          if username = client.resolve_email_by_spoof(target)
            target = username
            display.success("Found GitHub account: #{target}")
          else
            display.error("No GitHub user found for email: #{target}")
            return {target, false, "User not found"}
          end
        end
      else
        display.info("Target Username: #{target}")
      end

      user = client.get_user(target)
      unless user
        display.error("User not found: #{target}")
        return {target, false, "User not found"}
      end

      is_org = user.type == "Organization"

      return {target, true, nil} if @config.profile_only

      repos = if is_org
                client.get_org_repos(target, @config.include_forks)
              else
                client.get_user_repos(target, @config.include_forks)
              end

      if repos.empty?
        return {target, true, nil}
      end

      emails = {} of String => Models::EmailDetails
      user_identifiers = build_user_identifiers(target, lookup_email, user)

      repos.each do |repo|
        commits = client.get_commits(repo.owner, repo.name, @config.quick)

        is_external_repo = repo.owner.downcase != target.downcase

        commits.each do |commit|
          if @config.secrets || @config.interesting
            content = client.get_commit_content(repo.owner, repo.name, commit.hash)
            unless content.empty?
              scanner = Scanner.new(@config.secrets, @config.interesting)
              scanner.scan(content).each do |m|
                commit.secrets << "#{m.name}: #{m.value}"
              end
            end
          end

          if @config.timestamp_analysis
            commit.timestamp_analysis = Timestamp.analyze(commit.author_date)
          end

          email = commit.author_email
          next if email.empty?

          details = emails[email]? || Models::EmailDetails.new
          details.names.add(commit.author_name) unless commit.author_name.empty?

          if is_external_repo
            commit.is_external = true
            details.external_commits[repo.full_name] ||= [] of Models::CommitInfo
            details.external_commits[repo.full_name] << commit
            details.external_commit_count += 1
          else
            commit.is_own_repo = true
            details.commits[repo.full_name] ||= [] of Models::CommitInfo
            details.commits[repo.full_name] << commit
            details.own_commit_count += 1
          end

          details.commit_count += 1
          details.is_target = user_identifiers.includes?(email.downcase) ||
                              user_identifiers.includes?(commit.author_name.downcase)
          emails[email] = details
        end
      end

      mark_similar_accounts(emails, user_identifiers)

      if @config.batch_mode? && !@config.output_dir.empty?
        store = ResultsStore.new(@config.output_dir, @config)
        store.save_result(target, emails, user, is_org, nil)
      end

      {target, true, nil}
    rescue ex
      {target, false, ex.message}
    end

    private def build_user_identifiers(username : String, email : String, user : Models::User) : Set(String)
      ids = Set(String).new
      ids.add(username.downcase)
      ids.add(email.downcase) unless email.empty?
      ids.add(user.login.downcase)
      ids.add(user.name.downcase) unless user.name.empty?
      ids.add(user.email.downcase) unless user.email.empty?
      ids.add("#{user.login.downcase}@users.noreply.github.com")

      ids
    end

    private def scan_commit(commit : Models::CommitInfo, repo : Models::Repository)
      content = @client.get_commit_content(repo.owner, repo.name, commit.hash)
      return if content.empty?

      scanner = Scanner.new(@config.secrets, @config.interesting)
      matches = scanner.scan(content)
      matches.each do |m|
        commit.secrets << "#{m.name}: #{m.value}"
      end
    end

    private def mark_similar_accounts(emails : Hash(String, Models::EmailDetails), identifiers : Set(String))
      target_username = identifiers.first? || ""

      mark_matching_github_ids(emails)

      changed = true
      iterations = 0
      max_iterations = 10

      while changed && iterations < max_iterations
        changed = false
        iterations += 1

        target_names = Set(String).new
        emails.each do |email, details|
          if details.is_target
            details.names.each do |n|
              normalized = n.downcase.strip
              next if normalized.size < 3
              next if %w[hi test user admin root github-actions bot].includes?(normalized)
              target_names.add(normalized)
            end
          end
        end

        identifiers.each { |id| target_names.add(id) if id.size >= 3 }

        emails.each do |email, details|
          next if details.is_target

          shared_names = details.names.select { |n|
            normalized = n.downcase.strip
            normalized.size >= 3 && target_names.includes?(normalized)
          }
          shared_count = shared_names.size

          email_user = email.split("@").first.downcase
          email_user = email_user.gsub(/^\d+\+/, "")
          username_match = email_user.size >= 3 && target_names.includes?(email_user)

          name_contains_username = details.names.any? { |n|
            n.downcase.includes?(target_username) && target_username.size >= 3
          }

          fuzzy_match = details.names.any? { |n| fuzzy_name_match?(n, target_names) }

          if shared_count >= 2 || (shared_count >= 1 && username_match) || (shared_count >= 1 && name_contains_username)
            details.is_target = true
            changed = true
          elsif shared_count >= 1 || username_match || fuzzy_match
            details.is_similar = true
          end
        end
      end
    end

    private def fuzzy_name_match?(name : String, target_names : Set(String)) : Bool
      normalized = name.downcase.strip
      return false if normalized.size < 4

      base_name = normalized.gsub(/\d+$/, "")
      return true if base_name.size >= 4 && target_names.includes?(base_name)

      %w[_ - . alt backup old new dev test].each do |suffix|
        stripped = normalized.chomp(suffix)
        return true if stripped.size >= 4 && target_names.includes?(stripped)
      end

      target_names.each do |target|
        next if target.size < 4
        if normalized.starts_with?(target) && normalized.size > target.size
          return true
        end
        if normalized.ends_with?(target) && normalized.size > target.size
          return true
        end
      end

      false
    end

    private def extract_github_user_id(email : String) : String?
      return nil unless email.ends_with?("@users.noreply.github.com")

      local_part = email.split("@").first
      if match = local_part.match(/^(\d+)\+/)
        return match[1]
      end
      nil
    end

    private def mark_matching_github_ids(emails : Hash(String, Models::EmailDetails))
      target_github_ids = Set(String).new

      emails.each do |email, details|
        if details.is_target
          if github_id = extract_github_user_id(email)
            target_github_ids.add(github_id)
          end
        end
      end

      emails.each do |email, details|
        next if details.is_target

        if github_id = extract_github_user_id(email)
          if target_github_ids.includes?(github_id)
            details.is_target = true
          end
        end
      end
    end
  end
end
