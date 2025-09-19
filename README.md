## Project setup

### Installation
First clone the repo
```
cd /path-to-your-j2sgit-project/
git clone 
```

### Add a jgit shortcut in your terminal
Edit your zprofile
```
nano ~/.zprofile
```

Add the line
```
alias jgit='/path-to-your-j2sgit-project/J2S-Git/jgit.sh'
```

Restart your terminal.

### prerequisites
You should have 1 remote named `origin` that head to a J2S github repository on all your local projects.
You must have your reference branch existing on local (`develop2` or `master`)

You must have git install on your local.

You must have github client install on your local https://cli.github.com/

Configure you gh envrionment

```
gh repo set-default
```

By default jgit use the following parameters
```
2s_remote="origin"
branch_prod="main"
branch_preprod="develop"
```

You can ovveride those variable for each git projects by creating a specific configuration file.

In your git project, create a file `.jgit/conf_local.sh` (create the `.jgit` folder if needed)

With the content (update with your needs)
```
#!/bin/bash

j2s_remote="origin"
branch_prod="master2"
branch_preprod="develop2"
```

PS : you can add `.jgit/*` in the .gitignore of your git project.

## Usage
jgit will be used in command line directly from your project folder.

Example
```
toto@MacBook-Pro ~ % cd Projets/My-project 
toto@MacBook-Pro % jgit feature start TESTDEV-1111
```

Please read the documentation with `jgit -h` or `jgit help`

### Feature & Hotfix commands

- `jgit feature start <ticket> [--based-on <branch>]` — creates (or resumes) the working branch `feature/<ticket>` and its PR branch `__PR__feature/<ticket>`. When the branches do not exist yet, the reference branch is checked out (`--based-on` or default), a commit is added to seed the PR, everything is pushed, and a GitHub PR is opened. Replace `feature` with `hotfix` for an identical workflow on hotfix branches.
- `jgit feature restart <ticket>` — resets the working branch from the existing PR branch after verifying that both hold the same code. The script deletes the old `feature/<ticket>` locally/remotely, recreates it with a restart marker commit, pushes it, and reopens the PR. Also available as `jgit hotfix restart`.
- `jgit feature rebase <ticket> [--based-on <branch>]` — orchestrates a clean rebase: fetches the remote branches, ensures no merge commits slip in, displays the commits to replay, cherry-picks them onto temporary `jgit_rebase_*` branches, renames them back, and force-pushes. Works the same for `jgit hotfix rebase`.

### Release commands

- `jgit release start` — inspects the latest `x.y.z` tag, increments the middle number, and creates or resumes the corresponding `release/x.y.z` branch with an init commit.
- `jgit release merge <branch>` — ensures the release branch is ready (creating it if needed) then merges the provided branch (usually `__PR__feature/<ticket>`) into the release, preferring a local branch if present otherwise the remote one.
- `jgit release finish` — validates the current release branch, merges it into `main` (`branch_prod`), tags the release, deletes the release branch locally/remotely, pushes, and creates a GitHub release.

### Demo commands

- `jgit demo start [demo_name] [--based-on <branch>]` — creates or resumes a `demo_<base>` branch. Existing branches are checked out and fast-forwarded; otherwise the branch is created from the chosen reference branch after confirmation and pushed with a marker commit.
- `jgit demo merge feature <feature_name>` — run from a demo branch. Checks that `feature/<feature_name>` exists on the remote, adds a marker commit if missing, applies the feature commits onto the demo branch, and pushes with `--force-with-lease` to keep the history linear.
- `jgit demo list` — scans the history since the demo init commit, finds all `[jgit] DEMO feature …` markers, and prints both the merged features and the `jgit release merge` commands to replay them during a release.
- `jgit demo remove` — from a demo branch, asks for confirmation, switches back to the reference branch, deletes the demo branch on the remote then locally, and leaves you on the safe branch.

### Utility

- `jgit clean` — removes local helper branches created by jgit (`jgit_rebase_*`, `__PR__*`).
- `jgit help` ou `jgit -h` — displays the in-terminal help with every command and option.
