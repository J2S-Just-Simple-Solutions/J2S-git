import type { JgitResult, JgitRunner } from '../src/jgit.js';
import type { AnyDoc, DemoSummary } from '../src/types.js';

// Exécuteur factice : chaque appel est noté, la réponse vient d'un
// gestionnaire qui reçoit les arguments (sans le « --json » ajouté par le vrai).
export class FakeRunner implements JgitRunner {
  calls: string[][] = [];
  constructor(private readonly handler: (args: string[]) => Partial<JgitResult> & { doc: AnyDoc | null }) {}

  async run(args: string[]): Promise<JgitResult> {
    this.calls.push(args);
    const response = this.handler(args);
    return { exitCode: response.exitCode ?? (response.doc && 'ok' in response.doc && response.doc.ok ? 0 : 2), doc: response.doc, stderr: response.stderr ?? '' };
  }

  called(prefix: string): boolean {
    return this.calls.some((call) => call.join(' ').startsWith(prefix));
  }
}

export function summary(overrides: Partial<DemoSummary> = {}): DemoSummary {
  return {
    name: 'sprint12',
    branch: 'demo/sprint12',
    format: 'v2',
    archived: false,
    archived_on: null,
    read_only: false,
    base: 'develop',
    base_exists: true,
    behind_base: 0,
    updated_at: '2026-10-12T09:14:03+02:00',
    updated_by: 'Yann',
    ticket_count: 2,
    tickets_needing_attention: 0,
    foreign_commit_count: 0,
    needs_rebase: false,
    operation_in_progress: false,
    ...overrides,
  };
}

export const noPause: AnyDoc = { schema: 'jgit.status/1', ok: true, current_branch: 'develop', operation_in_progress: null };

export const tick = (ms = 40) => new Promise((resolve) => setTimeout(resolve, ms));

export const KEYS = {
  enter: '\r',
  escape: '\u001B',
  down: '\u001B[B',
  up: '\u001B[A',
  space: ' ',
};
