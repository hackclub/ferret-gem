#!/usr/bin/env bash
set -euo pipefail

FERRET_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$FERRET_DIR"

MODE="default"
BASE_REF="HEAD~1"

usage() {
  echo "Usage: $0 [--full | --integration] [--base REF]"
  echo ""
  echo "  (default)       Run specs only for changed files"
  echo "  --full          Run the entire spec suite"
  echo "  --integration   Run only integration specs (searcher, indexer)"
  echo "  --base REF      Git ref to diff against (default: HEAD~1)"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) MODE="full"; shift ;;
    --integration) MODE="integration"; shift ;;
    --base) BASE_REF="$2"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# --- Step 1: Gem build check (always runs, fast) ---
echo "=== Checking gem build ==="
gem build ferret.gemspec --silent
rm -f ferret-*.gem
echo "  ✓ gemspec is valid"
echo ""

# --- Step 2: Rubocop (always runs, fast) ---
echo "=== Running rubocop ==="
bundle exec rubocop
echo ""

# --- Step 3: Figure out which specs to run ---
if [[ "$MODE" == "full" ]]; then
  echo "=== Running full spec suite ==="
  bundle exec rspec
  exit $?
fi

if [[ "$MODE" == "integration" ]]; then
  echo "=== Running integration specs ==="
  bundle exec rspec spec/ferret/indexer_spec.rb spec/ferret/searcher_spec.rb
  exit $?
fi

# --- Default: diff-based spec selection ---
echo "=== Detecting changed files (vs $BASE_REF) ==="
CHANGED_FILES=$(git diff --name-only "$BASE_REF" 2>/dev/null || echo "")

if [[ -z "$CHANGED_FILES" ]]; then
  echo "  No changed files detected, running full suite as fallback"
  bundle exec rspec
  exit $?
fi

echo "$CHANGED_FILES" | sed 's/^/  /'
echo ""

# Map source files to their spec files
declare -a SPECS_TO_RUN=()

map_to_spec() {
  local src="$1"
  local spec=""

  case "$src" in
    lib/ferret/configuration.rb)    spec="spec/ferret/configuration_spec.rb" ;;
    lib/ferret/database.rb)         spec="spec/ferret/database_spec.rb" ;;
    lib/ferret/indexer.rb)          spec="spec/ferret/indexer_spec.rb" ;;
    lib/ferret/searcher.rb)         spec="spec/ferret/searcher_spec.rb" ;;
    lib/ferret/searchable.rb)       spec="spec/ferret/searchable_spec.rb" ;;
    lib/ferret/jobs/*)              spec="spec/ferret/jobs/embed_record_job_spec.rb" ;;
    lib/ferret/railtie.rb)          spec="" ;; # no spec yet
    lib/ferret.rb)                  spec="spec/" ;; # main entrypoint: run all
    lib/ferret/version.rb)          spec="" ;; # version bump, no spec needed
    lib/generators/*)               spec="" ;; # generator, no spec yet
    spec/*)                         spec="$src" ;; # spec changed, run itself
    ferret.gemspec)                 spec="" ;; # already validated by gem build
    Gemfile)                        spec="" ;; # dependency change, no spec
    README.md|LICENSE|.rspec|.gitignore) spec="" ;; # docs/config, no spec
    *)                              spec="" ;;
  esac

  echo "$spec"
}

for file in $CHANGED_FILES; do
  spec=$(map_to_spec "$file")
  if [[ -n "$spec" ]]; then
    # Avoid duplicates
    if [[ ! " ${SPECS_TO_RUN[*]:-} " =~ " $spec " ]]; then
      SPECS_TO_RUN+=("$spec")
    fi
  fi
done

if [[ ${#SPECS_TO_RUN[@]} -eq 0 ]]; then
  echo "=== No specs to run for these changes ==="
  echo "  (Only non-code files changed)"
  exit 0
fi

echo "=== Running specs ==="
for spec in "${SPECS_TO_RUN[@]}"; do
  echo "  → $spec"
done
echo ""

bundle exec rspec "${SPECS_TO_RUN[@]}"
