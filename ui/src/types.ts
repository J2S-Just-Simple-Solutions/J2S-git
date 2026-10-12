// Documents produits par « jgit … --json ». Le contrat complet est dans
// docs/06-contrat-cli.md ; seuls les champs lus par l'interface sont typés.

export interface JgitError {
  code: string;
  exit_code: number;
  message: string;
  hint: string | null;
}

export interface DemoSummary {
  name: string;
  branch: string;
  format: 'v2' | 'legacy';
  archived: boolean;
  archived_on: string | null;
  read_only: boolean;
  base: string | null;
  base_exists: boolean;
  behind_base: number | null;
  updated_at: string | null;
  updated_by: string | null;
  ticket_count: number;
  tickets_needing_attention: number;
  foreign_commit_count: number;
  needs_rebase: boolean;
  operation_in_progress: boolean;
}

export interface DemoListDoc {
  schema: 'jgit.demo.list/1';
  ok: true;
  demos: DemoSummary[];
  archived_count: number;
}

export type TicketStatus = 'up_to_date' | 'ahead' | 'diverged' | 'missing' | 'unknown';
export type SuggestedAction = 'none' | 'add' | 'refresh' | 'drop';

export interface DemoTicket {
  ticket: string;
  type: string;
  id: string;
  position: number;
  status: TicketStatus;
  delivered: boolean;
  delivered_with_pending_work: boolean;
  commits_not_in_demo: number | null;
  suggested_action: SuggestedAction;
}

export interface DemoShowDoc {
  schema: 'jgit.demo.show/1';
  ok: true;
  demo: DemoSummary;
  tickets: DemoTicket[];
  foreign_commits: { sha: string; subject: string; author: string }[];
  release_command: string | null;
}

export interface Candidate {
  ticket: string;
  updated_at: string;
  last_subject: string;
  author: string;
  delivered: boolean;
}

export interface CandidatesDoc {
  schema: 'jgit.demo.candidates/1';
  ok: true;
  demo: string | null;
  base: string | null;
  candidates: Candidate[];
}

export interface DemoResultDoc {
  schema: 'jgit.demo.result/1';
  ok: true;
  operation: string;
  demo: string;
  branch: string | null;
  changed: boolean;
  pushed: boolean;
  dry_run: boolean;
  added?: string[];
  updated?: string[];
  dropped?: { ticket: string; reason: string }[];
  warnings?: { code: string; ticket: string | null }[];
}

export interface ConflictFile {
  path: string;
  kind: string;
}

export interface ConflictDoc {
  schema: 'jgit.conflict/1';
  ok: false;
  operation: string;
  target: string;
  paused: boolean;
  error: JgitError;
  branch: string | null;
  commit: { sha: string | null; subject: string | null };
  conflicted_files: ConflictFile[];
  progress: { done: number | null; total: number | null };
  commands: { continue: string; abort: string } | null;
  context?: { demo?: string; ticket?: string | null };
}

export interface PausedOperation {
  operation: string;
  target: string;
  label: string;
  branch: string;
  commit: { sha: string | null; subject: string | null };
  conflicted_files: ConflictFile[];
  commands: { continue: string; abort: string };
  context?: { demo?: string; ticket?: string | null };
}

export interface StatusDoc {
  schema: 'jgit.status/1';
  ok: true;
  current_branch: string | null;
  operation_in_progress: PausedOperation | null;
}

export interface ErrorDoc {
  schema: 'jgit.error/1';
  ok: false;
  error: JgitError;
}

export type AnyDoc =
  | DemoListDoc
  | DemoShowDoc
  | CandidatesDoc
  | DemoResultDoc
  | ConflictDoc
  | StatusDoc
  | ErrorDoc;
