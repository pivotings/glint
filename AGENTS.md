# AGENTS.md - Glint Development Guide

Guidelines for AI agents working on this Crystal codebase.

## Critical Rules

**NO COMMENTS**: Never write comments in this codebase. No inline comments, no block comments, no documentation comments. Code should be self-documenting through clear naming and structure. This rule has no exceptions.

## Build & Test Commands

```bash
# Install dependencies
shards install

# Build debug binary
shards build

# Build release binary
shards build --release --no-debug

# Run all tests
crystal spec

# Run single test file
crystal spec spec/scanner_spec.cr

# Run specific test by line number
crystal spec spec/scanner_spec.cr:5

# Run tests matching description
crystal spec --example "detects AWS"

# Format code
crystal tool format

# Check formatting (CI uses this)
crystal tool format --check

# Type check without building
crystal build --no-codegen src/glint.cr
```

## Project Structure

```
src/
  glint.cr           # Entry point, CLI argument parsing
  glint/
    lib.cr           # Orchestrator, Config class, core logic
    models.cr        # Data structures (CommitInfo, User, Repository, etc.)
    github.cr        # GitHub API client
    scanner.cr       # Secret/pattern detection
    display.cr       # Output formatting (text, JSON, CSV)
    timestamp.cr     # Commit timestamp analysis
    token.cr         # Token detection and interactive setup
spec/
    spec_helper.cr   # Test setup, requires src/glint/lib
    *_spec.cr        # Test files mirror src structure
```

## Code Style

### Formatting
- Use `crystal tool format` - enforced in CI
- 2-space indentation
- No trailing whitespace
- Newline at end of file

### Imports
- Standard library first: `require "json"`, `require "http/client"`
- Local modules second: `require "./models"`, `require "./scanner"`
- Order: option_parser, http/client, json, csv, uri, then local files

### Naming Conventions
- **Classes/Modules**: PascalCase (`GitHubClient`, `TimestampAnalysis`)
- **Methods/Variables**: snake_case (`get_user`, `commit_count`)
- **Constants**: SCREAMING_SNAKE_CASE (`API_BASE`, `SECRET_PATTERNS`)
- **Predicates**: end with `?` (`found?`, `structured_output?`)
- **Boolean properties**: use `is_` prefix (`is_target`, `is_weekend`)

### Type Annotations
- Always annotate instance variables: `property token : String = ""`
- Always annotate method parameters: `def get_user(username : String)`
- Return types optional but recommended for public APIs
- Use `?` suffix for nilable returns: `def get_user(...) : Models::User?`

### Properties & Initialization
- Use `property` for read/write, `getter` for read-only
- Initialize with defaults: `property count : Int32 = 0`
- Empty initialize methods are fine when using property defaults

### Error Handling
- Use `rescue` without type for broad catches in API methods
- Return nil/empty collections on failure, don't raise
- Log errors to STDERR: `STDERR.puts "Error: #{ex.message}"`
- Exit with code 1 on fatal errors

### Null Safety
- Use `.try(&.method)` for safe navigation
- Use `||` for defaults: `data["key"]?.try(&.as_s) || ""`
- Prefer early returns: `return nil unless response.status.success?`

### Collections
- Initialize typed empty collections: `[] of String`, `{} of String => Int32`
- Use `Set(T)` for unique values: `Set(String).new`
- Hash default values: `Hash(String, Int32).new(0)`

## Module Organization

### Namespace Pattern
```crystal
module Glint
  class Config
    # ...
  end
end

module Glint::GitHub
  class Client
    # ...
  end
end

module Glint::Models
  class User
    # ...
  end
end
```

### JSON Serialization
- Include `JSON::Serializable` for API response parsing
- Use `@[JSON::Field(key: "snake_case")]` for field mapping
- Implement custom `to_json(json : JSON::Builder)` for output control

## Testing Patterns

### Spec Structure
```crystal
require "./spec_helper"

describe Glint::Scanner do
  describe "#scan" do
    it "detects AWS access keys" do
      scanner = Glint::Scanner.new(check_secrets: true)
      matches = scanner.scan("AKIAIOSFODNN7EXAMPLE")
      matches.size.should eq(1)
    end
  end
end
```

### Assertions
- `should eq(value)` - equality
- `should be_true` / `should be_false` - booleans
- `should be_empty` - empty collections
- `should contain("substring")` - string inclusion

### Test Data
- Use realistic but clearly fake data
- Example AWS key: `AKIAIOSFODNN7EXAMPLE`
- Example GitHub token: `ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

## Common Patterns

### API Pagination
```crystal
loop do
  response = request("GET", "/endpoint?per_page=100&page=#{page}")
  break unless response.status.success?
  items = parse(response.body)
  break if items.empty?
  # process items
  page += 1
  break if items.size < 100
end
```

### Safe JSON Parsing
```crystal
data = JSON.parse(response.body)
value = data["key"]?.try(&.as_s) || ""
nested = data.dig?("a", "b").try(&.as_s)
```

### ANSI Colors (Display)
```crystal
RESET  = "\e[0m"
RED    = "\e[31m"
GREEN  = "\e[32m"
puts "#{GREEN}Success#{RESET}"
```

## Git Workflow
- Main branch: `main`
- CI runs on push and PR
- All tests must pass
- Code must be formatted
