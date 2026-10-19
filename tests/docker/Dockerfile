# Image de test Linux de jgit.
#
# Debian plutôt qu'Alpine : jgit est écrit pour bash et les outils GNU/BSD
# courants, pas pour busybox. bookworm fournit bash 5.2, git 2.39 et python3
# (requis par le pilote de pseudo-terminal des tests interactifs).
#
#   ./tests/run-in-docker.sh            construit l'image et joue toute la suite
#   ./tests/run-in-docker.sh demo -v    mêmes arguments que tests/run.sh
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends git python3 ca-certificates procps \
 && rm -rf /var/lib/apt/lists/*

# Le dépôt jgit est monté ici en lecture seule par run-in-docker.sh.
WORKDIR /jgit
