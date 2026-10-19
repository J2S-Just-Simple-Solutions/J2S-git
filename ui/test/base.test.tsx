import { test } from 'node:test';
import assert from 'node:assert/strict';
import { render } from 'ink-testing-library';
import { BasePickScreen, filterBases } from '../src/screens/BasePickScreen.js';
import type { AnyDoc, Base } from '../src/types.js';
import { FakeRunner, KEYS, tick } from './fixtures.js';

const BASES: Base[] = [
  { branch: 'develop', role: 'preprod', updated_at: '2026-10-12T08:00:00+02:00', last_subject: 'Préprod' },
  { branch: 'main', role: 'prod', updated_at: '2026-10-11T08:00:00+02:00', last_subject: 'Production' },
  { branch: 'release/1.4.0', role: 'release', updated_at: '2026-10-10T08:00:00+02:00', last_subject: 'Version 1.4' },
  { branch: 'release/1.3.0', role: 'release', updated_at: '2026-10-01T08:00:00+02:00', last_subject: 'Version 1.3' },
];

function screen() {
  const doc: AnyDoc = { schema: 'jgit.demo.bases/1', ok: true, default: 'develop', bases: BASES };
  const runner = new FakeRunner(() => ({ doc }));
  const result: { base: string | null; cancelled: boolean } = { base: null, cancelled: false };
  const view = render(
    <BasePickScreen
      runner={runner}
      title="Base"
      onDone={(base) => {
        result.base = base;
      }}
      onCancel={() => {
        result.cancelled = true;
      }}
      onError={() => {}}
    />,
  );
  return { ...view, result };
}

test('la sélection part sur la base par défaut, ⏎ la choisit', async () => {
  const { lastFrame, stdin, result } = screen();
  await tick();
  assert.match(lastFrame() ?? '', /❯ develop/);
  stdin.write(KEYS.enter);
  await tick();
  assert.equal(result.base, 'develop');
});

test('taper filtre : « 1.3 » ne laisse qu’une release, sélectionnée d’office', async () => {
  const { lastFrame, stdin, result } = screen();
  await tick();
  for (const char of '1.3') {
    stdin.write(char);
    await tick(10);
  }
  await tick();
  const frame = lastFrame() ?? '';
  assert.match(frame, /❯ release\/1\.3\.0/);
  assert.doesNotMatch(frame, /release\/1\.4\.0/);
  assert.match(frame, /✓ Base : release\/1\.3\.0/);
  stdin.write(KEYS.enter);
  await tick();
  assert.equal(result.base, 'release/1.3.0');
});

test('on peut chercher par rôle : « prod » trouve la production', () => {
  assert.deepEqual(filterBases(BASES, 'production').map((base) => base.branch), ['main']);
});

test('échap revient en arrière', async () => {
  const { stdin, result } = screen();
  await tick();
  stdin.write(KEYS.escape);
  await tick();
  assert.equal(result.cancelled, true);
});
