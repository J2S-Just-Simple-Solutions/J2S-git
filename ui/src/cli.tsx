#!/usr/bin/env node
import { render } from 'ink';
import { spawnSync, execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { App } from './app.js';
import type { SpawnRequest } from './app.js';
import type { Flash } from './components.js';
import { createRunner } from './jgit.js';

// Interface en terminal des démos jgit.
//
//   jgit-ui [--jgit <chemin de jgit>] [--cwd <dépôt>]
//
// Par défaut : « jgit » du PATH (ou $JGIT_BIN), dans le dossier courant.

function option(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

const jgit = option('--jgit') ?? process.env.JGIT_BIN ?? 'jgit';
const cwd = resolve(option('--cwd') ?? process.cwd());
const runner = createRunner(jgit, cwd);

function commandExists(command: string): boolean {
  return spawnSync('sh', ['-c', `command -v ${command}`], { stdio: 'ignore' }).status === 0;
}

const MARKERS = /^(<{7}|={7}|>{7})( |$)/m;

async function stage(file: string): Promise<void> {
  execFileSync('git', ['add', '--', file], { cwd, stdio: 'ignore' });
}

// Exécute ce que l'interface a demandé, terminal rendu. Renvoie le message à
// afficher au retour.
function runSpawn(request: SpawnRequest): Flash | null {
  if (request.kind === 'editor') {
    const editor = process.env.VISUAL || process.env.EDITOR || 'vi';
    spawnSync(editor, [request.file], { cwd, stdio: 'inherit', shell: true });
    let content = '';
    try {
      content = readFileSync(resolve(cwd, request.file), 'utf8');
    } catch {
      return null;
    }
    if (MARKERS.test(content)) {
      return { kind: 'info', text: `${request.file} contient encore des marqueurs de conflit : il n'est pas marqué résolu.` };
    }
    execFileSync('git', ['add', '--', request.file], { cwd, stdio: 'ignore' });
    return { kind: 'success', text: `${request.file} est marqué résolu.` };
  }
  spawnSync('claude', [request.prompt], { cwd, stdio: 'inherit' });
  return null;
}

async function main(): Promise<void> {
  const claudeAvailable = commandExists('claude');
  let flash: Flash | null = null;

  for (;;) {
    let request: SpawnRequest | null = null;
    const instance = render(
      <App
        runner={runner}
        claudeAvailable={claudeAvailable}
        stage={stage}
        initialFlash={flash}
        onSpawn={(next) => {
          request = next;
          instance.unmount();
        }}
      />,
    );
    await instance.waitUntilExit();
    if (!request) break;
    flash = runSpawn(request);
  }
}

void main();
