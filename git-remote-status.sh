#!/usr/bin/env bash

BASE_DIR="${1:-.}"

# Maximum number of repositories fetched/inspected concurrently during a scan.
# Override with the GIT_REMOTE_STATUS_JOBS environment variable if needed.
MAX_PARALLEL_JOBS="${GIT_REMOTE_STATUS_JOBS:-8}"

declare -a repos
declare -a types
declare -a aheads
declare -a behinds
declare -a releases
declare -a release_commits

auto_fetch() {
    local repo=$1
    git -C "$repo" fetch --prune --quiet 2>/dev/null
}

# Computes the status of a single repository and writes it as a
# tab-separated line to $outfile. Runs in a background subshell, so results
# are communicated back to the parent via the file rather than variables.
process_repository() {
    local gitdir=$1
    local outfile=$2
    local repo="${gitdir%/.git}"
    local type ahead="-" behind="-" release="-" release_commit=""
    local upstream latest_release

    # Determine repository type
    if ! git -C "$repo" remote | grep -q .; then
        type="LOCAL"
    elif git -C "$repo" config --get-regexp '^remote\..*\.url$' 2>/dev/null | grep -qi 'github.com'; then
        type="GITHUB"
    else
        type="OTHER-REMOTE"
    fi

    if [[ "$type" != "LOCAL" ]]; then
        auto_fetch "$repo"
    fi

    # Check the latest GitHub release
    if [[ "$type" == "GITHUB" ]] && command -v gh >/dev/null 2>&1; then
        latest_release=$(
            gh release view \
                --repo "$(git -C "$repo" config --get remote.origin.url)" \
                --json tagName \
                --jq '.tagName' \
                2>/dev/null
        )

        if [[ -n "$latest_release" ]]; then
            # A repository may contain commits newer than the release tag while
            # still including the complete release. Check commit ancestry rather
            # than requiring HEAD to match the tag exactly.
            if release_commit=$(
                git -C "$repo" rev-parse \
                    "$latest_release^{commit}" \
                    2>/dev/null
            ) && [[ -n "$release_commit" ]] &&
               git -C "$repo" merge-base --is-ancestor \
                   "$release_commit" HEAD; then
                release="$latest_release"
            else
                release="$latest_release NEW"
            fi
        fi
    fi

    if [[ "$type" != "LOCAL" ]]; then
        # Get the current upstream branch
        if upstream=$(git -C "$repo" rev-parse \
            --abbrev-ref \
            --symbolic-full-name '@{upstream}' \
            2>/dev/null) && [[ -n "$upstream" ]]; then
            read -r behind ahead < <(
                git -C "$repo" rev-list \
                    --left-right \
                    --count \
                    "$upstream...HEAD"
            )
        elif [[ -n "$release_commit" ]]; then
            # No tracked branch (e.g. HEAD detached on a tag): fall back to
            # comparing against the latest release commit so a pinned
            # checkout still reports how far it trails the newest release.
            # A trailing "~" marks these counts as relative to the release
            # tag rather than a tracked upstream branch.
            read -r behind ahead < <(
                git -C "$repo" rev-list \
                    --left-right \
                    --count \
                    "$release_commit...HEAD"
            )
            behind="${behind}~"
            ahead="${ahead}~"
        fi
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$repo" "$type" "$ahead" "$behind" "$release" "$release_commit" \
        > "$outfile"
}

scan_repositories() {
    repos=()
    types=()
    aheads=()
    behinds=()
    releases=()
    release_commits=()

    local gitdirs=()
    while IFS= read -r gitdir; do
        gitdirs+=("$gitdir")
    done < <(find "$BASE_DIR" -type d -name .git -prune -print)

    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/git-remote-status.XXXXXX")

    # Fetch and inspect repositories concurrently (bounded by
    # MAX_PARALLEL_JOBS) instead of one at a time; each background job
    # writes its result to its own file so ordering can be restored
    # afterwards regardless of completion order.
    local i=0
    for gitdir in "${gitdirs[@]}"; do
        while (( $(jobs -rp | wc -l) >= MAX_PARALLEL_JOBS )); do
            wait -n
        done
        process_repository "$gitdir" "$tmpdir/$i" &
        ((i++))
    done
    wait

    local j repo type ahead behind release release_commit
    for ((j = 0; j < i; j++)); do
        IFS=$'\t' read -r repo type ahead behind release release_commit \
            < "$tmpdir/$j"
        repos+=("$repo")
        types+=("$type")
        aheads+=("$ahead")
        behinds+=("$behind")
        releases+=("$release")
        release_commits+=("$release_commit")
    done

    rm -rf "$tmpdir"
}

print_repositories() {
    for i in "${!repos[@]}"; do
        idx=$((i + 1))
        printf "%3d. %-14s %-6s %-7s %-20s %s\n" \
            "$idx" \
            "[${types[i]}]" \
            "↑${aheads[i]}" \
            "↓${behinds[i]}" \
            "${releases[i]}" \
            "${repos[i]}"
    done

    echo
}

refresh_repository_status() {
    local idx=$1
    local repo=${repos[idx]}
    local upstream
    local ahead="-"
    local behind="-"
    local release_commit=${release_commits[idx]}

    auto_fetch "$repo"
    if upstream=$(git -C "$repo" rev-parse \
        --abbrev-ref \
        --symbolic-full-name '@{upstream}' \
        2>/dev/null) && [[ -n "$upstream" ]]; then
        read -r behind ahead < <(
            git -C "$repo" rev-list --left-right --count "$upstream...HEAD"
        )
    elif [[ -n "$release_commit" ]]; then
        read -r behind ahead < <(
            git -C "$repo" rev-list --left-right --count "$release_commit...HEAD"
        )
        behind="${behind}~"
        ahead="${ahead}~"
    fi

    aheads[idx]=$ahead
    behinds[idx]=$behind
}

show_repository_commits() {
    local idx=$1
    local repo=${repos[idx]}
    local behind=${behinds[idx]}
    local behind_count=${behind%\~}
    local upstream

    if [[ "$behind" != "-" && "$behind_count" -gt 0 ]]; then
        if upstream=$(git -C "$repo" rev-parse \
            --abbrev-ref \
            --symbolic-full-name '@{upstream}' \
            2>/dev/null) && [[ -n "$upstream" ]]; then
            echo "Showing $behind_count commits from $upstream for ${repo}:"
            git -C "$repo" log -"$behind_count" --oneline "$upstream" 2>/dev/null || \
                echo "Could not read the remote commit log"
        else
            local release_commit=${release_commits[idx]}
            if [[ -n "$release_commit" ]]; then
                echo "Showing $behind_count commits from the latest release for ${repo}:"
                git -C "$repo" log -"$behind_count" --oneline "$release_commit" 2>/dev/null || \
                    echo "Could not read the release commit log"
            else
                echo "Could not determine the configured upstream"
            fi
        fi
    else
        echo "No commits behind the configured upstream for this repository"
    fi
    echo
}

repository_menu() {
    local idx=$1
    local repo=${repos[idx]}
    local type=${types[idx]}
    local choice

    while true; do
        show_repository_commits "$idx"
        if [[ "$type" == "GITHUB" ]]; then
            read -rp "Enter 'p' to pull, 'b' to go back, or 'x' to exit: " choice
        else
            read -rp "Enter 'b' to go back or 'x' to exit: " choice
        fi

        case "$choice" in
            x|X) exit 0 ;;
            b|B) return 0 ;;
            p|P)
                if [[ "$type" != "GITHUB" ]]; then
                    echo "Invalid selection. Enter 'b' to go back or 'x' to exit."
                    echo
                    continue
                fi
                if ! git -C "$repo" pull; then
                    echo "Pull failed for ${repo}."
                fi
                refresh_repository_status "$idx"
                echo
                ;;
            *)
                if [[ "$type" == "GITHUB" ]]; then
                    echo "Invalid selection. Enter 'p' to pull, 'b' to go back, or 'x' to exit."
                else
                    echo "Invalid selection. Enter 'b' to go back or 'x' to exit."
                fi
                echo
                ;;
        esac
    done
}

while true; do
    scan_repositories
    print_repositories

    while true; do
        read -rp "Enter repository number, 'r' to refresh, or 'x' to exit: " choice
        case "$choice" in
            x|X) exit 0 ;;
            r|R) break ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#repos[@]} )); then
                    repository_menu "$((choice - 1))"
                    print_repositories
                else
                    echo "Invalid selection. Enter a number between 1 and ${#repos[@]}, 'r' to refresh, or 'x' to exit."
                fi
                ;;
        esac
    done
done
