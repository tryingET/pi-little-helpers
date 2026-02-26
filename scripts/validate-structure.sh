#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Parse arguments
STAGED_ONLY=false
for arg in "$@"; do
  if [[ "$arg" == "--staged-only" ]]; then
    STAGED_ONLY=true
  fi
done

# Get list of staged files if --staged-only
if [[ "$STAGED_ONLY" == "true" ]]; then
  mapfile -t STAGED_FILES < <(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || echo "")
fi

# Helper to check if a file should be validated
should_check_file() {
  local file="$1"
  if [[ "$STAGED_ONLY" != "true" ]]; then
    return 0  # Check all files
  fi
  # Only check if file is staged
  for staged in "${STAGED_FILES[@]}"; do
    if [[ "./$staged" == "$file" || "$staged" == "${file#./}" ]]; then
      return 0
    fi
  done
  return 1  # Skip this file
}

required_files=(
  "README.md"
  "LICENSE"
  "CHANGELOG.md"
  "SECURITY.md"
  "CODE_OF_CONDUCT.md"
  "SUPPORT.md"
  "CONTRIBUTING.md"
  "AGENTS.md"
  "biome.jsonc"
  ".vscode/settings.json"
  ".copier-answers.yml"
  "prek.toml"
  ".github/CODEOWNERS"
  ".github/dependabot.yml"
  ".github/pull_request_template.md"
  ".github/VOUCHED.td"
  ".github/ISSUE_TEMPLATE/bug-report.yml"
  ".github/ISSUE_TEMPLATE/feature-request.yml"
  ".github/ISSUE_TEMPLATE/docs.yml"
  ".github/ISSUE_TEMPLATE/config.yml"
  ".github/workflows/ci.yml"
  ".github/workflows/release-check.yml"
  ".github/workflows/release-please.yml"
  ".github/workflows/publish.yml"
  ".github/workflows/vouch-check-pr.yml"
  ".github/workflows/vouch-manage.yml"
  ".release-please-config.json"
  ".release-please-manifest.json"
  "docs/org/operating_model.md"
  "docs/project/foundation.md"
  "docs/project/vision.md"
  "docs/project/incentives.md"
  "docs/project/resources.md"
  "docs/project/skills.md"
  "docs/project/strategic_goals.md"
  "docs/project/tactical_goals.md"
  "NEXT_SESSION_PROMPT.md"
  "docs/dev/status.md"
  "docs/tech-stack.local.md"
  "docs/dev/CONTRIBUTING.md"
  "docs/dev/EXTENSION_SOP.md"
  "policy/stack-lane.json"
  ".pi/prompts/commit.md"
  "scripts/sync-to-live.sh"
  "scripts/install-hooks.sh"
  "scripts/docs-list.sh"
  "scripts/release-check.sh"
  "scripts/validate-structure.sh"
  "scripts/validate-structure.mjs"
  "scripts/quality-gate.sh"
  ".githooks/pre-commit"
  ".githooks/pre-push"
  "prompts/implementation-planning.md"
  "prompts/security-review.md"
)

required_dirs=(
  ".github"
  ".github/workflows"
  ".github/ISSUE_TEMPLATE"
  ".vscode"
  "docs/org"
  "docs/dev/plans"
  "examples"
  "external"
  "ontology"
  "policy"
  "scripts"
  "src"
  "tests"
  ".pi"
  ".pi/prompts"
  ".githooks"
  "prompts"
)

required_executables=(
  "scripts/sync-to-live.sh"
  "scripts/install-hooks.sh"
  "scripts/docs-list.sh"
  "scripts/release-check.sh"
  "scripts/validate-structure.sh"
  "scripts/validate-structure.mjs"
  "scripts/quality-gate.sh"
  ".githooks/pre-commit"
  ".githooks/pre-push"
)

errors=0

for required_file in "${required_files[@]}"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing required file: $required_file" >&2
    ((errors+=1))
  fi
done

for required_dir in "${required_dirs[@]}"; do
  if [[ ! -d "$required_dir" ]]; then
    echo "Missing required directory: $required_dir" >&2
    ((errors+=1))
  fi
done

for executable in "${required_executables[@]}"; do
  if [[ ! -x "$executable" ]]; then
    echo "Expected executable bit on: $executable" >&2
    ((errors+=1))
  fi
done

max_lines=500
while IFS= read -r -d '' source_file; do
  normalized="${source_file#./}"
  # Skip lockfiles and hidden directories (except .github which we want to check)
  if [[ "$normalized" == "package-lock.json" ]]; then
    continue
  fi
  # Skip files in hidden directories like .obsidian, .git, etc.
  if [[ "$normalized" =~ ^\.[^/]+/ ]] && [[ ! "$normalized" =~ ^\.github/ ]]; then
    continue
  fi
  # Skip if --staged-only and file is not staged
  if ! should_check_file "$source_file"; then
    continue
  fi

  line_count=$(wc -l < "$source_file")
  if [[ "$line_count" -gt "$max_lines" ]]; then
    echo "File exceeds ${max_lines}-line limit (refactor required): ${normalized} (${line_count} lines)" >&2
    ((errors+=1))
  fi
done < <(find . -type f ! -path "./.git/*" ! -path "./node_modules/*" -print0)

plan_count=$(find "docs/dev/plans" -maxdepth 1 -type f -name "*.md" | wc -l | tr -d ' ')
if [[ "$plan_count" -lt 1 ]]; then
  echo "docs/dev/plans must contain at least one markdown plan file" >&2
  ((errors+=1))
fi

for copier_key in "_src_path:" "repo_name:" "command_name:"; do
  if ! grep -q "^${copier_key}" ".copier-answers.yml"; then
    echo "Missing copier answer key in .copier-answers.yml: ${copier_key}" >&2
    ((errors+=1))
  fi
done

placeholder_pattern='\{username\}|\{repo\}|\{discordInvite\}|\{@twitter\}'
placeholder_hits="$(grep -R -nE "$placeholder_pattern" .github || true)"
if [[ -n "$placeholder_hits" ]]; then
  echo "Unresolved placeholders found under .github:" >&2
  echo "$placeholder_hits" >&2
  ((errors+=1))
fi

if ! grep -q '^\*\.tgz$' ".gitignore"; then
  echo ".gitignore must ignore npm tarball outputs (*.tgz)" >&2
  ((errors+=1))
fi

if ! grep -q "npm run release:check:quick" ".github/workflows/release-check.yml"; then
  echo "release-check workflow must run npm run release:check:quick" >&2
  ((errors+=1))
fi

if ! grep -q "npm run release:check:quick" ".github/workflows/publish.yml"; then
  echo "publish workflow must run npm run release:check:quick before npm publish" >&2
  ((errors+=1))
fi

if ! grep -q "npm run quality:ci" ".github/workflows/ci.yml"; then
  echo "ci workflow must run npm run quality:ci" >&2
  ((errors+=1))
fi

release_please_ref="16a9c90856f42705d54a6fda1823352bdc62cf38"
if ! grep -q "googleapis/release-please-action@${release_please_ref}" ".github/workflows/release-please.yml"; then
  echo "release-please workflow must pin googleapis/release-please-action to ${release_please_ref} (v4.4.0)" >&2
  ((errors+=1))
fi

if grep -q "command:" ".github/workflows/release-please.yml"; then
  echo "release-please workflow must not use deprecated 'command' input" >&2
  ((errors+=1))
fi

if grep -q "cache: npm" ".github/workflows/publish.yml"; then
  echo "publish workflow must not require setup-node npm cache when lockfile may be absent" >&2
  ((errors+=1))
fi

if ! grep -q "npm install --global npm@\^11.5.1" ".github/workflows/publish.yml"; then
  echo "publish workflow must upgrade npm to >=11.5.1 for trusted publishing compatibility" >&2
  ((errors+=1))
fi

if ! grep -q "scripts/quality-gate.sh\" pre-commit" ".githooks/pre-commit"; then
  echo ".githooks/pre-commit must call scripts/quality-gate.sh pre-commit" >&2
  ((errors+=1))
fi

if ! grep -q "scripts/quality-gate.sh\" pre-push" ".githooks/pre-push"; then
  echo ".githooks/pre-push must call scripts/quality-gate.sh pre-push" >&2
  ((errors+=1))
fi

vouch_check_ref="$(grep -Eo 'mitchellh/vouch/action/check-pr@[0-9a-f]{40}' .github/workflows/vouch-check-pr.yml | head -n1 | sed 's/.*@//')"
vouch_manage_ref="$(grep -Eo 'mitchellh/vouch/action/manage-by-issue@[0-9a-f]{40}' .github/workflows/vouch-manage.yml | head -n1 | sed 's/.*@//')"

if [[ -z "$vouch_check_ref" ]]; then
  echo "vouch-check-pr workflow must pin mitchellh/vouch/action/check-pr to a 40-char SHA" >&2
  ((errors+=1))
fi

if [[ -z "$vouch_manage_ref" ]]; then
  echo "vouch-manage workflow must pin mitchellh/vouch/action/manage-by-issue to a 40-char SHA" >&2
  ((errors+=1))
fi

if [[ -n "$vouch_check_ref" && -n "$vouch_manage_ref" && "$vouch_check_ref" != "$vouch_manage_ref" ]]; then
  echo "vouch workflow SHAs must match between check-pr and manage-by-issue" >&2
  ((errors+=1))
fi

if grep -n "@main" .github/workflows/vouch-*.yml >/dev/null 2>&1; then
  echo "vouch workflows must not use @main refs" >&2
  ((errors+=1))
fi

if ! grep -q "pull_request_target" ".github/workflows/vouch-check-pr.yml"; then
  echo "vouch-check-pr workflow must trigger on pull_request_target" >&2
  ((errors+=1))
fi

if ! grep -q "require-vouch" ".github/workflows/vouch-check-pr.yml"; then
  echo "vouch-check-pr workflow must set require-vouch" >&2
  ((errors+=1))
fi

if ! grep -q "auto-close" ".github/workflows/vouch-check-pr.yml"; then
  echo "vouch-check-pr workflow must set auto-close" >&2
  ((errors+=1))
fi

if ! grep -q "issue_comment" ".github/workflows/vouch-manage.yml"; then
  echo "vouch-manage workflow must trigger on issue_comment" >&2
  ((errors+=1))
fi

if ! grep -q "concurrency:" ".github/workflows/vouch-manage.yml" || ! grep -q "group: vouch-manage" ".github/workflows/vouch-manage.yml"; then
  echo "vouch-manage workflow must define serialized concurrency" >&2
  ((errors+=1))
fi

if ! grep -q "vouched-file: .github/VOUCHED.td" ".github/workflows/vouch-manage.yml"; then
  echo "vouch-manage workflow must target .github/VOUCHED.td" >&2
  ((errors+=1))
fi

if grep -q "@your-github-handle" ".github/CODEOWNERS"; then
  echo ".github/CODEOWNERS must not keep @your-github-handle placeholder" >&2
  ((errors+=1))
fi

if ! grep -Eq "^github:[A-Za-z0-9][A-Za-z0-9-]*" ".github/VOUCHED.td"; then
  echo ".github/VOUCHED.td must include at least one github maintainer entry" >&2
  ((errors+=1))
fi

# Run Node.js validation (package.json, release-please, stack-lane, biome-ignore)
if command -v node >/dev/null 2>&1; then
  if ! node "$ROOT_DIR/scripts/validate-structure.mjs"; then
    ((errors+=1))
  fi
fi

# Markdown frontmatter validation
while IFS= read -r -d '' markdown_file; do
  normalized="${markdown_file#./}"
  # Skip files in hidden directories like .obsidian, etc. (except .github and .pi)
  if [[ "$normalized" =~ ^\.[^/]+/ ]] && [[ ! "$normalized" =~ ^(\.github|\.pi)/ ]]; then
    continue
  fi
  # Skip if --staged-only and file is not staged
  if ! should_check_file "$markdown_file"; then
    continue
  fi

  if [[ "$(head -n 1 "$markdown_file")" != "---" ]]; then
    echo "Missing YAML frontmatter start in: $markdown_file" >&2
    ((errors+=1))
    continue
  fi

  if ! grep -q "^system4d:" "$markdown_file"; then
    echo "Missing system4d section in: $markdown_file" >&2
    ((errors+=1))
    continue
  fi

  for key in container compass engine fog; do
    if ! grep -q "^  $key:" "$markdown_file"; then
      echo "Missing system4d.$key in: $markdown_file" >&2
      ((errors+=1))
    fi
  done

  if [[ "$markdown_file" == "./prompts/"* || "$markdown_file" == "./.pi/prompts/"* ]]; then
    if ! grep -q "^description:" "$markdown_file"; then
      echo "Prompt template missing frontmatter description: $markdown_file" >&2
      ((errors+=1))
    fi
  fi
done < <(find . -type f -name "*.md" ! -path "./.git/*" ! -path "./node_modules/*" -print0)

if [[ "$errors" -gt 0 ]]; then
  echo "Structure validation failed with $errors issue(s)." >&2
  exit 1
fi

echo "Structure validation passed."
