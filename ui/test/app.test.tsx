import { test } from 'node:test';
import assert from 'node:assert/strict';
import { render } from 'ink-testing-library';
import { App } from '../src/app.js';
import type { AnyDoc } from '../src/types.js';
import { isValidDemoName } from '../src/screens/NameScreen.js';
import { FakeRunner, KEYS, noPause, summary, tick } from './fixtures.js';

const listDoc: AnyDoc = {
  schema: 'jgit.demo.list/1',
  ok: true,
  demos: [
    summary({ name: 'client-a', branch: 'demo/client-a', needs_rebase: true, behind_base: 4, tickets_needing_attention: 1 }),
    summary(),
  ],
  archived_count: 1,
};

const showDoc: AnyDoc = {
  schema: 'jgit.demo.show/1',
  ok: true,
  demo: summary({ name: 'client-a', branch: 'demo/client-a', needs_rebase: true, behind_base: 4 }),
  tickets: [
    { ticket: 'feature/A-1', type: 'feature', id: 'A-1', position: 1, status: 'up_to_date', delivered: false, delivered_with_pending_work: false, commits_not_in_demo: 0, suggested_action: 'none' },
    { ticket: 'feature/A-2', type: 'feature', id: 'A-2', position: 2, status: 'ahead', delivered: false, delivered_with_pending_work: false, commits_not_in_demo: 2, suggested_action: 'add' },
    { ticket: 'hotfix/H-3', type: 'hotfix', id: 'H-3', position: 3, status: 'up_to_date', delivered: true, delivered_with_pending_work: false, commits_not_in_demo: 0, suggested_action: 'drop' },
  ],
  foreign_commits: [],
  release_command: 'jgit release merge --from feature/A-1 --from feature/A-2',
};

const conflictDoc: AnyDoc = {
  schema: 'jgit.conflict/1',
  ok: false,
  operation: 'demo_rebase',
  target: 'demo/client-a',
  paused: true,
  error: { code: 'conflict', exit_code: 3, message: 'Conflit pendant le rebase de la démo demo/client-a sur develop, sur le ticket feature/A-2.', hint: 'jgit demo continue client-a' },
  branch: 'jgit_demo_client-a',
  commit: { sha: 'abc', subject: 'Modifie la facturation' },
  conflicted_files: [{ path: 'src/facturation.php', kind: 'both_modified' }],
  progress: { done: 2, total: 5 },
  commands: { continue: 'jgit demo continue client-a', abort: 'jgit demo abort client-a' },
  context: { demo: 'client-a', ticket: 'feature/A-2' },
};

function app(runner: FakeRunner) {
  return render(<App runner={runner} claudeAvailable={false} stage={async () => {}} onSpawn={() => {}} />);
}

test('la liste montre chaque démo et son état', async () => {
  const runner = new FakeRunner((args) => (args[0] === 'util' ? { doc: noPause } : { doc: listDoc }));
  const { lastFrame } = app(runner);
  await tick();
  const frame = lastFrame() ?? '';
  assert.match(frame, /client-a/);
  assert.match(frame, /en retard de 4 commit\(s\)/);
  assert.match(frame, /sprint12/);
  assert.match(frame, /✔ à jour/);
  assert.match(frame, /1 démo\(s\) archivée\(s\)/);
});

test('⏎ ouvre le détail, ticket par ticket, avec la suggestion', async () => {
  const runner = new FakeRunner((args) => {
    if (args[0] === 'util') return { doc: noPause };
    if (args[1] === 'list') return { doc: listDoc };
    return { doc: showDoc };
  });
  const { lastFrame, stdin } = app(runner);
  await tick();
  stdin.write(KEYS.enter);
  await tick();
  const frame = lastFrame() ?? '';
  assert.ok(runner.called('demo show demo/client-a'));
  assert.match(frame, /Démo client-a/);
  assert.match(frame, /2 commits pas encore dans la démo/);
  assert.match(frame, /livré dans develop/);
  assert.match(frame, /jgit release merge --from feature\/A-1/);
});

test('rebaser montre le plan du --dry-run, puis applique en mode pause', async () => {
  const runner = new FakeRunner((args) => {
    if (args[0] === 'util') return { doc: noPause };
    if (args[1] === 'list') return { doc: listDoc };
    if (args[1] === 'show') return { doc: showDoc };
    if (args[1] === 'rebase' && args.includes('--dry-run')) {
      return { doc: { schema: 'jgit.demo.result/1', ok: true, operation: 'rebase', demo: 'client-a', branch: 'demo/client-a', changed: true, pushed: false, dry_run: true, added: [], updated: [], dropped: [{ ticket: 'hotfix/H-3', reason: 'delivered' }], warnings: [] } };
    }
    return { doc: { schema: 'jgit.demo.result/1', ok: true, operation: 'rebase', demo: 'client-a', branch: 'demo/client-a', changed: true, pushed: true, dry_run: false, dropped: [{ ticket: 'hotfix/H-3', reason: 'delivered' }] } };
  });
  const { lastFrame, stdin } = app(runner);
  await tick();
  stdin.write(KEYS.enter);
  await tick();
  stdin.write('b');
  await tick();
  assert.match(lastFrame() ?? '', /- hotfix\/H-3 \(déjà livré dans la base\)/);
  assert.match(lastFrame() ?? '', /Rien n'a encore été modifié/);
  stdin.write(KEYS.enter);
  await tick();
  assert.ok(runner.calls.some((call) => call.join(' ') === 'demo rebase client-a --on-conflict pause'));
  assert.match(lastFrame() ?? '', /Démo demo\/client-a publiée\. \(retiré : hotfix\/H-3\)/);
});

test('un conflit en pause ouvre l’écran de conflit, et c reprend', async () => {
  let continued = false;
  const runner = new FakeRunner((args) => {
    if (args[0] === 'util') return { doc: noPause };
    if (args[1] === 'list') return { doc: listDoc };
    if (args[1] === 'show') return { doc: showDoc };
    if (args[1] === 'add') return { doc: conflictDoc, exitCode: 3 };
    if (args[1] === 'continue') {
      continued = true;
      return { doc: { schema: 'jgit.demo.result/1', ok: true, operation: 'add', demo: 'client-a', branch: 'demo/client-a', changed: true, pushed: true, dry_run: false, updated: ['feature/A-2'] } };
    }
    return { doc: null };
  });
  const { lastFrame, stdin } = app(runner);
  await tick();
  stdin.write(KEYS.enter);
  await tick();
  stdin.write(KEYS.down);
  await tick();
  stdin.write('u');
  await tick();
  const frame = lastFrame() ?? '';
  assert.ok(runner.calls.some((call) => call.join(' ') === 'demo add client-a --from feature/A-2 --on-conflict pause'));
  assert.match(frame, /Conflit en attente/);
  assert.match(frame, /src\/facturation\.php \(modifié des deux côtés\)/);
  assert.match(frame, /Ticket\s+feature\/A-2/);
  stdin.write('c');
  await tick();
  assert.ok(continued);
  assert.ok(runner.calls.some((call) => call.join(' ') === 'demo continue client-a'));
});

test('au démarrage, une opération déjà en pause est montrée d’abord', async () => {
  const runner = new FakeRunner((args) => {
    if (args[0] === 'util') {
      return {
        doc: {
          schema: 'jgit.status/1',
          ok: true,
          current_branch: 'jgit_demo_client-a',
          operation_in_progress: {
            operation: 'demo_rebase',
            target: 'demo/client-a',
            label: 'le rebase de la démo demo/client-a sur develop',
            branch: 'jgit_demo_client-a',
            commit: { sha: 'abc', subject: 'Modifie la facturation' },
            conflicted_files: [],
            commands: { continue: 'jgit demo continue client-a', abort: 'jgit demo abort client-a' },
            context: { demo: 'client-a', ticket: 'feature/A-2' },
          },
        },
      };
    }
    return { doc: listDoc };
  });
  const { lastFrame, stdin } = app(runner);
  await tick();
  assert.match(lastFrame() ?? '', /Plus aucun fichier en conflit : c pour reprendre/);
  stdin.write('x');
  await tick();
  assert.match(lastFrame() ?? '', /Tout annuler \? Rien ne sera publié/);
  stdin.write('y');
  await tick();
  assert.ok(runner.calls.some((call) => call.join(' ') === 'demo abort client-a'));
});

test('créer une démo : nom, tickets dans l’ordre coché, plan, puis création', async () => {
  const runner = new FakeRunner((args) => {
    if (args[0] === 'util') return { doc: noPause };
    if (args[1] === 'list') return { doc: { schema: 'jgit.demo.list/1', ok: true, demos: [], archived_count: 0 } };
    if (args[1] === 'candidates') {
      return {
        doc: {
          schema: 'jgit.demo.candidates/1', ok: true, demo: null, base: 'develop',
          candidates: [
            { ticket: 'feature/B-1', updated_at: '2026-10-12T08:00:00+02:00', last_subject: 'B1', author: 'Yann', delivered: false },
            { ticket: 'feature/B-2', updated_at: '2026-10-11T08:00:00+02:00', last_subject: 'B2', author: 'Yann', delivered: false },
          ],
        },
      };
    }
    if (args[1] === 'create' && args.includes('--dry-run')) {
      return { doc: { schema: 'jgit.demo.result/1', ok: true, operation: 'create', demo: 'vitrine', branch: 'demo/vitrine', changed: true, pushed: false, dry_run: true, added: ['feature/B-2', 'feature/B-1'] } };
    }
    if (args[1] === 'create') {
      return { doc: { schema: 'jgit.demo.result/1', ok: true, operation: 'create', demo: 'vitrine', branch: 'demo/vitrine', changed: true, pushed: true, dry_run: false, added: ['feature/B-2', 'feature/B-1'] } };
    }
    return { doc: showDocFor('vitrine') };
  });
  const { lastFrame, stdin } = app(runner);
  await tick();
  assert.match(lastFrame() ?? '', /Aucune démo/);
  stdin.write('n');
  await tick();
  stdin.write('vitrine');
  await tick();
  assert.match(lastFrame() ?? '', /demo\/vitrine/);
  stdin.write(KEYS.enter);
  await tick();
  stdin.write(KEYS.down);
  await tick();
  stdin.write(KEYS.space);
  await tick();
  stdin.write(KEYS.up);
  await tick();
  stdin.write(KEYS.space);
  await tick();
  stdin.write(KEYS.enter);
  await tick();
  assert.ok(runner.calls.some((call) => call.join(' ') === 'demo create vitrine --from feature/B-2 --from feature/B-1 --dry-run'));
  assert.match(lastFrame() ?? '', /\+ feature\/B-2/);
  stdin.write(KEYS.enter);
  await tick();
  assert.ok(runner.calls.some((call) => call.join(' ') === 'demo create vitrine --from feature/B-2 --from feature/B-1 --on-conflict pause'));
  assert.ok(runner.called('demo show demo/vitrine'));
});

test('les noms de démo suivent la règle de jgit', () => {
  assert.ok(isValidDemoName('sprint12'));
  assert.ok(isValidDemoName('client-a.v2'));
  assert.ok(!isValidDemoName('-tiret'));
  assert.ok(!isValidDemoName('sprint..12'));
  assert.ok(!isValidDemoName(''));
});

function showDocFor(name: string): AnyDoc {
  return {
    schema: 'jgit.demo.show/1',
    ok: true,
    demo: summary({ name, branch: `demo/${name}` }),
    tickets: [],
    foreign_commits: [],
    release_command: null,
  };
}
