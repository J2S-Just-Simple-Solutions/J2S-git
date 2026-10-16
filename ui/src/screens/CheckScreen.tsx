import { useState } from 'react';
import { Box, Text, useInput } from 'ink';
import type { CheckDoc, CheckedDemo } from '../types.js';
import { KeyHints, Title } from '../components.js';
import { listHeight, useTerminalRows } from '../viewport.js';

interface Line {
  text: string;
  color?: string;
  bold?: boolean;
  dim?: boolean;
}

const STEPS: Record<string, string> = {
  rebase: 'au rebase sur la base à jour',
  foreign: 'au rebase sur la base à jour',
  refresh: 'à la reprise du ticket',
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

// Le rapport, ligne par ligne : il peut être long, l'écran n'en montre qu'une
// fenêtre que l'on fait défiler.
export function reportLines(doc: CheckDoc): Line[] {
  const lines: Line[] = [];
  doc.demos.forEach((demo: CheckedDemo, index) => {
    if (index > 0) lines.push({ text: '' });
    lines.push({ text: `${demo.branch}  (base ${demo.base ?? '?'})`, bold: true });
    switch (demo.status) {
      case 'up_to_date':
        lines.push({ text: '  ✔ À jour, rien à faire.', color: 'green' });
        break;
      case 'blocked':
        lines.push({ text: `  ✖ ${demo.message ?? 'Bloquée.'}`, color: 'red' });
        break;
      case 'feasible':
        lines.push({ text: '  ✔ Mise à jour faisable sans conflit :', color: 'green' });
        break;
      case 'conflicts':
        lines.push({ text: `  ✖ ${demo.conflicts.length} conflit(s) à résoudre`, color: 'red' });
        break;
    }

    for (const conflict of demo.conflicts) {
      const ticket = conflict.ticket === '-' ? 'commits ajoutés à la main' : conflict.ticket;
      lines.push({ text: `    ${ticket} — ${STEPS[conflict.step] ?? conflict.step}`, color: 'red' });
      lines.push({
        text: `      commit ${conflict.commit.sha.slice(0, 7)} « ${conflict.commit.subject} » par ${conflict.commit.author} <${conflict.commit.email}>, le ${conflict.commit.date}`,
      });
      for (const file of conflict.files) {
        lines.push({ text: `      ${file.path} (${KINDS[file.kind] ?? file.kind})` });
        if (file.other) {
          lines.push({
            text: `        en face : « ${file.other.subject} » par ${file.other.author} <${file.other.email}> (${file.other.origin})`,
            dim: true,
          });
        }
      }
      lines.push({ text: `      → résoudre : ${conflict.commands.resolve}`, color: 'cyan' });
      lines.push({ text: `      → ou retirer : ${conflict.commands.drop}`, color: 'cyan' });
    }

    if (demo.actions.length > 0) {
      if (demo.status === 'conflicts') lines.push({ text: "    Pour la remettre à jour, dans l'ordre :" });
      for (const action of demo.actions) {
        lines.push({ text: `    ${action.command}`, color: 'cyan' });
        lines.push({ text: `      ${action.reason}`, dim: true });
      }
    }
  });

  const s = doc.summary;
  lines.push({ text: '' });
  lines.push({
    text: `Bilan : ${s.demos} démo(s) — ${s.up_to_date} à jour, ${s.feasible} faisable(s), ${s.conflicts} en conflit, ${s.blocked} bloquée(s).`,
    bold: true,
  });
  if (s.skipped_legacy > 0) {
    lines.push({ text: `${s.skipped_legacy} démo(s) à l'ancien format non vérifiée(s).`, dim: true });
  }
  return lines;
}

interface Props {
  doc: CheckDoc;
  onBack: () => void;
  onRerun: () => void;
}

const RESERVED_ROWS = 8;

export function CheckScreen({ doc, onBack, onRerun }: Props) {
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
      <Title>Vérification des mises à jour</Title>
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
