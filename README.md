## Project setup
You must have git install on your local.

### Installation
First clone the repo
```
cd /path-to-yourj2sgit-project/
git clone 
```

### Add a jgit shortcut in your terminal
Edit your zprofile
```
nano ~/.zprofile
```

Add the line
```
alias jgit='/path-to-yourj2sgit-project/J2S-Git/jgit.sh'
```

Restart your terminal.

### prerequisites
You should have 1 remote named `origin` that head to a J2S github repository on all your local projects.
You must have git install on your local.
You must have github client install on your local https://cli.github.com/

Configure you gh environment
```
gh repo set-default
```

## Usage
jgit will be used in command line directly from your project folder.

Example
```
toto@MacBook-Pro ~ % cd Projets/My-project 
toto@MacBook-Pro % jgit feature TESTDEV-1111
```

### prerequisites
You must have forked the project on your own account.

You should have 2 remotes on all your local projects
* origin that point to J2S github remote
* <your-own-remote> that point to the fork of teh project on your remote/


NOTICE : 
<your-own-remote> should be name the same on all your projects.
J2S remote must always be name the same on all projects.

### Configure remote
Configure your remote on your local using SSH (https authenitification is note supported since 2021)
```
git remote add origin git@github.com:J2S-Just-Simple-Solutions/My-Project.git
git remote add your-own-remote git@github.com:your-own-remote/My-Project.git
```

### Command line options
`jgit -h` to get help

`jgit feature start <ticket-ID>` will create a feature branch on your local and on J2S remote and will create an associated PR on github with NFR flag.

`jgit hotfix start <ticket-ID>` will create a hotfix branch on your local and on J2S remote and will create an associated PR on github with NFR flag.

`jgit release start` will create, or checkout the existing, release branch on your local and create it on J2S remote if needed.

