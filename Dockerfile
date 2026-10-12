# Image jgit : la ligne de commande et l'interface en terminal (ui/).
#
# Elle sert aux postes qui ne veulent rien installer (« jgit ui »), et servira à
# Jenkins (temps 2) : « docker run … j2s/jgit:local jgit demo rebase … ».
#
# Debian plutôt qu'Alpine : jgit est écrit pour bash et les outils GNU/BSD
# courants, pas pour busybox (docs/05-portabilite.md).

FROM node:22-bookworm-slim AS ui
WORKDIR /build
COPY ui/package.json ui/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY ui/tsconfig.json ./
COPY ui/src ./src
COPY ui/test ./test
RUN npx tsc -p tsconfig.json && npm prune --omit=dev --no-audit --no-fund

FROM node:22-bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends git openssh-client ca-certificates nano less tzdata \
 && rm -rf /var/lib/apt/lists/*

# Le dépôt monté appartient à l'utilisateur de l'hôte : git doit l'accepter
# sans configuration à écrire (le ~/.gitconfig de l'hôte est monté en lecture).
ENV GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=safe.directory \
    GIT_CONFIG_VALUE_0=* \
    EDITOR=nano \
    HOME=/home/jgit

COPY *.sh /opt/jgit/
COPY --from=ui /build/dist /opt/jgit/ui/dist
COPY --from=ui /build/node_modules /opt/jgit/ui/node_modules
COPY ui/package.json /opt/jgit/ui/package.json
COPY docker/entrypoint.sh /usr/local/bin/jgit-entrypoint

RUN chmod +x /opt/jgit/jgit.sh /usr/local/bin/jgit-entrypoint \
 && ln -s /opt/jgit/jgit.sh /usr/local/bin/jgit \
 && printf '#!/bin/sh\nexec node /opt/jgit/ui/dist/src/cli.js "$@"\n' > /usr/local/bin/jgit-ui \
 && chmod +x /usr/local/bin/jgit-ui \
 && mkdir -p /home/jgit/.ssh \
 && chmod -R 777 /home/jgit \
 && chmod 666 /etc/passwd

ENTRYPOINT ["jgit-entrypoint"]
CMD ["jgit-ui"]
