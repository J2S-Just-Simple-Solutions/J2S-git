# Feuille de route : Jenkins, environnements, prototypes

Ce document cadre les temps 2 et 3 de l'évolution de `jgit`. Rien n'y est encore
réalisé ; il dit ce que le temps 1 (les démos) a déjà préparé, et ce qu'il reste
à trancher.

---

## Temps 2 — Déployer les démos en continu avec Jenkins

### L'idée

On associe des démos à des environnements (« `demo/client-a` → recette-client-a »).
Un job Jenkins planifié (toutes les heures) remet chaque démo à jour sur sa base,
puis déploie l'environnement associé **seulement si la démo a changé**.

```bash
docker run --rm -v "$WORKSPACE:$WORKSPACE" -w "$WORKSPACE" \
  -v "$SSH_AUTH_SOCK:$SSH_AUTH_SOCK" -e SSH_AUTH_SOCK \
  j2s/jgit:local jgit demo rebase client-a --json
```

| Résultat (`jgit.demo.result/1`, code de sortie) | Ce que fait le job |
| --- | --- |
| code 0, `changed: false` | rien : pas de redéploiement inutile |
| code 0, `changed: true` | déploie `new_sha` sur l'environnement associé |
| code 3 (`jgit.conflict/1`, `paused: false`) | ne déploie pas ; notifie avec le ticket et les fichiers en conflit |
| code 4 (`lease_rejected`) | quelqu'un a modifié la démo pendant le job : on réessaiera au prochain passage |
| autre | notifie l'erreur (`error.code`, `error.message`) |

Un conflit se résout sur un poste (`jgit demo rebase client-a --on-conflict pause`,
ou en demandant à Claude) : la résolution devient un commit de la démo, et le
job suivant la rejoue sans conflit.

### Déjà prêt depuis le temps 1

- `jgit` tourne sous Linux, dans l'image `j2s/jgit:local` ; un clone
  `--single-branch` fonctionne, un clone superficiel est refusé proprement.
- Le contrat `--json` et ses codes de sortie ; aucune question n'est posée.
- Une démo inchangée n'est jamais republiée (`changed: false`).
- Sans interaction, un conflit est abandonné proprement et décrit (`jgit.conflict/1`).
- Les publications sont protégées par lease : un humain qui travaille sur la démo
  n'est jamais écrasé par le job.

### À trancher

- **Où vit l'association démo ↔ environnement.** Pistes : un fichier versionné
  dans chaque dépôt applicatif (`.jgit/environments.yml`), ou un paramètre du
  `Jenkinsfile`. Ce n'est pas une propriété de la branche : elle ne doit pas
  être perdue quand une démo est archivée puis remplacée.
- **L'identité git du job** (commits de reconstruction) et la clé SSH de
  déploiement.
- **La notification** : canal, destinataires (l'auteur du ticket en conflit ?).
- **Le déploiement lui-même** : propre à chaque projet.

---

## Temps 3 — Prototypes

### L'idée

Quelqu'un a une idée sans rapport avec un projet existant. Il fait générer un
projet par une IA, qui l'héberge quelque part et donne un lien à partager.

### À définir

- Le gabarit de départ (pile technique, conventions J2S), le lieu d'hébergement
  et sa durée de vie, la gestion des accès au lien.
- La place de `jgit` : probablement aucune dans la génération elle-même ; un
  outil distinct, qui pourra reprendre l'image Docker et la façon de faire du
  skill `jgit-demo` (une IA pilotée par un contrat `--json` et des règles de
  prudence explicites).
