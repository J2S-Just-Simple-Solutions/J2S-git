## Project setup

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


Configure you gh envrionment

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

### Command line options
`jgit -h` to get help

`jgit feature start <ticket-ID>` will create a feature branch on your local and on J2S remote and will create an associated PR on github with NFR flag.

`jgit hotfix start <ticket-ID>` will create a hotfix branch on your local and on J2S remote and will create an associated PR on github with NFR flag.

`jgit release start` will create, or checkout the existing, release branch on your local and create it on J2S remote if needed.


