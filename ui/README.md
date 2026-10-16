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
| `src/screens/` | liste, détail, nom, choix de la base, choix de tickets, confirmation du plan, conflit |
| `src/filter.ts` | filtrage à la frappe (sans casse ni accents) et pertinence (identifiant exact d'abord) |
| `src/viewport.ts` | fenêtre des listes longues : seul ce qui tient à l'écran est affiché |
| `test/` | tests (`node:test` + `ink-testing-library`) avec un `jgit` simulé |

## Créer une démo

Trois étapes : le nom ; **la base** (« Base de la nouvelle démo », la sélection
part sur la préprod, la liste — `jgit demo bases` — se filtre à la frappe) ; les
tickets, comparés à cette base (`jgit demo candidates --based-on`). Le plan
montré avant la création rappelle la base, et la commande passe toujours
`--based-on` explicitement.

## Choisir des tickets

Un projet compte souvent des centaines de branches : on ne les parcourt pas, on
les **cherche**.

| Touche | Effet |
| --- | --- |
| lettres, chiffres | filtrent la liste (numéro, nom de branche, dernier message) ; le ticket exactement tapé passe en tête |
| — | quand **un seul** ticket correspond, il est **coché tout seul** ; il ne s'ajoute qu'avec ⏎, pour qu'un « 123 » déjà unique ne parte pas sur un autre ticket au « 4 » suivant |
| ↑ ↓ (ou ctrl-p, ctrl-n), page ↑ ↓ | déplacent la sélection dans la liste réduite |
| ⏎ | ajoute le ticket sélectionné et vide la saisie ; saisie vide : valide le choix |
| espace | ajoute ou retire le ticket sélectionné |
| ⌫ | efface un caractère ; saisie vide : retire le dernier ticket choisi |
| tab | montre ou masque les tickets déjà livrés (masqués par défaut) |
| échap | vide la saisie, puis annule |

L'ordre des tickets choisis est leur ordre dans la démo.

Toutes les listes n'affichent qu'une fenêtre qui tient dans le terminal, avec
« ↑ N de plus » / « ↓ N de plus » : un écran plus haut que le terminal ferait
défiler celui-ci au lieu de bouger la sélection.

```bash
npm ci
npm test        # compile puis joue les tests
```
