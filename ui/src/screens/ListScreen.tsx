import { useEffect, useState } from 'react';
import { Box, Text, useInput } from 'ink';
import type { JgitRunner } from '../jgit.js';
import { failureText } from '../jgit.js';
import type { DemoListDoc, DemoSummary } from '../types.js';
import { KeyHints, Spinner, Title, pad } from '../components.js';
import { listHeight, useTerminalRows, windowAround } from '../viewport.js';

// Lignes fixes de l'écran, hors liste.
const RESERVED_ROWS = 11;

interface Props {
  runner: JgitRunner;
  onOpen: (demo: DemoSummary) => void;
  onCreate: () => void;
  onCheck: () => void;
  onQuit: () => void;
  onError: (text: string) => void;
}

function stateOf(demo: DemoSummary): { text: string; color: string } {
  if (demo.archived) return { text: `archivée le ${demo.archived_on}`, color: 'gray' };
  if (demo.format === 'legacy') return { text: '⚠ ancien format : à convertir (m)', color: 'yellow' };
  if (demo.operation_in_progress) return { text: '⏸ conflit en attente', color: 'red' };
  if (!demo.base_exists) return { text: `✖ sa base ${demo.base ?? '?'} n'existe plus`, color: 'red' };
  const parts: string[] = [];
  if (demo.needs_rebase) parts.push(`en retard de ${demo.behind_base} commit(s)`);
  if (demo.tickets_needing_attention > 0) parts.push(`${demo.tickets_needing_attention} ticket(s) à reprendre`);
  if (demo.foreign_commit_count > 0) parts.push(`${demo.foreign_commit_count} commit(s) ajouté(s) à la main`);
  if (parts.length === 0) return { text: '✔ à jour', color: 'green' };
  return { text: `⚠ ${parts.join(' · ')}`, color: 'yellow' };
}

export function ListScreen({ runner, onOpen, onCreate, onCheck, onQuit, onError }: Props) {
  const rows = useTerminalRows();
  const [scope, setScope] = useState<'active' | 'all'>('active');
  const [doc, setDoc] = useState<DemoListDoc | null>(null);
  const [loading, setLoading] = useState(true);
  const [cursor, setCursor] = useState(0);
  const [reload, setReload] = useState(0);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    const args = ['demo', 'list'];
    if (scope === 'all') args.push('--all');
    if (reload === 0 && scope === 'active') args.push('--no-fetch');
    runner.run(args).then((result) => {
      if (cancelled) return;
      setLoading(false);
      if (result.doc && result.doc.schema === 'jgit.demo.list/1') {
        const list = result.doc;
        setDoc(list);
        setCursor((value) => Math.min(value, Math.max(0, list.demos.length - 1)));
      } else {
        onError(failureText(result));
      }
    });
    return () => {
      cancelled = true;
    };
  }, [scope, reload]);

  const demos = doc?.demos ?? [];
  const range = windowAround(demos.length, cursor, listHeight(rows, RESERVED_ROWS));

  useInput((input, key) => {
    if (loading) return;
    if (key.upArrow || (key.ctrl && input === 'p')) setCursor((value) => Math.max(0, value - 1));
    else if (key.downArrow || (key.ctrl && input === 'n')) setCursor((value) => Math.min(demos.length - 1, value + 1));
    else if (key.return && demos[cursor]) onOpen(demos[cursor]);
    else if (input === 'n') onCreate();
    else if (input === 'v' && demos.length > 0) onCheck();
    else if (input === 'a') setScope((value) => (value === 'active' ? 'all' : 'active'));
    else if (input === 'r') setReload((value) => value + 1);
    else if (input === 'q' || key.escape) onQuit();
  });

  return (
    <Box flexDirection="column">
      <Title>{scope === 'all' ? 'Toutes les démos' : 'Démos du projet'}</Title>
      <Box marginTop={1} flexDirection="column">
        {loading && !doc ? (
          <Spinner label="Lecture des démos sur le serveur…" />
        ) : demos.length === 0 ? (
          <Text>Aucune démo. Appuyez sur n pour en créer une.</Text>
        ) : (
          <>
            <Text dimColor>{`  ${pad('NOM', 24)}${pad('BASE', 12)}${pad('TICKETS', 10)}ÉTAT`}</Text>
            {range.start > 0 ? <Text dimColor>{`  ↑ ${range.start} de plus`}</Text> : null}
            {demos.slice(range.start, range.end).map((demo, offset) => {
              const index = range.start + offset;
              const state = stateOf(demo);
              const selected = index === cursor;
              return (
                <Text key={demo.branch} inverse={selected} wrap="truncate-end">
                  {selected ? '❯ ' : '  '}
                  {pad(demo.name, 24)}
                  {pad(demo.base ?? '-', 12)}
                  {pad(String(demo.ticket_count), 10)}
                  <Text color={selected ? undefined : state.color}>{state.text}</Text>
                </Text>
              );
            })}
            {range.end < demos.length ? <Text dimColor>{`  ↓ ${demos.length - range.end} de plus`}</Text> : null}
          </>
        )}
        {loading && doc ? <Spinner label="Mise à jour…" /> : null}
        {scope === 'active' && doc && doc.archived_count > 0 ? (
          <Text dimColor>{`${doc.archived_count} démo(s) archivée(s) : a pour les voir`}</Text>
        ) : null}
      </Box>
      <KeyHints
        hints={[
          ['↑↓', 'choisir'],
          ['⏎', 'ouvrir'],
          ['n', 'nouvelle démo'],
          ['v', 'vérifier les mises à jour'],
          ['a', scope === 'active' ? 'archives' : 'actives seulement'],
          ['r', 'actualiser'],
          ['q', 'quitter'],
        ]}
      />
    </Box>
  );
}
