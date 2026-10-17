#!/usr/bin/env bash
# wasc passwords: keep this fork's Actions limited to the wasc-* workflows (see wasc/README.md).
#
# - Disables every active workflow whose file is not .github/workflows/wasc-*.yml. Upstream
#   workflows arrive with each sync and are registered (enabled) as soon as a branch containing
#   them is pushed.
# - Re-enables the wasc workflow files given as arguments (keepalive). GitHub disables scheduled
#   workflows in public repos after 60 days without repository activity; the enable call resets
#   that timer and also revives a workflow that was already auto-disabled.
#
# Usage: workflow-guard.sh [wasc-workflow.yml ...]   (needs GH_TOKEN with actions: write)
set -euo pipefail
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"

gh api --paginate "repos/$repo/actions/workflows" \
  --jq '.workflows[] | [.id, .state, .path] | @tsv' |
  while IFS=$'\t' read -r id state path; do
    case "$path" in
      .github/workflows/wasc-*) continue ;;
    esac
    if [ "$state" = active ]; then
      echo "Disabling $path ($id)"
      gh api -X PUT "repos/$repo/actions/workflows/$id/disable" ||
        echo "::warning::Could not disable $path ($id)"
    fi
  done

for file in "$@"; do
  echo "Keepalive: enabling $file"
  gh api -X PUT "repos/$repo/actions/workflows/$file/enable"
done
