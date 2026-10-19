#!/bin/sh
# Le conteneur tourne sous l'identité de l'utilisateur de l'hôte, pour que les
# fichiers du dépôt monté lui appartiennent toujours. ssh refuse de démarrer si
# cette identité n'existe pas dans /etc/passwd : on l'y déclare au besoin.
if ! getent passwd "$(id -u)" >/dev/null 2>&1; then
  echo "jgit:x:$(id -u):$(id -g):jgit:/home/jgit:/bin/sh" >> /etc/passwd
fi
exec "$@"
