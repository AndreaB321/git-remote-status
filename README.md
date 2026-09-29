# git-remote-status

A small Bash utility that scans local Git repositories, refreshes their remote references, and reports whether the checked-out branch is ahead of or behind its configured upstream. It can show the commits available upstream and, on explicit request, pull a selected GitHub repository.

The initial scan only runs `git fetch`; it does not modify a working tree. A `git pull` is run only after selecting a GitHub repository and explicitly choosing `p` from its detail menu.

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

After the list, enter a repository number to inspect the remote commits that are not yet present locally. Enter `r` to rescan all repositories and refresh their remote references, or `x` to exit. The detail menu displays commits with `git log`; use `b` to return to the cached list without another scan. GitHub repositories also offer `p` to run `git pull` for the selected repository. For example:

```text
Enter repository number, 'r' to refresh, or 'x' to exit: 4

Showing 4 commits from origin/main for ./projects/example-library:
a1b2c3d4 fix: handle an example input safely
b2c3d4e5 docs: clarify the fictional setup
c3d4e5f6 test: cover the remote-status example
d4e5f6a7 chore: refresh sample metadata

Enter 'p' to pull, 'b' to go back, or 'x' to exit: b
```

The commit hashes and messages above are fictional examples. In an actual run, they are read from the selected repository's configured upstream branch. The `p` option is displayed only for repositories classified as `GITHUB`; other repository types offer only `b` and `x` in the detail menu.

## Performance

Repositories are fetched and inspected concurrently (up to 8 at a time by
default) rather than one at a time, so scans with many remote repositories
complete faster. Set `GIT_REMOTE_STATUS_JOBS` to change the maximum number
of concurrent jobs, for example:

```bash
GIT_REMOTE_STATUS_JOBS=16 ./git-remote-status.sh "$HOME/projects"
```

## Requirements

- Bash 4+
- Git
- [GitHub CLI](https://cli.github.com/) (`gh`) for GitHub release information; it is optional
- Authentication with `gh auth login` if GitHub release information is needed

## Usage

```bash
./git-remote-status.sh [directory]
```

The directory defaults to the current directory. The script recursively finds Git repositories below it, fetches remote references, and prints a numbered list. Select a number to display the upstream commits that are not yet in the local branch, enter `r` to refresh the complete list, or enter `x` to exit. From a repository detail menu, enter `b` to return to the existing list; GitHub repositories additionally offer `p` to pull the selected repository.

Example:

```bash
chmod +x git-remote-status.sh
git-remote-status.sh "$HOME/projects"
```

The initial scan does not download changes into working trees. Choosing `p` explicitly runs `git pull` for the selected GitHub repository, using that repository's configured pull strategy. Inspect the pending commits before choosing it.

## Limitations

- Commit counts use each repository's configured upstream branch. Repositories without an upstream show `-`.
- Release information is only queried for GitHub remotes and requires `gh`.
- Repositories without a published GitHub release show `-` in the release column.
- Remote fetch errors are intentionally quiet; inspect the repository directly if its status looks incomplete.

## Licence

MIT. See [LICENSE](LICENSE).
