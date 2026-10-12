# jgit ui

Interface en terminal des démos jgit, en TypeScript avec
[Ink](https://github.com/vadimdemedes/ink). Elle **ne contient aucune logique
git** : elle appelle `jgit … --json` et lit les documents décrits dans
[`docs/06-contrat-cli.md`](../docs/06-contrat-cli.md).

```bash
jgit ui                     # dans Docker (image j2s/jgit:local)
JGIT_UI=native jgit ui      # avec le node du poste, après « npm ci && npm run build »
```

| Fichier | Rôle |
| --- | --- |
| `src/cli.tsx` | lanceur : rend l'interface, lui prête le terminal pour l'éditeur ou Claude Code, la relance |
| `src/app.tsx` | écrans et enchaînements : plan (`--dry-run`) avant chaque réécriture, `--on-conflict pause` pour toute modification |
| `src/jgit.ts` | appel de `jgit … --json`, lecture du document |
| `src/screens/` | liste, détail, choix de tickets, nom, confirmation du plan, conflit |
| `test/` | tests (`node:test` + `ink-testing-library`) avec un `jgit` simulé |

```bash
npm ci
npm test        # compile puis joue les tests
```
