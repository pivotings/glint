
                            G L I N T
                            =========

                Git Log Intelligence - GitHub OSINT Tool
                           Version 0.1.0

WHAT IS THIS?

Glint is a command-line tool for analyzing GitHub commit history and
user activity. It's useful for OSINT, security research, and general
snooping on developer habits.

Features:
  * Analyze GitHub user/organization commit history
  * Detect secrets in commits (AWS keys, tokens, API keys, etc.)
  * Find interesting patterns (UUIDs, IPs, URLs)
  * Timestamp analysis for commit behavior patterns
  * Multiple output formats (text, JSON, CSV)
  * Email-based user discovery


REQUIREMENTS

* Crystal >= 1.0
* GitHub personal access token (for API access)
* A terminal


INSTALLATION

FROM SOURCE:

  $ git clone https://github.com/pivotings/glint
  $ cd glint
  $ shards build --release
  $ sudo cp bin/glint /usr/local/bin/

FROM RELEASES:

  Prebuilt binaries available at:
  https://github.com/pivotings/glint/releases

  Linux x86_64:
    $ curl -L https://github.com/pivotings/glint/releases/latest/download/glint-linux-x86_64.tar.gz | tar xz
    $ sudo mv glint-linux-x86_64 /usr/local/bin/glint

  macOS ARM:
    $ curl -L https://github.com/pivotings/glint/releases/latest/download/glint-macos-arm64.tar.gz | tar xz
    $ sudo mv glint-macos-arm64 /usr/local/bin/glint

USAGE

SYNOPSIS

  glint [options] <username|email>

OPTIONS

  -t, --token=TOKEN          GitHub personal access token
  -d, --details              Show detailed commit info
  -s, --secrets              Scan for secrets in commits
  -i, --interesting          Show interesting strings (UUIDs, IPs, etc.)
  -S, --show-stargazers      Show repository stargazers
  -f, --show-forkers         Show repository forkers
  -j, --json                 JSON output
      --csv                  CSV output
  -p, --profile-only         Show profile only, skip repository analysis
  -q, --quick                Quick mode (~50 commits per repo)
  -T, --timestamp-analysis   Analyze commit timestamps
  -F, --include-forks        Include forked repositories
  -v, --version              Show version
  -h, --help                 Show help

EXAMPLES

  Basic user scan:
    $ glint torvalds

  Quick scan with secrets detection:
    $ glint -q -s username

  JSON output for automation:
    $ glint -j -q username > output.json

  Profile only (no repo scanning):
    $ glint -p username

  Full analysis with timestamp patterns:
    $ glint -d -s -T username


CONFIGURATION

ENVIRONMENT VARIABLES

  GITHUB_GLINT_API_KEY     GitHub personal access token

If no token is set, glint will prompt for interactive setup on first run.


SECRET DETECTION

Glint can detect the following secret types in commit diffs:

  * AWS Access Keys
  * GitHub Tokens (classic & fine-grained)
  * Private Keys (PEM format)
  * Stripe API Keys
  * Slack Tokens
  * Azure Storage Keys
  * GCP Service Account Keys
  * MongoDB Connection Strings
  * PostgreSQL Connection Strings
  * Generic secrets/passwords


DEVELOPMENT

Run tests:
  $ crystal spec

Build debug:
  $ shards build

Build release:
  $ shards build --release --no-debug

Format code:
  $ crystal tool format


FILES

src/glint.cr           Entry point, CLI argument parsing
src/glint/lib.cr       Orchestrator, Config class, core logic
src/glint/models.cr    Data structures (CommitInfo, User, etc.)
src/glint/github.cr    GitHub API client
src/glint/scanner.cr   Secret/pattern detection
src/glint/display.cr   Output formatting (text, JSON, CSV)
src/glint/timestamp.cr Commit timestamp analysis
src/glint/token.cr     Token detection and interactive setup


DISCLAIMER

This tool is intended for legitimate security research and OSINT
purposes only. Always respect GitHub's Terms of Service and applicable
laws. The authors are not responsible for misuse of this software.

