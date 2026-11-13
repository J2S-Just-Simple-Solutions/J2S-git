#!/bin/bash

###############################################
#      jgit ui : l'interface en terminal
###############################################
#
# L'interface (ui/, TypeScript + Ink) tourne par défaut dans le conteneur
# j2s/jgit:local, construit par docker compose à partir de ce dépôt : rien à
# installer sur le poste que Docker. JGIT_UI=native la lance avec le node du
# poste (après « npm ci && npm run build » dans ui/).
#
# Le dépôt du projet est monté au même chemin que sur l'hôte, et le conteneur
# tourne sous l'identité de l'hôte : les fichiers restent les siens. L'image est
# construite par docker compose (docker-compose.yml), qui ne refait que ce qui a
# changé.

jgit_ui() {
  local top
  top=$(git rev-parse --show-toplevel 2>/dev/null) || top="$PWD"

  if [[ "${JGIT_UI:-docker}" == "native" ]]; then
    jgit_ui_native
    return
  fi

  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    if [[ -f "$JGIT_HOME/ui/dist/src/cli.js" ]] && command -v node >/dev/null 2>&1; then
      printf "%sDocker est indisponible : l'interface est lancée avec le node du poste.%s\n" "$C_YELLOW" "$C_RESET" >&2
      jgit_ui_native
      return
    fi
    jgit_fail docker_unavailable "$JGIT_EXIT_ERROR" \
      "L'interface tourne dans Docker, qui est indisponible sur ce poste." \
      "Démarrez Docker, ou construisez-la localement : (cd $JGIT_HOME/ui && npm ci && npm run build), puis JGIT_UI=native jgit ui"
  fi

  local compose=(docker compose -f "$JGIT_HOME/docker-compose.yml")
  printf "Préparation de l'image jgit (la première fois seulement, ou après une mise à jour de jgit)…\n" >&2
  if ! PWD="$top" "${compose[@]}" build --quiet jgit >/dev/null; then
    jgit_fail docker_build_failed "$JGIT_EXIT_ERROR" \
      "L'image de l'interface n'a pas pu être construite." \
      "${compose[*]} build jgit"
  fi

  # Construite par compose, lancée par docker run : « compose run » ne sait
  # pas ajouter un groupe (--group-add), nécessaire à l'agent SSH du Mac.
  local run=(run --rm -it --user "$(id -u):$(id -g)" -v "$top:$top" -w "$PWD"
             -e "TERM=${TERM:-xterm-256color}")
  # Les commits créés dans le conteneur portent l'heure locale du poste.
  local zone="${TZ:-}"
  [[ -n "$zone" ]] || zone=$(readlink /etc/localtime 2>/dev/null | sed -n 's#.*/zoneinfo/##p')
  [[ -n "$zone" ]] && run+=(-e "TZ=$zone")
  [[ -f "$HOME/.gitconfig" ]] && run+=(-v "$HOME/.gitconfig:/home/jgit/.gitconfig:ro")
  # Tout ~/.ssh, pas seulement known_hosts : un remote peut passer par un alias
  # de ~/.ssh/config (« git:projet » → Host git, autre serveur, autre clé, autres
  # algorithmes), et sa clé n'est pas forcément chargée dans l'agent.
  if [[ -d "$HOME/.ssh" ]]; then
    run+=(-v "$HOME/.ssh:/home/jgit/.ssh:ro")
    # UseKeychain n'existe que dans le ssh de macOS : le ssh Linux du conteneur
    # refuserait la config entière. Sauf si le poste a choisi sa commande ssh.
    if [[ -z "${GIT_SSH_COMMAND:-}" && -z "$(git config --get core.sshCommand 2>/dev/null)" ]]; then
      run+=(-e "GIT_SSH_COMMAND=ssh -o IgnoreUnknown=UseKeychain")
    fi
  fi
  if [[ "$(uname -s)" == "Darwin" ]]; then
    # Docker Desktop expose l'agent SSH du Mac à cet emplacement, sur un socket
    # root:root en rw-rw---- : le groupe root suffit pour s'en servir sans
    # quitter l'identité de l'hôte.
    run+=(-v "/run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock"
          -e "SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock" --group-add 0)
  elif [[ -n "${SSH_AUTH_SOCK:-}" && -S "$SSH_AUTH_SOCK" ]]; then
    run+=(-v "$SSH_AUTH_SOCK:$SSH_AUTH_SOCK" -e "SSH_AUTH_SOCK=$SSH_AUTH_SOCK")
  fi

  # Claude Code est installé sur le poste, pas dans l'image : l'interface écrit
  # sa demande dans un fichier de relais et s'arrête ; on lance claude ici, dans
  # le dossier courant, puis on relance l'interface, qui retrouve l'opération
  # en pause.
  if ! command -v claude >/dev/null 2>&1; then
    exec docker "${run[@]}" j2s/jgit:local jgit-ui
  fi
  local relay status prompt
  JGIT_UI_RELAY_DIR=$(mktemp -d "${TMPDIR:-/tmp}/jgit-ui.XXXXXX") || exec docker "${run[@]}" j2s/jgit:local jgit-ui
  jgit_on_exit jgit_ui_relay_cleanup
  # Chemin physique (/private/var/… sur Mac) : c'est lui que Docker partage.
  JGIT_UI_RELAY_DIR=$(cd "$JGIT_UI_RELAY_DIR" && pwd -P)
  relay="$JGIT_UI_RELAY_DIR/claude.request"
  run+=(-v "$JGIT_UI_RELAY_DIR:$JGIT_UI_RELAY_DIR" -e "JGIT_UI_CLAUDE_RELAY=$relay")
  while :; do
    status=0
    docker "${run[@]}" j2s/jgit:local jgit-ui || status=$?
    [[ -s "$relay" ]] || return "$status"
    prompt=$(cat "$relay")
    rm -f "$relay"
    printf "%sClaude Code prend la main. Pour revenir à jgit ui : /exit (ou Ctrl+D deux fois).%s\n" "$C_YELLOW" "$C_RESET" >&2
    jgit_ui_claude "$prompt"
  done
}

# Lance Claude Code sur le poste, dans le dossier courant. Le skill jgit-demo
# est livré avec jgit ; si ni le projet ni ~/.claude ne l'installent, on le
# donne à Claude (accès au dossier et chemin dans la demande) plutôt que de le
# laisser résoudre sans lui. En natif, cli.tsx fait de même.
jgit_ui_claude() {
  local prompt="$1" skill="$JGIT_HOME/.claude/skills/jgit-demo" top
  local args=()
  top=$(git rev-parse --show-toplevel 2>/dev/null) || top="$PWD"
  if [[ -f "$skill/SKILL.md" && ! -e "$HOME/.claude/skills/jgit-demo" && ! -e "$top/.claude/skills/jgit-demo" ]]; then
    args=(--add-dir "$skill")
    prompt="$prompt Le skill jgit-demo n'est pas installé dans ce projet : lis $skill/SKILL.md et suis-le."
  fi
  claude ${args[@]+"${args[@]}"} "$prompt" || true
}

jgit_ui_relay_cleanup() {
  [[ -n "${JGIT_UI_RELAY_DIR:-}" ]] && rm -rf "$JGIT_UI_RELAY_DIR"
  return 0
}

jgit_ui_native() {
  if [[ ! -f "$JGIT_HOME/ui/dist/src/cli.js" ]]; then
    jgit_fail ui_not_built "$JGIT_EXIT_ERROR" \
      "L'interface n'est pas construite sur ce poste." \
      "(cd $JGIT_HOME/ui && npm ci && npm run build)"
  fi
  exec node "$JGIT_HOME/ui/dist/src/cli.js" --jgit "$JGIT_HOME/jgit.sh"
}
