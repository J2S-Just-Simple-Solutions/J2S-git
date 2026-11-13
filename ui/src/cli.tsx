#!/usr/bin/env node
import { render } from 'ink';
import { spawnSync, execFileSync } from 'node:child_process';
import { existsSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
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

// Dans le conteneur (jgit ui), Claude Code n'est pas installé : il tourne sur
// le poste. ui.sh donne alors un fichier de relais ; l'interface y écrit la
// demande et s'arrête, ui.sh lance claude sur le poste puis relance l'interface.
const claudeRelay = process.env.JGIT_UI_CLAUDE_RELAY;
const claudeLocal = commandExists('claude');

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
  process.stderr.write('Claude Code prend la main. Pour revenir à jgit ui : /exit (ou Ctrl+D deux fois).\n');
  spawnSync('claude', claudeArgs(request.prompt), { cwd, stdio: 'inherit' });
  return null;
}

// Le skill jgit-demo est livré avec jgit : si ni le projet ni ~/.claude ne
// l'installent, on le donne à Claude (même règle que jgit_ui_claude, ui.sh).
function claudeArgs(prompt: string): string[] {
  let skill: string;
  try {
    skill = join(dirname(realpathSync(jgit)), '.claude', 'skills', 'jgit-demo');
  } catch {
    return [prompt];
  }
  let top = cwd;
  try {
    top = execFileSync('git', ['rev-parse', '--show-toplevel'], { cwd, encoding: 'utf8' }).trim();
  } catch {
    // hors dépôt : le dossier courant
  }
  const installed = [join(homedir(), '.claude', 'skills', 'jgit-demo'), join(top, '.claude', 'skills', 'jgit-demo')];
  if (!existsSync(join(skill, 'SKILL.md')) || installed.some((path) => existsSync(path))) return [prompt];
  return ['--add-dir', skill, `${prompt} Le skill jgit-demo n'est pas installé dans ce projet : lis ${skill}/SKILL.md et suis-le.`];
}

// Vrai si la demande part au poste : l'interface doit alors s'arrêter.
function relayToHost(request: SpawnRequest): boolean {
  if (request.kind !== 'claude' || claudeLocal || !claudeRelay) return false;
  writeFileSync(claudeRelay, request.prompt);
  return true;
}

async function main(): Promise<void> {
  const claudeAvailable = claudeLocal || Boolean(claudeRelay);
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
    if (relayToHost(request)) break;
    flash = runSpawn(request);
  }
}

void main();
