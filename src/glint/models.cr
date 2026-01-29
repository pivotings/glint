module Glint::Models
  class CommitInfo
    property hash : String = ""
    property url : String = ""
    property author_name : String = ""
    property author_email : String = ""
    property author_date : Time = Time.utc
    property committer_name : String = ""
    property committer_email : String = ""
    property committer_date : Time = Time.utc
    property message : String = ""
    property secrets : Array(String) = [] of String
    property is_own_repo : Bool = true
    property is_fork : Bool = false
    property is_external : Bool = false
    property repo_name : String = ""
    property timestamp_analysis : TimestampAnalysis? = nil

    def initialize
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "hash", @hash
        json.field "url", @url
        json.field "message", @message
        json.field "author_name", @author_name
        json.field "author_email", @author_email
        json.field "author_date", @author_date.to_rfc3339
        json.field "committer_name", @committer_name
        json.field "committer_email", @committer_email
        json.field "secrets", @secrets unless @secrets.empty?
      end
    end
  end

  class TimestampAnalysis
    property is_unusual_hour : Bool = false
    property is_weekend : Bool = false
    property hour_of_day : Int32 = 0
    property day_of_week : Time::DayOfWeek = Time::DayOfWeek::Monday
    property is_night_owl : Bool = false
    property is_early_bird : Bool = false
    property timezone_hint : String = ""
    property commit_timezone : String = ""
    property local_hour : Int32 = 0

    def initialize
    end
  end

  class EmailDetails
    property names : Set(String) = Set(String).new
    property commits : Hash(String, Array(CommitInfo)) = {} of String => Array(CommitInfo)
    property commit_count : Int32 = 0
    property is_target : Bool = false
    property is_similar : Bool = false
    property github_username : String = ""
    property external_commits : Hash(String, Array(CommitInfo)) = {} of String => Array(CommitInfo)
    property external_commit_count : Int32 = 0
    property own_commit_count : Int32 = 0

    def initialize
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "names", @names.to_a
        json.field "commit_count", @commit_count
        json.field "is_target", @is_target
        json.field "repositories" do
          json.array do
            @commits.each do |repo_name, commits|
              json.object do
                json.field "name", repo_name
                json.field "commits" do
                  json.array do
                    commits.each { |c| c.to_json(json) }
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  class User
    include JSON::Serializable

    property login : String = ""
    property name : String = ""
    property email : String = ""
    property company : String = ""
    property location : String = ""
    property bio : String = ""
    property blog : String = ""
    property twitter_username : String = ""
    @[JSON::Field(key: "public_repos")]
    property public_repos : Int32 = 0
    @[JSON::Field(key: "public_gists")]
    property public_gists : Int32 = 0
    property followers : Int32 = 0
    property following : Int32 = 0
    property type : String = "User"
    @[JSON::Field(key: "created_at")]
    property created_at : Time = Time.utc
    @[JSON::Field(key: "updated_at")]
    property updated_at : Time = Time.utc

    def initialize
    end

    def to_json_output(json : JSON::Builder)
      json.object do
        json.field "login", @login
        json.field "name", @name unless @name.empty?
        json.field "email", @email unless @email.empty?
        json.field "company", @company unless @company.empty?
        json.field "location", @location unless @location.empty?
        json.field "bio", @bio unless @bio.empty?
        json.field "blog", @blog unless @blog.empty?
        json.field "twitter", @twitter_username unless @twitter_username.empty?
        json.field "followers", @followers
        json.field "following", @following
        json.field "public_repos", @public_repos
      end
    end
  end

  class Repository
    include JSON::Serializable

    property name : String = ""
    @[JSON::Field(key: "full_name")]
    property full_name : String = ""
    property fork : Bool = false
    property owner : String = ""

    def initialize
    end

    def after_initialize
      if @owner.empty? && !@full_name.empty?
        @owner = @full_name.split("/").first? || ""
      end
    end
  end

  class RepositoryResponse
    include JSON::Serializable

    property name : String = ""
    @[JSON::Field(key: "full_name")]
    property full_name : String = ""
    property fork : Bool = false
    property owner : OwnerInfo = OwnerInfo.new

    def to_repository : Repository
      repo = Repository.new
      repo.name = @name
      repo.full_name = @full_name
      repo.fork = @fork
      repo.owner = @owner.login
      repo
    end
  end

  class OwnerInfo
    include JSON::Serializable

    property login : String = ""

    def initialize
    end
  end

  class RateLimit
    property limit : Int32 = 0
    property remaining : Int32 = 0
    property reset_at : Time = Time.utc

    def initialize(@limit, @remaining, @reset_at)
    end
  end
end
