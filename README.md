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

### Command line options
`jgit -h` to get help

`jgit feature|hotfix start <ticket-ID>` will create a feature or a hotfix branch on your local and on J2S remote and will create an associated PR on github with NFR flag. If the feature already exists, it will just checkout on it and update it.

`jgit feature|hotfix rebase <ticket-ID>` will rebase the PR branch and the feature or hotfix branch based on main branch.
    -> In case of conflicts, teh command will pause, fix all conflicts and commit them before resuming the execution.
    -> If you leave the command execution in the middle, you will need to re-run (and fix conflicts) from scratch. 

`jgit release start` will create, or checkout the existing, release branch on your local and create it on J2S remote if needed.

`jgit release merge <branch_name>` will merge the branch in the current release.

`jgit release finish` will close the current release : merge the current release branch, create the tag and the release in github.

`jgit clean` Will clean all local branches to remove working branches as rebase and _ _PR__.
