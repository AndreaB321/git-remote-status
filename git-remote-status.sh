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

scan_repositories() {
    repos=()
    types=()
    aheads=()
    behinds=()
    releases=()

    while IFS= read -r gitdir; do
    repo="${gitdir%/.git}"

    # Determine repository type
    if ! git -C "$repo" remote | grep -q .; then
        type="LOCAL"
    elif git -C "$repo" config --get-regexp '^remote\..*\.url$' 2>/dev/null | grep -qi 'github.com'; then
        type="GITHUB"
    else
        type="OTHER-REMOTE"
    fi

    ahead="-"
    behind="-"
    release="-"
    release_commit=""

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

        repos+=("$repo")
        types+=("$type")
        aheads+=("$ahead")
        behinds+=("$behind")
        releases+=("$release")
    done < <(find "$BASE_DIR" -type d -name .git -prune -print)
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

    auto_fetch "$repo"
    if upstream=$(git -C "$repo" rev-parse \
        --abbrev-ref \
        --symbolic-full-name '@{upstream}' \
        2>/dev/null) && [[ -n "$upstream" ]]; then
        read -r behind ahead < <(
            git -C "$repo" rev-list --left-right --count "$upstream...HEAD"
        )
    fi

    aheads[idx]=$ahead
    behinds[idx]=$behind
}

show_repository_commits() {
    local idx=$1
    local repo=${repos[idx]}
    local behind=${behinds[idx]}
    local upstream

    if [[ "$behind" != "-" && "$behind" -gt 0 ]]; then
        upstream=$(git -C "$repo" rev-parse \
            --abbrev-ref \
            --symbolic-full-name '@{upstream}' \
            2>/dev/null) || upstream=""
        if [[ -n "$upstream" ]]; then
            echo "Showing $behind commits from $upstream for ${repo}:"
            git -C "$repo" log -"$behind" --oneline "$upstream" 2>/dev/null || \
                echo "Could not read the remote commit log"
        else
            echo "Could not determine the configured upstream"
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
