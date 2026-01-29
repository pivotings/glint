require "http/client"
require "json"
require "base64"
require "file_utils"

module Glint::GitHub
  EMAIL_REGEX = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/

  class Client
    API_BASE = "https://api.github.com"

    @rate_limit : Models::RateLimit = Models::RateLimit.new(5000, 5000, Time.utc)

    def initialize(@token : String = "")
    end

    def self.valid_email?(input : String) : Bool
      !!(input =~ EMAIL_REGEX)
    end

    def rate_limit : Models::RateLimit
      @rate_limit
    end

    def get_user(username : String) : Models::User?
      response = request("GET", "/users/#{username}")
      return nil unless response.status.success?
      Models::User.from_json(response.body)
    rescue
      nil
    end

    def search_user_by_email(email : String) : Models::User?
      response = request("GET", "/search/users?q=#{URI.encode_path_segment("in:email #{email}")}")
      return nil unless response.status.success?

      data = JSON.parse(response.body)
      items = data["items"]?.try(&.as_a)
      return nil if items.nil? || items.empty?

      login = items.first["login"]?.try(&.as_s)
      return nil unless login
      get_user(login)
    rescue
      nil
    end

    def get_user_repos(username : String, include_forks : Bool = false) : Array(Models::Repository)
      repos = [] of Models::Repository
      page = 1

      loop do
        response = request("GET", "/users/#{username}/repos?per_page=100&page=#{page}&type=all")
        break unless response.status.success?

        page_repos = Array(Models::RepositoryResponse).from_json(response.body)
        break if page_repos.empty?

        page_repos.each do |r|
          next if r.fork && !include_forks
          repos << r.to_repository
        end

        page += 1
        break if page_repos.size < 100
      end

      repos
    rescue
      [] of Models::Repository
    end

    def get_org_repos(org : String, include_forks : Bool = false) : Array(Models::Repository)
      repos = [] of Models::Repository
      page = 1

      loop do
        response = request("GET", "/orgs/#{org}/repos?per_page=100&page=#{page}")
        break unless response.status.success?

        page_repos = Array(Models::RepositoryResponse).from_json(response.body)
        break if page_repos.empty?

        page_repos.each do |r|
          next if r.fork && !include_forks
          repos << r.to_repository
        end

        page += 1
        break if page_repos.size < 100
      end

      repos
    rescue
      [] of Models::Repository
    end

    def get_commits(owner : String, repo : String, quick : Bool = false) : Array(Models::CommitInfo)
      commits = [] of Models::CommitInfo
      per_page = quick ? 50 : 100
      page = 1

      loop do
        response = request("GET", "/repos/#{owner}/#{repo}/commits?per_page=#{per_page}&page=#{page}")
        break unless response.status.success?

        data = JSON.parse(response.body)
        arr = data.as_a?
        break if arr.nil? || arr.empty?

        arr.each do |c|
          commit = parse_commit(c, repo)
          commits << commit if commit
        end

        break if quick
        page += 1
        break if arr.size < per_page
      end

      commits
    rescue
      [] of Models::CommitInfo
    end

    def get_commit_content(owner : String, repo : String, sha : String) : String
      response = request("GET", "/repos/#{owner}/#{repo}/commits/#{sha}")
      return "" unless response.status.success?

      data = JSON.parse(response.body)
      content = String.build do |s|
        if msg = data.dig?("commit", "message").try(&.as_s)
          s << msg << "\n"
        end
        if files = data["files"]?.try(&.as_a)
          files.each do |f|
            filename = f["filename"]?.try(&.as_s) || ""
            next if skip_file?(filename)
            if patch = f["patch"]?.try(&.as_s)
              s << patch << "\n"
            end
          end
        end
      end
      content
    rescue
      ""
    end

    def get_stargazers(owner : String, repo : String) : Array(String)
      users = [] of String
      page = 1

      loop do
        response = request("GET", "/repos/#{owner}/#{repo}/stargazers?per_page=100&page=#{page}")
        break unless response.status.success?

        data = JSON.parse(response.body)
        arr = data.as_a?
        break if arr.nil? || arr.empty?

        arr.each do |u|
          if login = u["login"]?.try(&.as_s)
            users << login
          end
        end

        page += 1
        break if arr.size < 100
      end

      users
    rescue
      [] of String
    end

    def get_forks(owner : String, repo : String) : Array(String)
      users = [] of String
      page = 1

      loop do
        response = request("GET", "/repos/#{owner}/#{repo}/forks?per_page=100&page=#{page}")
        break unless response.status.success?

        data = JSON.parse(response.body)
        arr = data.as_a?
        break if arr.nil? || arr.empty?

        arr.each do |f|
          if login = f.dig?("owner", "login").try(&.as_s)
            users << login
          end
        end

        page += 1
        break if arr.size < 100
      end

      users
    rescue
      [] of String
    end

    def resolve_email_by_spoof(email : String) : String?
      return nil if @token.empty?

      current_user = get_authenticated_user
      return nil unless current_user

      repo_name = "glint-tmp-#{Time.utc.to_unix}"
      owner = current_user

      unless create_temp_repo(repo_name)
        return nil
      end

      begin
        temp_dir = File.tempname("glint-spoof")
        Dir.mkdir_p(temp_dir)

        begin
          run_git(temp_dir, "init")
          run_git(temp_dir, "config", "user.email", email)
          run_git(temp_dir, "config", "user.name", "glint-lookup")

          File.write(File.join(temp_dir, "tmp.txt"), "glint email lookup")
          run_git(temp_dir, "add", "tmp.txt")
          run_git(temp_dir, "commit", "-m", "glint email lookup")
          run_git(temp_dir, "branch", "-M", "main")

          remote_url = "https://#{@token}@github.com/#{owner}/#{repo_name}.git"
          run_git(temp_dir, "remote", "add", "origin", remote_url)
          run_git(temp_dir, "push", "-u", "origin", "main")
        ensure
          FileUtils.rm_rf(temp_dir)
        end

        sleep 2.seconds

        username = get_commit_author_login(owner, repo_name)
        return username
      ensure
        delete_repo(owner, repo_name)
      end
    end

    private def get_authenticated_user : String?
      response = request("GET", "/user")
      return nil unless response.status.success?
      data = JSON.parse(response.body)
      data["login"]?.try(&.as_s)
    rescue
      nil
    end

    private def create_temp_repo(name : String) : Bool
      body = {
        "name"        => name,
        "private"     => true,
        "auto_init"   => false,
        "description" => "Temporary repo for glint email lookup - will be deleted",
      }.to_json

      response = request_with_body("POST", "/user/repos", body)
      response.status.success?
    rescue
      false
    end

    private def delete_repo(owner : String, name : String) : Bool
      response = request("DELETE", "/repos/#{owner}/#{name}")
      response.status.success? || response.status_code == 404
    rescue
      false
    end

    private def get_commit_author_login(owner : String, repo : String) : String?
      response = request("GET", "/repos/#{owner}/#{repo}/commits?per_page=1")
      return nil unless response.status.success?

      data = JSON.parse(response.body)
      arr = data.as_a?
      return nil if arr.nil? || arr.empty?

      commit = arr.first
      commit["author"]?.try(&.["login"]?).try(&.as_s)
    rescue
      nil
    end

    private def run_git(dir : String, *args : String)
      output = IO::Memory.new
      status = Process.run("git", args: args.to_a, chdir: dir, output: output, error: output)
      raise "git #{args.first} failed: #{output}" unless status.success?
    end

    private def request_with_body(method : String, path : String, body : String) : HTTP::Client::Response
      headers = HTTP::Headers{
        "Accept"       => "application/vnd.github.v3+json",
        "User-Agent"   => "glint/#{VERSION}",
        "Content-Type" => "application/json",
      }
      headers["Authorization"] = "Bearer #{@token}" unless @token.empty?

      HTTP::Client.exec(method, "#{API_BASE}#{path}", headers: headers, body: body)
    end

    private def request(method : String, path : String) : HTTP::Client::Response
      headers = HTTP::Headers{
        "Accept"     => "application/vnd.github.v3+json",
        "User-Agent" => "glint/#{VERSION}",
      }
      headers["Authorization"] = "Bearer #{@token}" unless @token.empty?

      response = HTTP::Client.exec(method, "#{API_BASE}#{path}", headers: headers)

      if limit = response.headers["X-RateLimit-Limit"]?
        remaining = response.headers["X-RateLimit-Remaining"]?
        reset = response.headers["X-RateLimit-Reset"]?
        if remaining && reset
          reset_time = Time.unix(reset.to_i64)
          @rate_limit = Models::RateLimit.new(limit.to_i, remaining.to_i, reset_time)
        end
      end

      response
    end

    private def parse_commit(data : JSON::Any, repo : String) : Models::CommitInfo?
      commit_data = data["commit"]?
      return nil unless commit_data

      author = commit_data["author"]?
      committer = commit_data["committer"]?

      c = Models::CommitInfo.new
      c.hash = data["sha"]?.try(&.as_s) || ""
      c.url = data["html_url"]?.try(&.as_s) || ""
      c.message = commit_data["message"]?.try(&.as_s) || ""
      c.repo_name = repo

      if author
        c.author_name = author["name"]?.try(&.as_s) || ""
        c.author_email = author["email"]?.try(&.as_s) || ""
        if date_str = author["date"]?.try(&.as_s)
          c.author_date = Time.parse_rfc3339(date_str) rescue Time.utc
        end
      end

      if committer
        c.committer_name = committer["name"]?.try(&.as_s) || ""
        c.committer_email = committer["email"]?.try(&.as_s) || ""
        if date_str = committer["date"]?.try(&.as_s)
          c.committer_date = Time.parse_rfc3339(date_str) rescue Time.utc
        end
      end

      c
    end

    private def skip_file?(filename : String) : Bool
      return true if filename.includes?("/node_modules/") || filename.starts_with?("node_modules/")
      return true if filename.ends_with?(".lock")

      skip_files = %w[
        package.json package-lock.json npm-shrinkwrap.json .npmrc
        yarn.lock .yarnrc .yarnrc.yml
        pnpm-lock.yaml .pnpmrc
        Gemfile Gemfile.lock
        go.mod go.sum
        Cargo.lock
      ]
      skip_files.includes?(filename.split("/").last)
    end
  end
end
