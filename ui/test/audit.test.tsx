import { test } from 'node:test';
import assert from 'node:assert/strict';
import { render } from 'ink-testing-library';
import { App } from '../src/app.js';
import { reportLines } from '../src/screens/AuditScreen.js';
import type { AnyDoc, AuditDoc, AuditTicket } from '../src/types.js';
import { FakeRunner, KEYS, noPause, summary, tick } from './fixtures.js';

function ticket(overrides: Partial<AuditTicket>): AuditTicket {
  const name = overrides.ticket ?? 'feature/X';
  return {
    ticket: name, type: 'feature', id: name.replace('feature/', ''), base: 'develop', base_recorded: true, behind_base: 1,
    status: 'to_rebase', delivered: false, pr_validated: false, owner: { author: 'Yann', email: 'yann@j2s.example' },
    last_activity: '2026-10-19T08:00:00+02:00', command: `jgit feature rebase ${name.replace('feature/', '')}`, conflict: null, demos: [],
    ...overrides,
  };
}

const report: AuditDoc = {
  schema: 'jgit.audit/1',
  ok: true,
  scope: 'all',
  tickets: [
    ticket({ ticket: 'feature/AUTRE-1' }),
    ticket({ ticket: 'feature/AUTRE-2' }),
    ticket({ ticket: 'feature/AUTRE-3', owner: { author: 'Dominique', email: 'dominique@j2s.example' } }),
    ticket({ ticket: 'feature/MENU-3', demos: ['client-a'] }),
    ticket({ ticket: 'feature/FINI-9', status: 'up_to_date', behind_base: 0, command: null }),
    ticket({
      ticket: 'feature/FACT-2', status: 'conflicts', demos: ['client-a'], command: 'jgit feature rebase FACT-2 --on-conflict pause',
      conflict: {
        commit: { sha: 'fefe23f0000', subject: 'Affiche la remise fidélité', author: 'Yann', email: 'yann@j2s.example', date: '2026-10-12' },
        files: [{ path: 'src/accueil.txt', kind: 'both_modified', other: { sha: '2a926dd', subject: "Nouveau message d'accueil", author: 'Camille', email: 'camille@j2s.example', origin: 'develop' } }],
      },
    }),
  ],
  demos: [
    {
      name: 'client-a', branch: 'demo/client-a', base: 'develop', behind_base: 1, status: 'conflicts', message: null,
      prerequisites: [
        { ticket: 'feature/MENU-3', status: 'to_rebase', command: 'jgit feature rebase MENU-3' },
        { ticket: 'feature/FACT-2', status: 'conflicts', command: 'jgit feature rebase FACT-2 --on-conflict pause' },
      ],
      held: ['feature/FACT-2'],
      actions: [
        { kind: 'ticket', command: 'jgit feature rebase MENU-3', reason: "d'abord rebaser le ticket chez lui : en retard de 1 commit(s) sur develop — propriétaire : Yann" },
        { kind: 'ticket', command: 'jgit feature rebase FACT-2 --on-conflict pause', reason: "d'abord rebaser le ticket chez lui : son rebase sur develop coince (voir TICKETS) — propriétaire : Yann" },
        { kind: 'demo', command: 'jgit demo rebase client-a --from feature/FACT-2', reason: 'base develop en retard de 1 commit(s) ; reprend feature/FACT-2 depuis leur branche' },
        { kind: 'demo', command: 'jgit demo add client-a --from feature/MENU-3 --on-conflict pause', reason: 'feature/MENU-3 a de nouveaux commits' },
      ],
      dropped: [],
      conflicts: [
        {
          ticket: 'feature/MENU-3', step: 'add',
          commit: { sha: 'abcabc10000', subject: 'Réorganise le menu', author: 'Yann', email: 'yann@j2s.example', date: '2026-10-13' },
          files: [{ path: 'src/menu.txt', kind: 'both_modified', other: { sha: '3b3b3b3', subject: 'Menu du client', author: 'Dominique', email: 'dominique@j2s.example', origin: 'feature/CLIENT-4' } }],
          commands: { resolve: 'jgit demo add client-a --from feature/MENU-3 --on-conflict pause', drop: 'jgit demo drop client-a --from feature/MENU-3' },
        },
      ],
    },
    {
      name: 'recette', branch: 'demo/recette', base: 'main', behind_base: 0, status: 'up_to_date', message: null,
      prerequisites: [], held: [], actions: [], dropped: [], conflicts: [],
    },
  ],
  summary: {
    tickets: { total: 6, up_to_date: 1, to_rebase: 4, conflicts: 1, base_missing: 0, delivered: 0 },
    demos: { total: 2, up_to_date: 1, feasible: 0, conflicts: 1, blocked: 0, skipped_legacy: 0 },
  },
};

const listDoc: AnyDoc = {
  schema: 'jgit.demo.list/1', ok: true,
  demos: [summary({ name: 'client-a', branch: 'demo/client-a' }), summary({ name: 'recette', branch: 'demo/recette', base: 'main' })],
  archived_count: 0,
};

test("l'état des lieux dit qui est concerné : le commit en cause, et en face", () => {
  const text = reportLines(report).map((line) => line.text).join('\n');
  assert.match(text, /^TICKETS \(6\)\n  ✖ feature\/FACT-2 — en retard de 1 commit\(s\) sur develop, son rebase coince/);
  assert.match(text, /« Affiche la remise fidélité » par Yann <yann@j2s\.example>, le 2026-10-12/);
  assert.match(text, /en face : « Nouveau message d'accueil » par Camille <camille@j2s\.example> \(develop\)/);
  assert.match(text, /→ jgit feature rebase FACT-2 --on-conflict pause   \(propriétaire : Yann · démos : client-a\)/);
  assert.match(text, /↻ feature\/MENU-3 — en retard de 1 commit\(s\) sur develop, son rebase passe/);
  assert.match(text, /✔ 1 à jour sur leur base, 0 déjà livré\(s\)/);
});

test('les tickets hors démo à rebaser sont comptés par propriétaire', () => {
  const text = reportLines(report).map((line) => line.text).join('\n');
  assert.doesNotMatch(text, /AUTRE-1/);
  assert.match(text, /↻ 3 autre\(s\) ticket\(s\) en retard sur leur base, rebase sans conflit — par propriétaire : Yann \(2\), Dominique \(1\)/);
});

test("pour chaque démo : les conflits à résoudre dans la démo, puis les commandes dans l'ordre", () => {
  const text = reportLines(report).map((line) => line.text).join('\n');
  assert.match(text, /DÉMOS \(2\)/);
  assert.match(text, /demo\/client-a  \(base develop\)/);
  assert.match(text, /✖ Conflit : feature\/MENU-3 \(à l'ajout de ses nouveaux commits\)/);
  assert.match(text, /en face : « Menu du client » par Dominique <dominique@j2s\.example> \(feature\/CLIENT-4\)/);
  assert.match(text, /→ résoudre dans la démo : jgit demo add client-a --from feature\/MENU-3 --on-conflict pause/);
  assert.match(text, /Dans l'ordre :\n      jgit feature rebase MENU-3\n.*\n      jgit feature rebase FACT-2 --on-conflict pause\n.*\n      jgit demo rebase client-a --from feature\/FACT-2/);
  assert.match(text, /⚠ feature\/FACT-2 : à simuler de nouveau une fois rebasé\(s\) chez eux\./);
  assert.match(text, /demo\/recette  \(base main\)\n    ✔ À jour/);
  assert.match(text, /Bilan : tickets — 1 à jour, 4 à rebaser, 1 en conflit, 0 base disparue, 0 livré\(s\)/);
  assert.match(text, /démos — 1 à jour, 0 faisable\(s\), 1 en conflit, 0 bloquée\(s\)/);
});

test("v depuis la liste lance l'état des lieux complet", async () => {
  const runner = new FakeRunner((args) => {
    if (args[0] === 'util') return { doc: noPause };
    if (args[1] === 'list') return { doc: listDoc };
    if (args[0] === 'audit') return { doc: report, exitCode: 3 };
    return { doc: null };
  });
  const { lastFrame, stdin } = render(<App runner={runner} claudeAvailable={false} stage={async () => {}} onSpawn={() => {}} />);
  await tick();
  stdin.write('v');
  await tick();
  assert.ok(runner.calls.some((call) => call.join(' ') === 'audit'));
  const frame = lastFrame() ?? '';
  assert.match(frame, /État des lieux/);
  assert.match(frame, /Simulation : rien n'a été modifié/);
  assert.match(frame, /Camille/);
  stdin.write(KEYS.escape);
  await tick();
  assert.match(lastFrame() ?? '', /Démos du projet/);
});

test('v depuis le détail fait l’état des lieux de cette démo seulement', async () => {
  const runner = new FakeRunner((args) => {
    if (args[0] === 'util') return { doc: noPause };
    if (args[1] === 'list') return { doc: listDoc };
    if (args[1] === 'show') {
      return { doc: { schema: 'jgit.demo.show/1', ok: true, demo: summary({ name: 'client-a', branch: 'demo/client-a' }), tickets: [], foreign_commits: [], release_command: null } };
    }
    if (args[0] === 'audit') return { doc: { ...report, scope: 'demos', demos: [report.demos[0]] }, exitCode: 3 };
    return { doc: null };
  });
  const { stdin } = render(<App runner={runner} claudeAvailable={false} stage={async () => {}} onSpawn={() => {}} />);
  await tick();
  stdin.write(KEYS.enter);
  await tick();
  stdin.write('v');
  await tick();
  assert.ok(runner.calls.some((call) => call.join(' ') === 'audit demos client-a'));
});

test('un long rapport défile', async () => {
  const many: AuditDoc = {
    ...report,
    demos: Array.from({ length: 12 }, (_, index) => ({ ...report.demos[0], name: `d${index}`, branch: `demo/d${index}` })),
  };
  const runner = new FakeRunner((args) => {
    if (args[0] === 'util') return { doc: noPause };
    if (args[1] === 'list') return { doc: listDoc };
    return { doc: many, exitCode: 3 };
  });
  const { lastFrame, stdin } = render(<App runner={runner} claudeAvailable={false} stage={async () => {}} onSpawn={() => {}} />);
  await tick();
  stdin.write('v');
  await tick();
  let frame = lastFrame() ?? '';
  assert.match(frame, /↓ \d+ ligne\(s\) de plus/);
  assert.ok(frame.split('\n').length <= 26, `écran de ${frame.split('\n').length} lignes`);
  stdin.write(' ');
  await tick();
  frame = lastFrame() ?? '';
  assert.match(frame, /↑ \d+ ligne\(s\) de plus/);
});
