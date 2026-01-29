module Glint::Timestamp
  def self.analyze(time : Time) : Models::TimestampAnalysis
    a = Models::TimestampAnalysis.new

    a.hour_of_day = time.hour
    a.day_of_week = time.day_of_week
    a.local_hour = time.hour
    a.commit_timezone = time.location.to_s

    a.is_unusual_hour = time.hour >= 22 || time.hour <= 6
    a.is_weekend = time.day_of_week.saturday? || time.day_of_week.sunday?
    a.is_night_owl = time.hour >= 22 || time.hour <= 2
    a.is_early_bird = time.hour >= 5 && time.hour <= 7

    if a.is_unusual_hour
      a.timezone_hint = "Commit at unusual hour (#{time.hour}:00)"
    end

    a
  end

  struct Patterns
    property total_commits : Int32 = 0
    property unusual_hour_pct : Float64 = 0.0
    property weekend_pct : Float64 = 0.0
    property night_owl_pct : Float64 = 0.0
    property early_bird_pct : Float64 = 0.0
    property most_active_hour : Int32 = 0
    property most_active_day : Time::DayOfWeek = Time::DayOfWeek::Monday
    property timezone_distribution : Hash(String, Int32) = {} of String => Int32
    property hour_distribution : Hash(Int32, Int32) = {} of Int32 => Int32
  end

  def self.get_patterns(commits : Array(Models::CommitInfo)) : Patterns
    p = Patterns.new
    p.total_commits = commits.size
    return p if commits.empty?

    unusual = 0
    weekend = 0
    night_owl = 0
    early_bird = 0
    hour_counts = Hash(Int32, Int32).new(0)
    day_counts = Hash(Time::DayOfWeek, Int32).new(0)
    tz_counts = Hash(String, Int32).new(0)

    commits.each do |c|
      ta = c.timestamp_analysis
      next unless ta

      unusual += 1 if ta.is_unusual_hour
      weekend += 1 if ta.is_weekend
      night_owl += 1 if ta.is_night_owl
      early_bird += 1 if ta.is_early_bird

      hour_counts[ta.hour_of_day] += 1
      day_counts[ta.day_of_week] += 1
      tz_counts[ta.commit_timezone] += 1 unless ta.commit_timezone.empty?
    end

    total = commits.size.to_f
    p.unusual_hour_pct = (unusual / total * 100).round(1)
    p.weekend_pct = (weekend / total * 100).round(1)
    p.night_owl_pct = (night_owl / total * 100).round(1)
    p.early_bird_pct = (early_bird / total * 100).round(1)

    max_hour = 0
    max_hour_count = 0
    hour_counts.each do |h, c|
      if c > max_hour_count
        max_hour = h
        max_hour_count = c
      end
    end
    p.most_active_hour = max_hour
    p.hour_distribution = hour_counts

    max_day = Time::DayOfWeek::Monday
    max_day_count = 0
    day_counts.each do |d, c|
      if c > max_day_count
        max_day = d
        max_day_count = c
      end
    end
    p.most_active_day = max_day

    p.timezone_distribution = tz_counts
    p
  end
end
