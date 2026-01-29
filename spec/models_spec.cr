require "./spec_helper"

describe Glint::Models::CommitInfo do
  it "initializes with default values" do
    commit = Glint::Models::CommitInfo.new
    commit.hash.should eq("")
    commit.url.should eq("")
    commit.author_name.should eq("")
    commit.secrets.should be_empty
  end

  it "can set properties" do
    commit = Glint::Models::CommitInfo.new
    commit.hash = "abc123"
    commit.author_name = "Test User"
    commit.author_email = "test@example.com"
    commit.message = "Fix bug"

    commit.hash.should eq("abc123")
    commit.author_name.should eq("Test User")
    commit.author_email.should eq("test@example.com")
    commit.message.should eq("Fix bug")
  end

  it "can store secrets" do
    commit = Glint::Models::CommitInfo.new
    commit.secrets << "AWS Key: AKIAIOSFODNN7EXAMPLE"
    commit.secrets << "GitHub Token: ghp_xxx"

    commit.secrets.size.should eq(2)
  end

  it "serializes to JSON" do
    commit = Glint::Models::CommitInfo.new
    commit.hash = "abc123"
    commit.url = "https://github.com/test/repo/commit/abc123"
    commit.author_name = "Test"
    commit.author_email = "test@example.com"
    commit.author_date = Time.utc(2024, 1, 15, 10, 0, 0)

    json = String.build do |io|
      builder = JSON::Builder.new(io)
      builder.document do
        commit.to_json(builder)
      end
    end
    json.should contain("abc123")
    json.should contain("test@example.com")
  end
end

describe Glint::Models::EmailDetails do
  it "initializes with empty collections" do
    details = Glint::Models::EmailDetails.new
    details.names.should be_empty
    details.commits.should be_empty
    details.commit_count.should eq(0)
    details.is_target.should be_false
  end

  it "can add names" do
    details = Glint::Models::EmailDetails.new
    details.names.add("John Doe")
    details.names.add("John")
    details.names.add("John Doe") # Duplicate

    details.names.size.should eq(2)
  end

  it "can group commits by repo" do
    details = Glint::Models::EmailDetails.new

    commit1 = Glint::Models::CommitInfo.new
    commit1.hash = "abc"
    commit2 = Glint::Models::CommitInfo.new
    commit2.hash = "def"

    details.commits["repo1"] = [commit1]
    details.commits["repo2"] = [commit2]

    details.commits.size.should eq(2)
    details.commits["repo1"].size.should eq(1)
  end
end

describe Glint::Models::TimestampAnalysis do
  it "initializes with default values" do
    ta = Glint::Models::TimestampAnalysis.new
    ta.is_unusual_hour.should be_false
    ta.is_weekend.should be_false
    ta.hour_of_day.should eq(0)
  end
end

describe Glint::Models::User do
  it "parses from JSON" do
    json = %({
      "login": "octocat",
      "name": "The Octocat",
      "email": "octocat@github.com",
      "company": "@github",
      "location": "San Francisco",
      "bio": "A cat",
      "blog": "https://github.blog",
      "twitter_username": "octocat",
      "public_repos": 8,
      "public_gists": 8,
      "followers": 1000,
      "following": 5,
      "type": "User",
      "created_at": "2011-01-25T00:00:00Z",
      "updated_at": "2024-01-15T00:00:00Z"
    })

    user = Glint::Models::User.from_json(json)
    user.login.should eq("octocat")
    user.name.should eq("The Octocat")
    user.email.should eq("octocat@github.com")
    user.company.should eq("@github")
    user.public_repos.should eq(8)
    user.followers.should eq(1000)
    user.type.should eq("User")
  end

  it "handles missing optional fields" do
    json = %({
      "login": "minimal",
      "type": "User",
      "created_at": "2024-01-01T00:00:00Z",
      "updated_at": "2024-01-01T00:00:00Z"
    })

    user = Glint::Models::User.from_json(json)
    user.login.should eq("minimal")
    user.name.should eq("")
    user.email.should eq("")
  end
end

describe Glint::Models::Repository do
  it "parses from RepositoryResponse" do
    json = %({
      "name": "hello-world",
      "full_name": "octocat/hello-world",
      "fork": false,
      "owner": {"login": "octocat"}
    })

    response = Glint::Models::RepositoryResponse.from_json(json)
    repo = response.to_repository

    repo.name.should eq("hello-world")
    repo.full_name.should eq("octocat/hello-world")
    repo.fork.should be_false
    repo.owner.should eq("octocat")
  end

  it "identifies forks" do
    json = %({
      "name": "fork-repo",
      "full_name": "user/fork-repo",
      "fork": true,
      "owner": {"login": "user"}
    })

    response = Glint::Models::RepositoryResponse.from_json(json)
    repo = response.to_repository

    repo.fork.should be_true
  end
end

describe Glint::Models::RateLimit do
  it "stores rate limit info" do
    reset = Time.utc(2024, 1, 15, 12, 0, 0)
    rl = Glint::Models::RateLimit.new(5000, 4500, reset)

    rl.limit.should eq(5000)
    rl.remaining.should eq(4500)
    rl.reset_at.should eq(reset)
  end
end
