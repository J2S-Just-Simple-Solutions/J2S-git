import { test } from 'node:test';
import assert from 'node:assert/strict';
import { render } from 'ink-testing-library';
import { App } from '../src/app.js';
import { reportLines } from '../src/screens/CheckScreen.js';
import type { AnyDoc, CheckDoc } from '../src/types.js';
import { FakeRunner, KEYS, noPause, summary, tick } from './fixtures.js';

const report: CheckDoc = {
  schema: 'jgit.demo.check/1',
  ok: true,
  demos: [
    {
      name: 'client-a', branch: 'demo/client-a', base: 'develop', behind_base: 1, status: 'conflicts', message: null,
      actions: [
        { command: 'jgit demo rebase client-a --on-conflict pause', reason: 'base develop en retard de 1 commit(s)' },
        { command: 'jgit demo add client-a --from feature/MENU-3', reason: 'feature/MENU-3 a de nouveaux commits' },
      ],
      dropped: [],
      conflicts: [
        {
          ticket: 'feature/FACT-2', step: 'rebase',
          commit: { sha: 'fefe23f0000', subject: 'Affiche la remise fidélité', author: 'Yann', email: 'yann@j2s.example', date: '2026-10-12' },
          files: [{ path: 'src/accueil.txt', kind: 'both_modified', other: { sha: '2a926dd', subject: "Nouveau message d'accueil", author: 'Camille', email: 'camille@j2s.example', origin: 'develop' } }],
          commands: { resolve: 'jgit demo rebase client-a --on-conflict pause', drop: 'jgit demo drop client-a --from feature/FACT-2' },
        },
      ],
    },
    {
      name: 'recette', branch: 'demo/recette', base: 'main', behind_base: 0, status: 'up_to_date', message: null,
      actions: [], dropped: [], conflicts: [],
    },
  ],
  summary: { demos: 2, up_to_date: 1, feasible: 0, conflicts: 1, blocked: 0, skipped_legacy: 0 },
};

const listDoc: AnyDoc = {
  schema: 'jgit.demo.list/1', ok: true,
  demos: [summary({ name: 'client-a', branch: 'demo/client-a' }), summary({ name: 'recette', branch: 'demo/recette', base: 'main' })],
  archived_count: 0,
};

test('le rapport dit qui est concerné : le commit en cause, et en face', () => {
  const text = reportLines(report).map((line) => line.text).join('\n');
  assert.match(text, /demo\/client-a  \(base develop\)/);
  assert.match(text, /✖ 1 conflit\(s\) à résoudre/);
  assert.match(text, /feature\/FACT-2 — au rebase sur la base à jour/);
  assert.match(text, /« Affiche la remise fidélité » par Yann <yann@j2s\.example>, le 2026-10-12/);
  assert.match(text, /en face : « Nouveau message d'accueil » par Camille <camille@j2s\.example> \(develop\)/);
  assert.match(text, /→ résoudre : jgit demo rebase client-a --on-conflict pause/);
  assert.match(text, /→ ou retirer : jgit demo drop client-a --from feature\/FACT-2/);
  assert.match(text, /jgit demo add client-a --from feature\/MENU-3/);
  assert.match(text, /demo\/recette  \(base main\)\n  ✔ À jour/);
  assert.match(text, /Bilan : 2 démo\(s\) — 1 à jour, 0 faisable\(s\), 1 en conflit/);
});

test('v depuis la liste vérifie toutes les démos', async () => {
  const runner = new FakeRunner((args) => {
    if (args[0] === 'util') return { doc: noPause };
    if (args[1] === 'list') return { doc: listDoc };
    if (args[1] === 'check') return { doc: report, exitCode: 3 };
    return { doc: null };
  });
  const { lastFrame, stdin } = render(<App runner={runner} claudeAvailable={false} stage={async () => {}} onSpawn={() => {}} />);
  await tick();
  stdin.write('v');
  await tick();
  assert.ok(runner.calls.some((call) => call.join(' ') === 'demo check'));
  const frame = lastFrame() ?? '';
  assert.match(frame, /Vérification des mises à jour/);
  assert.match(frame, /Simulation : rien n'a été modifié/);
  assert.match(frame, /Camille/);
  stdin.write(KEYS.escape);
  await tick();
  assert.match(lastFrame() ?? '', /Démos du projet/);
});

test('v depuis le détail vérifie cette démo seulement', async () => {
  const runner = new FakeRunner((args) => {
    if (args[0] === 'util') return { doc: noPause };
    if (args[1] === 'list') return { doc: listDoc };
    if (args[1] === 'show') {
      return { doc: { schema: 'jgit.demo.show/1', ok: true, demo: summary({ name: 'client-a', branch: 'demo/client-a' }), tickets: [], foreign_commits: [], release_command: null } };
    }
    if (args[1] === 'check') return { doc: { ...report, demos: [report.demos[0]] }, exitCode: 3 };
    return { doc: null };
  });
  const { stdin } = render(<App runner={runner} claudeAvailable={false} stage={async () => {}} onSpawn={() => {}} />);
  await tick();
  stdin.write(KEYS.enter);
  await tick();
  stdin.write('v');
  await tick();
  assert.ok(runner.calls.some((call) => call.join(' ') === 'demo check client-a'));
});

test('un long rapport défile', async () => {
  const many: CheckDoc = {
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
