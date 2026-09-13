# git-remote-status

A small Bash utility that scans local Git repositories, refreshes their remote references, and reports whether the checked-out branch is ahead of or behind its configured upstream. It can also show the commits available upstream without applying them locally.

The script only runs `git fetch`; it does not run `git pull`, merge, rebase, or modify the working tree.

## Example output

The following is representative output using fictional repository names and values; it was not captured from a user's machine:

```text
  1. [GITHUB]       ↑0   ↓3    v2.4.1               ./example-service
  2. [GITHUB]       ↑1   ↓0    v1.8.0               ./example-theme
  3. [LOCAL]        ↑-   ↓-    -                    ./scratch-notes
```

`↑` is the number of local commits not present in the upstream branch. `↓` is the number of upstream commits not present locally. A release is shown when the repository's latest GitHub release is available; `NEW` means that release commit is not an ancestor of the local `HEAD`.

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
