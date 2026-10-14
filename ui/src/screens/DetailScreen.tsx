import { useEffect, useState } from 'react';
import { Box, Text, useInput } from 'ink';
import type { JgitRunner } from '../jgit.js';
import { failureText } from '../jgit.js';
import type { DemoShowDoc } from '../types.js';
import { KeyHints, Spinner, Title, pad, ticketState } from '../components.js';
import { listHeight, useTerminalSize, windowAround, wrappedRows } from '../viewport.js';

// Lignes fixes de l'écran, hors tickets et hors commande de release : en-tête,
// base, mise à jour, titres, aide (sur deux lignes), message.
const RESERVED_ROWS = 15;
const MAX_FOREIGN_SHOWN = 3;

// Ce que l'écran de détail demande à l'application : une commande jgit à
// préparer (avec --dry-run si elle réécrit la démo) ou un autre écran.
export type DetailAction =
  | { kind: 'mutate'; args: string[]; title: string; preview: boolean }
  | { kind: 'pick'; demo: string; base: string | null }
  | { kind: 'back' };

interface Props {
  runner: JgitRunner;
  branch: string;
  reloadKey: number;
  onAction: (action: DetailAction) => void;
  onError: (text: string) => void;
}

export function DetailScreen({ runner, branch, reloadKey, onAction, onError }: Props) {
  const { rows, columns } = useTerminalSize();
  const [doc, setDoc] = useState<DemoShowDoc | null>(null);
  const [cursor, setCursor] = useState(0);
  const [marked, setMarked] = useState<Set<string>>(new Set());

  useEffect(() => {
    let cancelled = false;
    setDoc(null);
    runner.run(['demo', 'show', branch]).then((result) => {
      if (cancelled) return;
      if (result.doc && result.doc.schema === 'jgit.demo.show/1') {
        setDoc(result.doc);
        setMarked(new Set());
      } else {
        onError(failureText(result));
        onAction({ kind: 'back' });
      }
    });
    return () => {
      cancelled = true;
    };
  }, [branch, reloadKey]);

  const tickets = doc?.tickets ?? [];
  const demo = doc?.demo;
  const name = demo?.name ?? branch;
  const writable = demo ? !demo.read_only : false;

  useInput((input, key) => {
    if (!doc || !demo) return;
    const current = tickets[cursor];
    if (key.escape || key.leftArrow || input === 'q') return onAction({ kind: 'back' });
    if (key.upArrow || (key.ctrl && input === 'p')) return setCursor((value) => Math.max(0, value - 1));
    if (key.downArrow || (key.ctrl && input === 'n')) return setCursor((value) => Math.min(tickets.length - 1, value + 1));

    if (demo.archived) {
      if (input === 'u') {
        onAction({ kind: 'mutate', args: ['demo', 'unarchive', demo.branch], title: `Restaurer ${demo.branch}`, preview: false });
      }
      return;
    }
    if (demo.format === 'legacy') {
      if (input === 'm') {
        onAction({ kind: 'mutate', args: ['demo', 'migrate', demo.name], title: `Convertir ${demo.branch} au format actuel`, preview: true });
      }
      return;
    }
    if (!writable) return;

    if (input === ' ' && current) {
      const next = new Set(marked);
      if (next.has(current.ticket)) next.delete(current.ticket);
      else next.add(current.ticket);
      setMarked(next);
      return;
    }
    if (input === 'a') return onAction({ kind: 'pick', demo: name, base: demo.base });
    if (input === 'd') {
      const targets = marked.size > 0 ? [...marked] : current ? [current.ticket] : [];
      if (targets.length === 0) return;
      return onAction({
        kind: 'mutate',
        args: ['demo', 'drop', name, ...targets.flatMap((ticket) => ['--from', ticket])],
        title: `Retirer ${targets.join(', ')} de la démo ${name}`,
        preview: true,
      });
    }
    if (input === 'u' && current) {
      if (current.suggested_action === 'add') {
        return onAction({ kind: 'mutate', args: ['demo', 'add', name, '--from', current.ticket], title: `Ajouter les nouveaux commits de ${current.ticket}`, preview: false });
      }
      if (current.suggested_action === 'refresh') {
        return onAction({ kind: 'mutate', args: ['demo', 'refresh', name, '--from', current.ticket], title: `Reprendre ${current.ticket} en entier`, preview: true });
      }
      if (current.suggested_action === 'drop') {
        return onAction({ kind: 'mutate', args: ['demo', 'drop', name, '--from', current.ticket], title: `Retirer ${current.ticket}`, preview: true });
      }
      return;
    }
    if (input === 'b') {
      return onAction({ kind: 'mutate', args: ['demo', 'rebase', name], title: `Remettre la démo ${name} à jour sur ${demo.base}`, preview: true });
    }
    if (input === 'x') {
      return onAction({ kind: 'mutate', args: ['demo', 'archive', name], title: `Archiver la démo ${name}`, preview: true });
    }
  });

  if (!doc || !demo) {
    return <Spinner label={`Lecture de ${branch}…`} />;
  }

  const foreignRows = doc.foreign_commits.length > 0 ? Math.min(doc.foreign_commits.length, MAX_FOREIGN_SHOWN + 1) + 2 : 0;
  const releaseRows = doc.release_command ? wrappedRows(`  ${doc.release_command}`, columns) + 2 : 0;
  const range = windowAround(tickets.length, cursor, listHeight(rows, RESERVED_ROWS + foreignRows + releaseRows));

  const hints: [string, string][] = [['↑↓', 'choisir']];
  if (demo.archived) hints.push(['u', 'restaurer']);
  else if (demo.format === 'legacy') hints.push(['m', 'convertir']);
  else
    hints.push(
      ['espace', 'cocher'],
      ['a', 'ajouter des tickets'],
      ['d', 'retirer'],
      ['u', 'appliquer la suggestion'],
      ['b', 'rebaser'],
      ['x', 'archiver'],
    );
  hints.push(['esc', 'retour']);

  return (
    <Box flexDirection="column">
      <Title>
        Démo {demo.name} <Text dimColor>({demo.branch})</Text>
      </Title>
      <Text>
        {'  Base        '}
        {demo.base ?? '?'}
        {' — '}
        {!demo.base_exists ? (
          <Text color="red">n'existe plus</Text>
        ) : demo.needs_rebase ? (
          <Text color="yellow">en retard de {demo.behind_base} commit(s) : b pour rebaser</Text>
        ) : (
          <Text color="green">à jour</Text>
        )}
      </Text>
      {demo.updated_at ? <Text dimColor>{`  Mise à jour ${demo.updated_at.replace('T', ' ').slice(0, 16)} par ${demo.updated_by}`}</Text> : null}
      {demo.read_only ? <Text color="yellow">  Lecture seule{demo.archived ? ` (archivée le ${demo.archived_on})` : ' (ancien format)'}</Text> : null}

      <Box marginTop={1} flexDirection="column">
        <Title>Tickets</Title>
        {tickets.length === 0 ? <Text>  Aucun ticket : a pour en ajouter.</Text> : null}
        {range.start > 0 ? <Text dimColor>{`  ↑ ${range.start} de plus`}</Text> : null}
        {tickets.slice(range.start, range.end).map((ticket, offset) => {
          const index = range.start + offset;
          const state = ticketState(ticket, demo.base);
          const selected = index === cursor;
          const check = marked.has(ticket.ticket) ? '[x]' : '[ ]';
          return (
            <Text key={ticket.ticket} inverse={selected} wrap="truncate-end">
              {selected ? '❯ ' : '  '}
              {writable ? `${check} ` : ''}
              {pad(ticket.ticket, 30)}
              <Text color={selected ? undefined : state.color}>{state.text}</Text>
              {ticket.suggested_action !== 'none' && writable ? <Text dimColor>{'  (u)'}</Text> : null}
            </Text>
          );
        })}
        {range.end < tickets.length ? <Text dimColor>{`  ↓ ${tickets.length - range.end} de plus`}</Text> : null}
      </Box>

      {doc.foreign_commits.length > 0 ? (
        <Box marginTop={1} flexDirection="column">
          <Text color="yellow">Commits ajoutés à la main (gardés par les reconstructions)</Text>
          {doc.foreign_commits.slice(0, MAX_FOREIGN_SHOWN).map((commit) => (
            <Text key={commit.sha} dimColor wrap="truncate-end">{`  ${commit.sha.slice(0, 7)} ${commit.subject} (${commit.author})`}</Text>
          ))}
          {doc.foreign_commits.length > MAX_FOREIGN_SHOWN ? (
            <Text dimColor>{`  … et ${doc.foreign_commits.length - MAX_FOREIGN_SHOWN} autre(s)`}</Text>
          ) : null}
        </Box>
      ) : null}

      {doc.release_command ? (
        <Box marginTop={1} flexDirection="column">
          <Text dimColor>Pour livrer ces tickets (une fois leurs PR validées) :</Text>
          <Text dimColor>{`  ${doc.release_command}`}</Text>
        </Box>
      ) : null}

      <KeyHints hints={hints} />
    </Box>
  );
}
