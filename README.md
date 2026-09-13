# git-remote-status

A small Bash utility that scans local Git repositories, refreshes their remote references, and reports whether the checked-out branch is ahead of or behind its configured upstream. It can also show the commits available upstream without applying them locally.

The script only runs `git fetch`; it does not run `git pull`, merge, rebase, or modify the working tree.

## Example output

The following is representative output using fictional repository names and values; it was not captured from a user's machine:

```text
 1. [LOCAL]        ↑-   ↓-    -                    ./projects/scratch-notes
  2. [GITHUB]       ↑0   ↓0    v2.4.1               ./projects/example-service
  3. [GITHUB]       ↑1   ↓0    v1.8.0 NEW           ./projects/example-theme
  4. [GITHUB]       ↑0   ↓4    -                    ./projects/example-library
```

This is representative output using fictional repository names, paths, versions, and commit counts; it was not captured from a user's machine.

`↑` is the number of local commits not present in the upstream branch. `↓` is the number of upstream commits not present locally. A release is shown when the repository's latest GitHub release is available; `NEW` means that release commit is not an ancestor of the local `HEAD`.

After the list, enter a repository number to inspect the remote commits that are not yet present locally. The script displays those commits with `git log` after fetching the remote references; it does not apply them. For example:

```text
Enter repository number to see commits (or 'x' to exit): 4

Showing 4 commits from origin/main for ./projects/example-library:
a1b2c3d4 fix: handle an example input safely
b2c3d4e5 docs: clarify the fictional setup
c3d4e5f6 test: cover the remote-status example
d4e5f6a7 chore: refresh sample metadata
```

The commit hashes and messages above are fictional examples. In an actual run, they are read from the selected repository's configured upstream branch. Enter `x` to exit.

## Requirements

- Bash 4+
- Git
- [GitHub CLI](https://cli.github.com/) (`gh`) for GitHub release information; it is optional
- Authentication with `gh auth login` if GitHub release information is needed

## Usage

```bash
./git-remote-status.sh [directory]
```

The directory defaults to the current directory. The script recursively finds Git repositories below it, fetches remote references, and prints a numbered list. Select a number to display the upstream commits that are not yet in the local branch, or enter `x` to exit.

Example:

```bash
chmod +x git-remote-status.sh
git-remote-status.sh "$HOME/projects"
```

The script does not download changes into the working tree. To apply upstream changes, inspect them first and then run the appropriate Git command yourself, such as `git pull --ff-only`.

## Limitations

- Commit counts use each repository's configured upstream branch. Repositories without an upstream show `-`.
- Release information is only queried for GitHub remotes and requires `gh`.
- Repositories without a published GitHub release show `-` in the release column.
- Remote fetch errors are intentionally quiet; inspect the repository directly if its status looks incomplete.

## Licence

MIT. See [LICENSE](LICENSE).
