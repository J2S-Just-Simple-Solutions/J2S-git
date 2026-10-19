import { test } from 'node:test';
import assert from 'node:assert/strict';
import { render } from 'ink-testing-library';
import { PickTicketsScreen, filterCandidates } from '../src/screens/PickTicketsScreen.js';
import { matches } from '../src/filter.js';
import { windowAround } from '../src/viewport.js';
import type { AnyDoc, Candidate } from '../src/types.js';
import { FakeRunner, KEYS, tick } from './fixtures.js';

function candidate(ticket: string, subject: string, delivered = false): Candidate {
  return { ticket, updated_at: '2026-10-12T08:00:00+02:00', last_subject: subject, author: 'Yann', delivered };
}

const CANDIDATES: Candidate[] = [
  candidate('feature/FACT-1', 'Affiche le total TTC'),
  candidate('feature/FACT-12', 'Affiche la remise fidélité'),
  candidate('feature/MENU-3', 'Nouveau menu'),
  candidate('hotfix/URGENT-9', 'Corrige le panier', true),
];

function picker(candidates: Candidate[] = CANDIDATES) {
  const doc: AnyDoc = { schema: 'jgit.demo.candidates/1', ok: true, demo: null, base: 'develop', candidates };
  const runner = new FakeRunner(() => ({ doc }));
  const result: { done: string[] | null; cancelled: boolean } = { done: null, cancelled: false };
  const view = render(
    <PickTicketsScreen
      runner={runner}
      demo={null}
      title="Tickets de la démo"
      allowEmpty={false}
      onDone={(tickets) => {
        result.done = tickets;
      }}
      onCancel={() => {
        result.cancelled = true;
      }}
      onError={() => {}}
    />,
  );
  return { ...view, result };
}

async function type(stdin: { write: (data: string) => void }, text: string) {
  for (const char of text) {
    stdin.write(char);
    await tick(10);
  }
  await tick();
}

test('le filtre ignore la casse et les accents, et chaque mot doit apparaître', () => {
  assert.ok(matches('fidelite', 'Affiche la remise fidélité'));
  assert.ok(matches('FACT remise', 'feature/FACT-12 Affiche la remise fidélité'));
  assert.ok(!matches('fact menu', 'feature/FACT-12 Affiche la remise fidélité'));
  assert.equal(filterCandidates(CANDIDATES, 'fact', false).length, 2);
  assert.equal(filterCandidates(CANDIDATES, 'urgent', false).length, 0);
  assert.equal(filterCandidates(CANDIDATES, 'urgent', true).length, 1);
});

test('le ticket exactement tapé passe en tête', () => {
  const list = [
    candidate('feature/PERF-173', 'a'),
    candidate('feature/PERF-17', 'b'),
    candidate('feature/AUTRE', 'mentionne PERF-17'),
    candidate('feature/X-PERF-17', 'c'),
  ];
  assert.deepEqual(
    filterCandidates(list, 'perf-17', false).map((item) => item.ticket),
    ['feature/PERF-17', 'feature/PERF-173', 'feature/X-PERF-17', 'feature/AUTRE'],
  );
});

test('taper réduit la liste', async () => {
  const { lastFrame, stdin } = picker();
  await tick();
  await type(stdin, 'fact');
  const frame = lastFrame() ?? '';
  assert.match(frame, /feature\/FACT-1 /);
  assert.match(frame, /feature\/FACT-12/);
  assert.doesNotMatch(frame, /MENU-3/);
});

test('quand il ne reste qu’un ticket, il est coché tout seul ; ⏎ l’ajoute et vide la saisie', async () => {
  const { lastFrame, stdin } = picker();
  await tick();
  await type(stdin, 'me');
  let frame = lastFrame() ?? '';
  assert.match(frame, /\[✓\] feature\/MENU-3/);
  assert.match(frame, /✓ feature\/MENU-3 sélectionné : ⏎ pour l'ajouter/);
  assert.match(frame, /Aucun ticket choisi/);
  // Continuer à taper affine la même saisie : le ticket reste coché.
  await type(stdin, 'nu');
  assert.match(lastFrame() ?? '', /\[✓\] feature\/MENU-3/);
  stdin.write(KEYS.enter);
  await tick();
  frame = lastFrame() ?? '';
  assert.match(frame, /feature\/MENU-3 ajouté\./);
  assert.match(frame, /Dans la démo, dans l'ordre : 1\. feature\/MENU-3/);
  assert.match(frame, /tapez pour filtrer/);
});

test('une saisie qui ne désigne plus le ticket le décoche', async () => {
  const { lastFrame, stdin } = picker();
  await tick();
  await type(stdin, 'menu');
  assert.match(lastFrame() ?? '', /\[✓\] feature\/MENU-3/);
  await type(stdin, 'x');
  assert.match(lastFrame() ?? '', /Aucun ticket ne correspond/);
  assert.doesNotMatch(lastFrame() ?? '', /sélectionné/);
});

test('plusieurs choix : ↓ puis ⏎ ajoute le ticket sélectionné ; ⏎ à vide valide, dans l’ordre', async () => {
  const { stdin, result } = picker();
  await tick();
  await type(stdin, 'menu');
  stdin.write(KEYS.enter);
  await tick();
  await type(stdin, 'fact');
  stdin.write(KEYS.down);
  await tick();
  stdin.write(KEYS.enter);
  await tick();
  stdin.write(KEYS.enter);
  await tick();
  assert.deepEqual(result.done, ['feature/MENU-3', 'feature/FACT-12']);
});

test('rien n’est jamais ajouté sans ⏎, même quand un ticket est coché d’office', async () => {
  const { lastFrame, stdin, result } = picker();
  await tick();
  await type(stdin, 'fact-12');
  assert.match(lastFrame() ?? '', /\[✓\] feature\/FACT-12/);
  stdin.write('\u007F');
  await tick();
  // « fact-1 » : deux tickets, plus rien de coché, rien d'ajouté.
  assert.doesNotMatch(lastFrame() ?? '', /sélectionné/);
  assert.match(lastFrame() ?? '', /Aucun ticket choisi/);
  assert.equal(result.done, null);
});

test('⌫ sur une saisie vide retire le dernier ticket choisi ; échap vide puis annule', async () => {
  const { lastFrame, stdin, result } = picker();
  await tick();
  await type(stdin, 'menu');
  stdin.write(KEYS.enter);
  await tick();
  stdin.write('\u007F');
  await tick();
  assert.match(lastFrame() ?? '', /feature\/MENU-3 retiré\./);
  assert.match(lastFrame() ?? '', /Aucun ticket choisi/);
  await type(stdin, 'fa');
  stdin.write(KEYS.escape);
  await tick();
  assert.equal(result.cancelled, false);
  assert.match(lastFrame() ?? '', /tapez pour filtrer/);
  stdin.write(KEYS.escape);
  await tick();
  assert.equal(result.cancelled, true);
});

test('les tickets livrés sont masqués, tab les montre', async () => {
  const { lastFrame, stdin } = picker();
  await tick();
  assert.doesNotMatch(lastFrame() ?? '', /URGENT-9/);
  assert.match(lastFrame() ?? '', /tab livrés \(1\)/);
  stdin.write('\t');
  await tick();
  assert.match(lastFrame() ?? '', /hotfix\/URGENT-9\s+déjà livré dans develop/);
});

test('une longue liste n’affiche qu’une fenêtre qui suit la sélection', async () => {
  const many = Array.from({ length: 120 }, (_, index) => candidate(`feature/T-${index + 1}`, `Ticket ${index + 1}`));
  const { lastFrame, stdin } = picker(many);
  await tick();
  let frame = lastFrame() ?? '';
  assert.match(frame, /feature\/T-1 /);
  assert.doesNotMatch(frame, /feature\/T-120/);
  assert.match(frame, /↓ \d+ de plus/);
  assert.ok(frame.split('\n').length <= 24, `écran de ${frame.split('\n').length} lignes`);
  for (let i = 0; i < 30; i += 1) stdin.write(KEYS.down);
  await tick();
  frame = lastFrame() ?? '';
  assert.match(frame, /❯ \[ \] feature\/T-31 /);
  assert.match(frame, /↑ \d+ de plus/);
});

test('la fenêtre contient toujours le curseur', () => {
  assert.deepEqual(windowAround(5, 2, 10), { start: 0, end: 5 });
  assert.deepEqual(windowAround(100, 0, 10), { start: 0, end: 10 });
  assert.deepEqual(windowAround(100, 50, 10), { start: 45, end: 55 });
  assert.deepEqual(windowAround(100, 99, 10), { start: 90, end: 100 });
});
