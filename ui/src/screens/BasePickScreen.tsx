import { useEffect, useState } from 'react';
import { Box, Text, useInput } from 'ink';
import type { JgitRunner } from '../jgit.js';
import { failureText } from '../jgit.js';
import type { Base } from '../types.js';
import { KeyHints, Spinner, Title, pad } from '../components.js';
import { matches, rank } from '../filter.js';
import { listHeight, useTerminalRows, windowAround } from '../viewport.js';

interface Props {
  runner: JgitRunner;
  title: string;
  onDone: (base: string) => void;
  onCancel: () => void;
  onError: (text: string) => void;
}

const RESERVED_ROWS = 12;

const ROLES: Record<Base['role'], string> = {
  preprod: 'préprod',
  prod: 'production',
  release: 'release',
  other: '',
};

export function filterBases(bases: Base[], query: string): Base[] {
  return bases
    .filter((base) => matches(query, `${base.branch} ${ROLES[base.role]} ${base.last_subject}`))
    .map((base, index) => ({ base, index, score: rank(query, base.branch) }))
    .sort((a, b) => a.score - b.score || a.index - b.index)
    .map((entry) => entry.base);
}

// Choix de la base d'une nouvelle démo : la liste vient de « jgit demo bases »
// (préprod et production en tête), la sélection part sur la base par défaut,
// et la saisie filtre comme pour les tickets. Une seule base qui correspond
// est sélectionnée d'office ; ⏎ la choisit.
export function BasePickScreen({ runner, title, onDone, onCancel, onError }: Props) {
  const rows = useTerminalRows();
  const [bases, setBases] = useState<Base[] | null>(null);
  const [query, setQuery] = useState('');
  const [cursor, setCursor] = useState(0);

  useEffect(() => {
    runner.run(['demo', 'bases']).then((result) => {
      if (result.doc && result.doc.schema === 'jgit.demo.bases/1') {
        const doc = result.doc;
        setBases(doc.bases);
        setCursor(Math.max(0, doc.bases.findIndex((base) => base.branch === doc.default)));
      } else {
        onError(failureText(result));
        onCancel();
      }
    });
  }, []);

  const visible = bases ? filterBases(bases, query) : [];
  const position = Math.min(cursor, Math.max(0, visible.length - 1));
  const current = visible[position];

  const typed = (next: string) => {
    setQuery(next);
    setCursor(0);
  };

  useInput((input, key) => {
    if (!bases) return;
    if (key.upArrow || (key.ctrl && input === 'p')) return setCursor(Math.max(0, position - 1));
    if (key.downArrow || (key.ctrl && input === 'n')) return setCursor(Math.min(Math.max(0, visible.length - 1), position + 1));
    if (key.escape) {
      if (query !== '') return typed('');
      return onCancel();
    }
    if (key.return) {
      if (current) onDone(current.branch);
      return;
    }
    if (key.backspace || key.delete) {
      if (query !== '') typed(query.slice(0, -1));
      return;
    }
    if (input && !key.ctrl && !key.meta && /^[^\s]+$/.test(input)) typed(query + input);
  });

  if (!bases) return <Spinner label="Lecture des branches du serveur…" />;

  const { start, end } = windowAround(visible.length, position, listHeight(rows, RESERVED_ROWS));
  const single = query.trim() !== '' && visible.length === 1;

  return (
    <Box flexDirection="column">
      <Title>{title}</Title>
      <Text dimColor>  La démo partira de la version du serveur de cette branche.</Text>

      <Box marginTop={1}>
        <Text color="cyan">{'› '}</Text>
        <Text>{query}</Text>
        <Text inverse> </Text>
        {query === '' ? <Text dimColor>{'  tapez pour filtrer'}</Text> : null}
      </Box>

      <Box flexDirection="column">
        {visible.length === 0 ? (
          <Text dimColor>{'  Aucune branche ne correspond.'}</Text>
        ) : (
          <>
            {start > 0 ? <Text dimColor>{`  ↑ ${start} de plus`}</Text> : null}
            {visible.slice(start, end).map((base, offset) => {
              const selected = start + offset === position;
              const role = ROLES[base.role];
              return (
                <Text key={base.branch} inverse={selected} wrap="truncate-end">
                  {selected ? '❯ ' : '  '}
                  {pad(base.branch, 30)}
                  {role ? <Text color={selected ? undefined : 'cyan'}>{pad(role, 12)}</Text> : pad('', 12)}
                  {`${base.updated_at.slice(0, 10)}  ${base.last_subject}`}
                </Text>
              );
            })}
            {end < visible.length ? <Text dimColor>{`  ↓ ${visible.length - end} de plus`}</Text> : null}
          </>
        )}
      </Box>

      {current ? (
        <Text color={single ? 'green' : undefined}>{`\n${single ? '✓ ' : ''}Base : ${current.branch} — ⏎ pour la choisir`}</Text>
      ) : null}

      <KeyHints
        hints={[
          ['abc', 'filtrer'],
          ['↑↓', 'choisir'],
          ['⏎', 'valider'],
          ['esc', query !== '' ? 'effacer' : 'annuler'],
        ]}
      />
    </Box>
  );
}
