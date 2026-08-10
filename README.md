## Project setup

### Installation

First clone the repo

```sh
cd /path-to-your-j2sgit-project/
git clone git@github.com:J2S-Just-Simple-Solutions/J2S-git.git
```

### Add a jgit shortcut in your terminal

Edit your zprofile

```sh
nano ~/.zprofile
```

Add the line

```sh
alias jgit='/path-to-your-j2sgit-project/J2S-Git/jgit.sh'
```

Restart your terminal.

### prerequisites

You should have 1 remote named `origin` that head to a J2S github repository on all your local projects.
You must have your reference branch existing on local (`develop` or `master`)

You must have git install on your local.

You must have github client install on your local https://cli.github.com/

Configure you gh envrionment

```sh
gh repo set-default
```

By default jgit use the following parameters

```sh
j2s_remote="origin"
branch_prod="main"
branch_preprod="develop"
```

You can ovveride those variable for each git projects by creating a specific configuration file.

In your git project, create a file `.jgit/conf_local.sh` (create the `.jgit` folder if needed)

With the content (update with your needs)

```sh
#!/bin/bash

j2s_remote="origin"
branch_prod="master2"
branch_preprod="develop2"
```

PS : you can add `.jgit/*` in the .gitignore of your git project.

## Usage

jgit will be used in command line directly from your project folder.

Example

```sh
toto@MacBook-Pro ~ % cd Projets/My-project 
toto@MacBook-Pro % jgit feature start TESTDEV-1111
```

Please read the documentation with `jgit -h` or `jgit help`
