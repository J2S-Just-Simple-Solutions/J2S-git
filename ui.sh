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
  [[ -f "$HOME/.ssh/known_hosts" ]] && run+=(-v "$HOME/.ssh/known_hosts:/home/jgit/.ssh/known_hosts:ro")
  if [[ "$(uname -s)" == "Darwin" ]]; then
    # Docker Desktop expose l'agent SSH du Mac à cet emplacement, sur un socket
    # root:root en rw-rw---- : le groupe root suffit pour s'en servir sans
    # quitter l'identité de l'hôte.
    run+=(-v "/run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock"
          -e "SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock" --group-add 0)
  elif [[ -n "${SSH_AUTH_SOCK:-}" && -S "$SSH_AUTH_SOCK" ]]; then
    run+=(-v "$SSH_AUTH_SOCK:$SSH_AUTH_SOCK" -e "SSH_AUTH_SOCK=$SSH_AUTH_SOCK")
  fi

  exec docker "${run[@]}" j2s/jgit:local jgit-ui
}

jgit_ui_native() {
  if [[ ! -f "$JGIT_HOME/ui/dist/src/cli.js" ]]; then
    jgit_fail ui_not_built "$JGIT_EXIT_ERROR" \
      "L'interface n'est pas construite sur ce poste." \
      "(cd $JGIT_HOME/ui && npm ci && npm run build)"
  fi
  exec node "$JGIT_HOME/ui/dist/src/cli.js" --jgit "$JGIT_HOME/jgit.sh"
}
