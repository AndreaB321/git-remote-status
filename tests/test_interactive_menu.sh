#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/git-remote-status.sh"
temp_root=$(mktemp -d "${TMPDIR:-/tmp}/git-remote-status-test.XXXXXX")
trap 'rm -rf "$temp_root"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

make_repo() {
    local path=$1
    git init --quiet -b main "$path"
    git -C "$path" config user.name "Test User"
    git -C "$path" config user.email "test@example.invalid"
    printf 'fixture\n' > "$path/README.md"
    git -C "$path" add README.md
    git -C "$path" commit --quiet -m "Initial fixture"
}

# Refresh must rerun the scan rather than being rejected as invalid input.
local_root="$temp_root/local-root"
make_repo "$local_root/repository"
refresh_output=$(printf 'r\nx\n' | "$script" "$local_root" 2>&1)
refresh_rows=$(printf '%s\n' "$refresh_output" | grep -c '\[LOCAL\]')
[[ "$refresh_rows" -eq 2 ]] || fail "refresh should print the repository list twice"
if printf '%s\n' "$refresh_output" | grep -q 'Invalid selection'; then
    fail "refresh should not be treated as an invalid selection"
fi

# Back must return to the cached repository list, without another scan.
back_output=$(printf '1\nb\nx\n' | "$script" "$local_root" 2>&1)
back_rows=$(printf '%s\n' "$back_output" | grep -c '\[LOCAL\]')
[[ "$back_rows" -eq 2 ]] || fail "back should reprint the cached repository list"
if printf '%s\n' "$back_output" | grep -q 'Invalid selection'; then
    fail "back should not be treated as an invalid selection"
fi
if printf '%s\n' "$back_output" | grep -Fq "'p' to pull"; then
    fail "non-GitHub repository detail menu should not expose pull"
fi

# Pull must update only the selected GitHub repository and then refresh its status.
pull_remote="$temp_root/pull-remote.git"
pull_root="$temp_root/pull-root"
git init --bare --quiet "$pull_remote"
make_repo "$pull_root/repository"
git -C "$pull_root/repository" remote add origin https://github.com/example/pull.git
git -C "$pull_root/repository" config url."$pull_remote".insteadOf https://github.com/example/pull.git
git -C "$pull_root/repository" push --quiet --set-upstream origin main
git -C "$pull_remote" symbolic-ref HEAD refs/heads/main

# Refresh fetches again; back only reprints the cached list.
test_bin="$temp_root/bin"
mkdir "$test_bin"
ln -s "$repo_root/tests/fixtures/git-observer.sh" "$test_bin/git"
refresh_log="$temp_root/refresh-git.log"
PATH="$test_bin:$PATH" GIT_CALL_LOG="$refresh_log" \
    bash -c "printf 'r\\nx\\n' | '$script' '$pull_root'" >/dev/null 2>&1
[[ "$(grep -c 'fetch --prune --quiet' "$refresh_log")" -eq 2 ]] || \
    fail "refresh should fetch the remote repository twice"
back_log="$temp_root/back-git.log"
PATH="$test_bin:$PATH" GIT_CALL_LOG="$back_log" \
    bash -c "printf '1\\nb\\nx\\n' | '$script' '$pull_root'" >/dev/null 2>&1
[[ "$(grep -c 'fetch --prune --quiet' "$back_log")" -eq 1 ]] || \
    fail "back should not fetch the remote repository again"

publisher="$temp_root/publisher"
git clone --quiet "$pull_remote" "$publisher"
git -C "$publisher" config user.name "Test User"
git -C "$publisher" config user.email "test@example.invalid"
printf 'upstream change\n' >> "$publisher/README.md"
git -C "$publisher" commit --quiet -am "Upstream change"
git -C "$publisher" push --quiet
pull_output=$(printf '1\np\nb\nx\n' | "$script" "$pull_root" 2>&1)
printf '%s\n' "$pull_output" | grep -Fq '[GITHUB]' || \
    fail "pull fixture should be classified as a GitHub repository"
[[ "$(git -C "$pull_root/repository" rev-parse HEAD)" == \
   "$(git -C "$pull_root/repository" rev-parse refs/remotes/origin/main)" ]] || \
    fail "pull should update the selected repository to its upstream"
[[ -z "$(git -C "$pull_root/repository" status --porcelain)" ]] || \
    fail "pull fixture should leave no working-tree changes"

# A failed pull still refreshes the selected repository's cached status.
printf 'remote conflict\n' > "$publisher/conflict.txt"
git -C "$publisher" add conflict.txt
git -C "$publisher" commit --quiet -m "Add conflict fixture"
git -C "$publisher" push --quiet
printf 'local untracked conflict\n' > "$pull_root/repository/conflict.txt"
failed_pull_log="$temp_root/failed-pull-git.log"
failed_pull_output=$(PATH="$test_bin:$PATH" GIT_CALL_LOG="$failed_pull_log" \
    bash -c "printf '1\\np\\nb\\nx\\n' | '$script' '$pull_root'" 2>&1)
printf '%s\n' "$failed_pull_output" | grep -Fq "Pull failed for" || \
    fail "failed pull should be reported"
printf '%s\n' "$failed_pull_output" | grep -Fq '↓1' || \
    fail "failed pull should refresh the selected repository status"
[[ "$(grep -c 'fetch --prune --quiet' "$failed_pull_log")" -eq 2 ]] || \
    fail "failed pull should refresh remote references after the pull attempt"

printf 'PASS: interactive refresh, back, and GitHub pull-menu behaviour\n'
