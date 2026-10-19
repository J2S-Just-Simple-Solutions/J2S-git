import { useState } from 'react';
import { Box, Text, useInput } from 'ink';
import type { AuditCommit, AuditDemo, AuditDoc, AuditFile, AuditTicket } from '../types.js';
import { KeyHints, Title } from '../components.js';
import { listHeight, useTerminalRows } from '../viewport.js';

interface Line {
  text: string;
  color?: string;
  bold?: boolean;
  dim?: boolean;
}

const STEPS: Record<string, string> = {
  rebase: 'au rebase de la démo sur sa base à jour',
  foreign: 'au rebase de la démo sur sa base à jour',
  fresh: 'à la reprise du ticket depuis sa branche',
  add: "à l'ajout de ses nouveaux commits",
};

const KINDS: Record<string, string> = {
  both_modified: 'modifié des deux côtés',
  both_added: 'ajouté des deux côtés',
  both_deleted: 'supprimé des deux côtés',
  added_by_us: "ajouté d'un seul côté",
  added_by_them: "ajouté d'un seul côté",
  deleted_by_us: "supprimé d'un côté, modifié de l'autre",
  deleted_by_them: "modifié d'un côté, supprimé de l'autre",
};

const RANK: Record<AuditTicket['status'], number> = {
  conflicts: 0,
  base_missing: 1,
  to_rebase: 2,
  up_to_date: 3,
  delivered: 3,
};

// Le commit en cause et, pour chaque fichier, ce qui l'a touché en face.
function conflictLines(lines: Line[], indent: string, commit: AuditCommit, files: AuditFile[]) {
  lines.push({
    text: `${indent}commit ${commit.sha.slice(0, 7)} « ${commit.subject} » par ${commit.author} <${commit.email}>, le ${commit.date}`,
  });
  for (const file of files) {
    lines.push({ text: `${indent}${file.path} (${KINDS[file.kind] ?? file.kind})` });
    if (file.other) {
      lines.push({
        text: `${indent}  en face : « ${file.other.subject} » par ${file.other.author} <${file.other.email}> (${file.other.origin})`,
        dim: true,
      });
    }
  }
}

function ownerText(ticket: AuditTicket): string {
  const demos = ticket.demos.length > 0 ? ` · démos : ${ticket.demos.join(', ')}` : '';
  return `(propriétaire : ${ticket.owner.author ?? '?'}${demos})`;
}

// Les tickets : le détail de ce qui coince, et des tickets des démos ; les
// autres tickets à rebaser sont comptés par propriétaire (il peut y en avoir
// des centaines).
function ticketLines(lines: Line[], tickets: AuditTicket[]) {
  lines.push({ text: `TICKETS (${tickets.length})`, bold: true });
  const sorted = [...tickets].sort((a, b) => RANK[a.status] - RANK[b.status]);
  const owners = new Map<string, number>();
  let others = 0;

  for (const ticket of sorted) {
    switch (ticket.status) {
      case 'conflicts':
        lines.push({
          text: `  ✖ ${ticket.ticket} — en retard de ${ticket.behind_base} commit(s) sur ${ticket.base}, son rebase coince`,
          color: 'red',
        });
        if (ticket.conflict) conflictLines(lines, '      ', ticket.conflict.commit, ticket.conflict.files);
        lines.push({ text: `      → ${ticket.command}   ${ownerText(ticket)}`, color: 'cyan' });
        break;
      case 'base_missing':
        lines.push({ text: `  ✖ ${ticket.ticket} — sa base ${ticket.base ?? '?'} n'existe plus`, color: 'red' });
        lines.push({ text: `      → ${ticket.command}   ${ownerText(ticket)}`, color: 'cyan' });
        break;
      case 'to_rebase':
        if (ticket.demos.length > 0) {
          lines.push({
            text: `  ↻ ${ticket.ticket} — en retard de ${ticket.behind_base} commit(s) sur ${ticket.base}, son rebase passe`,
            color: 'yellow',
          });
          lines.push({ text: `      → ${ticket.command}   ${ownerText(ticket)}`, color: 'cyan' });
        } else {
          others += 1;
          const owner = ticket.owner.author ?? '?';
          owners.set(owner, (owners.get(owner) ?? 0) + 1);
        }
        break;
    }
  }

  if (others > 0) {
    const byOwner = [...owners.entries()]
      .sort((a, b) => b[1] - a[1])
      .map(([owner, count]) => `${owner} (${count})`)
      .join(', ');
    lines.push({
      text: `  ↻ ${others} autre(s) ticket(s) en retard sur leur base, rebase sans conflit — par propriétaire : ${byOwner}`,
      color: 'yellow',
    });
  }
  const upToDate = tickets.filter((ticket) => ticket.status === 'up_to_date').length;
  const delivered = tickets.filter((ticket) => ticket.status === 'delivered').length;
  if (upToDate + delivered > 0) {
    lines.push({ text: `  ✔ ${upToDate} à jour sur leur base, ${delivered} déjà livré(s)`, color: 'green' });
  }
}

function demoLines(lines: Line[], demo: AuditDemo) {
  lines.push({ text: '' });
  lines.push({ text: `  ${demo.branch}  (base ${demo.base ?? '?'})`, bold: true });
  switch (demo.status) {
    case 'up_to_date':
      lines.push({ text: '    ✔ À jour, rien à faire.', color: 'green' });
      return;
    case 'blocked':
      lines.push({ text: `    ✖ ${demo.message ?? 'Bloquée.'}`, color: 'red' });
      return;
    case 'feasible':
      lines.push({ text: '    ✔ Mise à jour faisable sans conflit.', color: 'green' });
      break;
    case 'conflicts':
      break;
  }

  for (const conflict of demo.conflicts) {
    const ticket = conflict.ticket === '-' ? 'commits ajoutés à la main' : conflict.ticket;
    lines.push({ text: `    ✖ Conflit : ${ticket} (${STEPS[conflict.step] ?? conflict.step})`, color: 'red' });
    conflictLines(lines, '        ', conflict.commit, conflict.files);
    lines.push({ text: `        → résoudre dans la démo : ${conflict.commands.resolve}`, color: 'cyan' });
    lines.push({ text: `        → ou retirer : ${conflict.commands.drop}`, color: 'cyan' });
  }

  if (demo.actions.length > 0) {
    lines.push({ text: "    Dans l'ordre :" });
    for (const action of demo.actions) {
      lines.push({ text: `      ${action.command}`, color: 'cyan' });
      lines.push({ text: `        ${action.reason}`, dim: true });
    }
  }
  if (demo.held.length > 0) {
    lines.push({ text: `    ⚠ ${demo.held.join(', ')} : à simuler de nouveau une fois rebasé(s) chez eux.`, color: 'yellow' });
  }
}

// Le rapport, ligne par ligne : il peut être long, l'écran n'en montre qu'une
// fenêtre que l'on fait défiler.
export function reportLines(doc: AuditDoc): Line[] {
  const lines: Line[] = [];
  ticketLines(lines, doc.tickets);

  if (doc.scope !== 'tickets') {
    lines.push({ text: '' });
    lines.push({ text: `DÉMOS (${doc.demos.length})`, bold: true });
    if (doc.demos.length === 0) lines.push({ text: '  Aucune démo.' });
    for (const demo of doc.demos) demoLines(lines, demo);
    if (doc.summary.demos.skipped_legacy > 0) {
      lines.push({ text: `  ${doc.summary.demos.skipped_legacy} démo(s) à l'ancien format non vérifiée(s).`, dim: true });
    }
  }

  const t = doc.summary.tickets;
  const d = doc.summary.demos;
  lines.push({ text: '' });
  lines.push({
    text: `Bilan : tickets — ${t.up_to_date} à jour, ${t.to_rebase} à rebaser, ${t.conflicts} en conflit, ${t.base_missing} base disparue, ${t.delivered} livré(s)`,
    bold: true,
  });
  if (doc.scope !== 'tickets') {
    lines.push({
      text: `        démos — ${d.up_to_date} à jour, ${d.feasible} faisable(s), ${d.conflicts} en conflit, ${d.blocked} bloquée(s)`,
      bold: true,
    });
  }
  return lines;
}

interface Props {
  doc: AuditDoc;
  onBack: () => void;
  onRerun: () => void;
}

const RESERVED_ROWS = 8;

export function AuditScreen({ doc, onBack, onRerun }: Props) {
  const rows = useTerminalRows();
  const lines = reportLines(doc);
  const height = listHeight(rows, RESERVED_ROWS);
  const [top, setTop] = useState(0);
  const maxTop = Math.max(0, lines.length - height);

  useInput((input, key) => {
    if (key.escape || input === 'q' || key.leftArrow) return onBack();
    if (input === 'r') return onRerun();
    if (key.upArrow || (key.ctrl && input === 'p')) return setTop((value) => Math.max(0, value - 1));
    if (key.downArrow || (key.ctrl && input === 'n')) return setTop((value) => Math.min(maxTop, value + 1));
    if (key.pageUp) return setTop((value) => Math.max(0, value - height));
    if (key.pageDown || input === ' ') return setTop((value) => Math.min(maxTop, value + height));
  });

  const first = Math.min(top, maxTop);
  const shown = lines.slice(first, first + height);

  return (
    <Box flexDirection="column">
      <Title>État des lieux</Title>
      <Text dimColor>  Simulation : rien n'a été modifié.</Text>
      <Box marginTop={1} flexDirection="column">
        {first > 0 ? <Text dimColor>{`  ↑ ${first} ligne(s) de plus`}</Text> : null}
        {shown.map((line, index) => (
          <Text key={first + index} color={line.color} bold={line.bold} dimColor={line.dim} wrap="truncate-end">
            {line.text || ' '}
          </Text>
        ))}
        {first + height < lines.length ? <Text dimColor>{`  ↓ ${lines.length - first - height} ligne(s) de plus`}</Text> : null}
      </Box>
      <KeyHints hints={[['↑↓', 'défiler'], ['r', 'relancer'], ['esc', 'retour']]} />
    </Box>
  );
}
