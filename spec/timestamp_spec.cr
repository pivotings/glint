require "./spec_helper"

describe Glint::Timestamp do
  describe ".analyze" do
    it "marks late night commits as unusual" do
      time = Time.utc(2024, 1, 15, 23, 30, 0)
      result = Glint::Timestamp.analyze(time)
      result.is_unusual_hour.should be_true
      result.is_night_owl.should be_true
    end

    it "marks early morning commits as unusual" do
      time = Time.utc(2024, 1, 15, 3, 0, 0)
      result = Glint::Timestamp.analyze(time)
      result.is_unusual_hour.should be_true
    end

    it "marks normal hours as not unusual" do
      time = Time.utc(2024, 1, 15, 14, 30, 0)
      result = Glint::Timestamp.analyze(time)
      result.is_unusual_hour.should be_false
    end

    it "detects weekend commits" do
      # Saturday
      time = Time.utc(2024, 1, 13, 10, 0, 0)
      result = Glint::Timestamp.analyze(time)
      result.is_weekend.should be_true

      # Sunday
      time = Time.utc(2024, 1, 14, 10, 0, 0)
      result = Glint::Timestamp.analyze(time)
      result.is_weekend.should be_true
    end

    it "marks weekdays as not weekend" do
      # Monday
      time = Time.utc(2024, 1, 15, 10, 0, 0)
      result = Glint::Timestamp.analyze(time)
      result.is_weekend.should be_false
    end

    it "detects early bird commits" do
      time = Time.utc(2024, 1, 15, 6, 0, 0)
      result = Glint::Timestamp.analyze(time)
      result.is_early_bird.should be_true
    end

    it "correctly captures hour of day" do
      time = Time.utc(2024, 1, 15, 14, 30, 0)
      result = Glint::Timestamp.analyze(time)
      result.hour_of_day.should eq(14)
    end

    it "correctly captures day of week" do
      # Monday
      time = Time.utc(2024, 1, 15, 10, 0, 0)
      result = Glint::Timestamp.analyze(time)
      result.day_of_week.should eq(Time::DayOfWeek::Monday)
    end
  end

  describe ".get_patterns" do
    it "returns empty patterns for empty commits" do
      commits = [] of Glint::Models::CommitInfo
      patterns = Glint::Timestamp.get_patterns(commits)
      patterns.total_commits.should eq(0)
    end

    it "calculates percentages correctly" do
      commits = [] of Glint::Models::CommitInfo

      # Create 10 commits: 3 at unusual hours
      10.times do |i|
        c = Glint::Models::CommitInfo.new
        hour = i < 3 ? 23 : 14 # 3 unusual, 7 normal
        c.author_date = Time.utc(2024, 1, 15, hour, 0, 0)
        c.timestamp_analysis = Glint::Timestamp.analyze(c.author_date)
        commits << c
      end

      patterns = Glint::Timestamp.get_patterns(commits)
      patterns.total_commits.should eq(10)
      patterns.unusual_hour_pct.should eq(30.0)
    end

    it "finds most active hour" do
      commits = [] of Glint::Models::CommitInfo

      # Create commits mostly at 14:00
      5.times do
        c = Glint::Models::CommitInfo.new
        c.author_date = Time.utc(2024, 1, 15, 14, 0, 0)
        c.timestamp_analysis = Glint::Timestamp.analyze(c.author_date)
        commits << c
      end

      2.times do
        c = Glint::Models::CommitInfo.new
        c.author_date = Time.utc(2024, 1, 15, 10, 0, 0)
        c.timestamp_analysis = Glint::Timestamp.analyze(c.author_date)
        commits << c
      end

      patterns = Glint::Timestamp.get_patterns(commits)
      patterns.most_active_hour.should eq(14)
    end
  end
end
