import { useState } from 'react';
import { Box, Text, useInput } from 'ink';
import type { AuditDemo, AuditDemoConflict, AuditDoc, AuditTicket } from '../types.js';
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

const RANK: Record<AuditTicket['status'], number> = {
  conflicts: 0,
  base_missing: 1,
  no_init: 1,
  to_rebase: 2,
  up_to_date: 3,
  delivered: 3,
};

function baseText(ticket: AuditTicket): string {
  const base = ticket.base ?? '?';
  return ticket.base_source === 'inferred' ? `${base} (base supposée)` : base;
}

// Qui doit intervenir : c'est ce que le rapport doit dire, le détail des
// fichiers et des commits reste dans le JSON.
function people(ticket: AuditTicket): string {
  const names = ticket.concerned.map((person) => person.author);
  return names.length > 0 ? names.join(', ') : '?';
}

function demosText(ticket: AuditTicket): string {
  return ticket.demos.length > 0 ? `   (démos : ${ticket.demos.join(', ')})` : '';
}

// « Yann (12), Camille (3) », sans tenir compte de la casse des noms.
function countByPerson(tickets: AuditTicket[]): string {
  const counts = new Map<string, { name: string; count: number }>();
  for (const ticket of tickets) {
    const names = ticket.concerned.length > 0 ? ticket.concerned.map((person) => person.author) : ['?'];
    for (const name of names) {
      const key = name.toLowerCase();
      const entry = counts.get(key) ?? { name, count: 0 };
      entry.count += 1;
      counts.set(key, entry);
    }
  }
  return [...counts.values()]
    .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name))
    .map((entry) => `${entry.name} (${entry.count})`)
    .join(', ');
}

// Ce qui se passe, puis sur leurs propres lignes (elles ne seront pas
// tronquées) le titre de la PR, qui doit intervenir et quoi lancer.
function ticketBlock(lines: Line[], ticket: AuditTicket, header: Line, command: string) {
  lines.push(header);
  if (ticket.pr_title) lines.push({ text: `      « ${ticket.pr_title} »`, dim: true });
  lines.push({ text: `      à faire par : ${people(ticket)}` });
  lines.push({ text: `      → ${command}${demosText(ticket)}`, color: 'cyan' });
}

function groupLines(lines: Line[], header: Line, tickets: AuditTicket[]) {
  if (tickets.length === 0) return;
  lines.push(header);
  lines.push({ text: `      à faire par : ${countByPerson(tickets)}` });
}

// Les tickets : pour ce qui demande une action, qui doit intervenir et quoi
// lancer ; les tickets hors démo simplement à rebaser (ou sans commit d'init)
// sont comptés par personne — il peut y en avoir des centaines.
function ticketLines(lines: Line[], tickets: AuditTicket[]) {
  lines.push({ text: `TICKETS (${tickets.length})`, bold: true });
  const sorted = [...tickets].sort((a, b) => RANK[a.status] - RANK[b.status]);
  const noInit = sorted.filter((ticket) => ticket.status === 'no_init' && ticket.demos.length === 0);
  const others = sorted.filter((ticket) => ticket.status === 'to_rebase' && ticket.demos.length === 0);
  let noInitShown = false;
  const showNoInit = () => {
    if (noInitShown) return;
    noInitShown = true;
    groupLines(
      lines,
      { text: `  ✖ ${noInit.length} autre(s) ticket(s) en retard, sans commit d'init : à rebaser à la main`, color: 'red' },
      noInit,
    );
  };

  for (const ticket of sorted) {
    if (RANK[ticket.status] >= 2) showNoInit();
    switch (ticket.status) {
      case 'conflicts':
        ticketBlock(lines, ticket, {
          text: `  ✖ ${ticket.ticket} — en retard de ${ticket.behind_base} commit(s) sur ${baseText(ticket)} : son rebase coince`,
          color: 'red',
        }, ticket.command ?? '');
        break;
      case 'base_missing':
        ticketBlock(lines, ticket, { text: `  ✖ ${ticket.ticket} — sa base ${ticket.base ?? '?'} n'existe plus`, color: 'red' }, ticket.command ?? '');
        break;
      case 'no_init':
        if (ticket.demos.length === 0) break;
        ticketBlock(lines, ticket, {
          text: `  ✖ ${ticket.ticket} — en retard sur ${baseText(ticket)}, sans commit d'init : jgit ne sait pas quels commits sont les siens`,
          color: 'red',
        }, 'à rebaser à la main');
        break;
      case 'to_rebase':
        if (ticket.demos.length === 0) break;
        ticketBlock(lines, ticket, {
          text: `  ↻ ${ticket.ticket} — en retard de ${ticket.behind_base} commit(s) sur ${baseText(ticket)}, son rebase passe`,
          color: 'yellow',
        }, ticket.command ?? '');
        break;
    }
  }
  showNoInit();

  groupLines(
    lines,
    { text: `  ↻ ${others.length} autre(s) ticket(s) en retard sur leur base, rebase sans conflit`, color: 'yellow' },
    others,
  );
  const upToDate = tickets.filter((ticket) => ticket.status === 'up_to_date').length;
  const delivered = tickets.filter((ticket) => ticket.status === 'delivered').length;
  if (upToDate + delivered > 0) {
    lines.push({ text: `  ✔ ${upToDate} à jour sur leur base, ${delivered} déjà livré(s)`, color: 'green' });
  }
}

// Qui est concerné par un conflit dans la démo : l'auteur du commit qui ne
// passe pas, et en face ceux qui ont touché les mêmes fichiers.
function conflictPeople(conflict: AuditDemoConflict): string {
  const seen = new Set<string>();
  const parts: string[] = [];
  const add = (who: string, from: string) => {
    const key = `${who}|${from}`;
    if (!who || seen.has(key)) return;
    seen.add(key);
    parts.push(`${who} (${from})`);
  };
  add(conflict.commit.author, conflict.ticket === '-' ? 'commit ajouté à la main' : conflict.ticket);
  for (const file of conflict.files) if (file.other) add(file.other.author, file.other.origin);
  return parts.length > 0 ? parts.join(', ') : '?';
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
    const name = conflict.ticket === '-' ? 'commits ajoutés à la main' : conflict.ticket;
    lines.push({ text: `    ✖ Conflit : ${name} (${STEPS[conflict.step] ?? conflict.step})`, color: 'red' });
    lines.push({ text: `        concerne : ${conflictPeople(conflict)}` });
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
    text: `Bilan : tickets — ${t.up_to_date} à jour, ${t.to_rebase} à rebaser, ${t.conflicts} en conflit, ${t.base_missing} base disparue, ${t.no_init} sans commit d'init, ${t.delivered} livré(s)`,
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
