#!/usr/bin/env bash

BASE_DIR="${1:-.}"

declare -a repos
declare -a types
declare -a aheads
declare -a behinds
declare -a releases

auto_fetch() {
    local repo=$1
    git -C "$repo" fetch --prune --quiet 2>/dev/null
}

while IFS= read -r gitdir; do
    repo="${gitdir%/.git}"

    # Determine repository type
    if ! git -C "$repo" remote | grep -q .; then
        type="LOCAL"
    elif git -C "$repo" remote -v | grep -qi 'github.com'; then
        type="GITHUB"
    else
        type="OTHER-REMOTE"
    fi

    ahead="-"
    behind="-"
    release="-"

    if [[ "$type" != "LOCAL" ]]; then
        auto_fetch "$repo"

        # Get the current upstream branch
        upstream=$(git -C "$repo" rev-parse \
            --abbrev-ref \
            --symbolic-full-name '@{upstream}' \
            2>/dev/null)

        if [[ -n "$upstream" ]]; then
            read -r behind ahead < <(
                git -C "$repo" rev-list \
                    --left-right \
                    --count \
                    "$upstream...HEAD"
            )
        fi
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
            release_commit=$(
                git -C "$repo" rev-parse \
                    "$latest_release^{commit}" \
                    2>/dev/null
            )

            if [[ -n "$release_commit" ]] &&
               git -C "$repo" merge-base --is-ancestor \
                   "$release_commit" HEAD; then
                release="$latest_release"
            else
                release="$latest_release NEW"
            fi
        fi
    fi

    repos+=("$repo")
    types+=("$type")
    aheads+=("$ahead")
    behinds+=("$behind")
    releases+=("$release")
done < <(find "$BASE_DIR" -type d -name .git -prune -print)

# Print a numbered list
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

# Interactive selection
while true; do
    read -rp "Enter repository number to see commits (or 'x' to exit): " choice
    if [[ "$choice" == "x" || "$choice" == "X" ]]; then
        exit 0
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#repos[@]} )); then
        idx=$((choice - 1))
        repo="${repos[idx]}"
        behind="${behinds[idx]}"
        upstream=$(git -C "$repo" rev-parse \
            --abbrev-ref \
            --symbolic-full-name '@{upstream}' \
            2>/dev/null)
        if [[ "$behind" != "-" && "$behind" -gt 0 ]]; then
            echo "Showing $behind commits from $upstream for ${repo}:"
            git -C "$repo" log -"$behind" --oneline "$upstream" 2>/dev/null || \
                echo "Could not read the remote commit log"
        else
            echo "No commits behind the configured upstream for this repository"
        fi
        echo
    else
        echo "Invalid selection. Enter a number between 1 and ${#repos[@]}, or 'x' to exit."
    fi
done
