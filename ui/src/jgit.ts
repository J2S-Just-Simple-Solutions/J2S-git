import { execFile } from 'node:child_process';
import type { AnyDoc, ConflictDoc, PausedOperation } from './types.js';

// L'interface ne fait AUCUNE opération git elle-même : tout passe par
// « jgit … --json », dont elle lit le document unique (docs/06-contrat-cli.md).

export interface JgitResult {
  exitCode: number;
  doc: AnyDoc | null;
  stderr: string;
}

export interface JgitRunner {
  run(args: string[]): Promise<JgitResult>;
}

export function createRunner(jgitPath: string, cwd: string): JgitRunner {
  return {
    run(args: string[]): Promise<JgitResult> {
      return new Promise((resolve) => {
        execFile(
          jgitPath,
          [...args, '--json'],
          { cwd, maxBuffer: 32 * 1024 * 1024, env: { ...process.env, JGIT_COLOR: 'never' } },
          (error, stdout, stderr) => {
            const exitCode = error ? (typeof error.code === 'number' ? error.code : 1) : 0;
            let doc: AnyDoc | null = null;
            const line = stdout.trim().split('\n').pop();
            if (line) {
              try {
                doc = JSON.parse(line) as AnyDoc;
              } catch {
                doc = null;
              }
            }
            resolve({ exitCode, doc, stderr: String(stderr) });
          },
        );
      });
    },
  };
}

// Message lisible d'un résultat en échec.
export function failureText(result: JgitResult): string {
  const doc = result.doc;
  if (doc && 'error' in doc && doc.error) {
    return doc.error.hint ? `${doc.error.message}\n${doc.error.hint}` : doc.error.message;
  }
  const lines = result.stderr.trim().split('\n').filter(Boolean);
  return lines.slice(-3).join('\n') || `jgit a échoué (code ${result.exitCode}).`;
}

// Vue commune d'un conflit, qu'il vienne d'une commande (jgit.conflict/1) ou
// de « jgit util status » (opération déjà en pause).
export interface ConflictView {
  label: string;
  target: string;
  ticket: string | null;
  commitSubject: string | null;
  files: { path: string; kind: string }[];
  continueArgs: string[];
  abortArgs: string[];
}

function commandArgs(command: string): string[] {
  return command.replace(/^jgit\s+/, '').split(/\s+/).filter(Boolean);
}

export function conflictFromDoc(doc: ConflictDoc): ConflictView {
  return {
    label: doc.error.message,
    target: doc.target,
    ticket: doc.context?.ticket ?? null,
    commitSubject: doc.commit.subject,
    files: doc.conflicted_files,
    continueArgs: commandArgs(doc.commands?.continue ?? ''),
    abortArgs: commandArgs(doc.commands?.abort ?? ''),
  };
}

export function conflictFromStatus(op: PausedOperation): ConflictView {
  return {
    label: `Une opération attend la résolution d'un conflit : ${op.label}.`,
    target: op.target,
    ticket: op.context?.ticket ?? null,
    commitSubject: op.commit.subject,
    files: op.conflicted_files,
    continueArgs: commandArgs(op.commands.continue),
    abortArgs: commandArgs(op.commands.abort),
  };
}
