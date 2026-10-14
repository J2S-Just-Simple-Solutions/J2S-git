import { useEffect, useState } from 'react';
import { Box, Text, useInput } from 'ink';
import type { JgitRunner } from '../jgit.js';
import { failureText } from '../jgit.js';
import type { Candidate } from '../types.js';
import { KeyHints, Spinner, Title, pad } from '../components.js';
import { matches, rank } from '../filter.js';
import { listHeight, useTerminalRows, windowAround } from '../viewport.js';

interface Props {
  runner: JgitRunner;
  // Démo existante (ajout), ou null (création : tous les tickets du serveur).
  demo: string | null;
  title: string;
  allowEmpty: boolean;
  onDone: (tickets: string[]) => void;
  onCancel: () => void;
  onError: (text: string) => void;
}

// Lignes fixes de l'écran, hors liste : en-tête, titre, base, saisie, tickets
// choisis, aide, message.
const RESERVED_ROWS = 14;

function searchText(candidate: Candidate): string {
  return `${candidate.ticket} ${candidate.last_subject}`;
}

// Tickets visibles pour une saisie donnée, les plus pertinents d'abord ; à
// pertinence égale, l'ordre du serveur (les plus récents d'abord).
export function filterCandidates(candidates: Candidate[], query: string, showDelivered: boolean): Candidate[] {
  return candidates
    .filter((candidate) => (showDelivered || !candidate.delivered) && matches(query, searchText(candidate)))
    .map((candidate, index) => ({ candidate, index, score: rank(query, candidate.ticket) }))
    .sort((a, b) => a.score - b.score || a.index - b.index)
    .map((entry) => entry.candidate);
}

// Choix des tickets d'une démo, à la manière d'un champ d'étiquettes :
//
//   - on tape, la liste se réduit ;
//   - quand un seul ticket (pas encore choisi) correspond, il est coché tout
//     seul, et le reste tant que la saisie le désigne ; ⏎ le confirme et vide
//     la saisie pour le suivant. Il n'est jamais ajouté sans ⏎ : en tapant
//     « 1234 », « 123 » peut déjà être unique, et le « 4 » repartirait sur un
//     autre ticket ;
//   - ↑↓ déplacent la sélection, espace ajoute ou retire le ticket sélectionné,
//     ⏎ ajoute le ticket sélectionné — ou, saisie vide, valide le choix ;
//   - ⌫ sur une saisie vide retire le dernier ticket choisi ;
//   - échap vide la saisie, puis annule ;
//   - tab montre ou masque les tickets déjà livrés.
//
// L'ordre de choix est l'ordre des tickets dans la démo.
export function PickTicketsScreen({ runner, demo, title, allowEmpty, onDone, onCancel, onError }: Props) {
  const rows = useTerminalRows();
  const [candidates, setCandidates] = useState<Candidate[] | null>(null);
  const [base, setBase] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [cursor, setCursor] = useState(0);
  const [chosen, setChosen] = useState<string[]>([]);
  const [showDelivered, setShowDelivered] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    const args = ['demo', 'candidates'];
    if (demo) args.push(demo);
    runner.run(args).then((result) => {
      if (result.doc && result.doc.schema === 'jgit.demo.candidates/1') {
        setCandidates(result.doc.candidates);
        setBase(result.doc.base);
      } else {
        onError(failureText(result));
        onCancel();
      }
    });
  }, [demo]);

  const visible = candidates ? filterCandidates(candidates, query, showDelivered) : [];
  // Un seul ticket libre correspond à la saisie : il est coché d'office.
  const free = visible.filter((candidate) => !chosen.includes(candidate.ticket));
  const pending = query.trim() !== '' && free.length === 1 ? free[0].ticket : null;
  const current = pending
    ? visible.find((candidate) => candidate.ticket === pending)
    : visible[Math.min(cursor, visible.length - 1)];

  const add = (ticket: string) => {
    setChosen((list) => (list.includes(ticket) ? list : [...list, ticket]));
    setNotice(`${ticket} ajouté.`);
  };

  const typed = (next: string) => {
    setQuery(next);
    setNotice(null);
    setCursor(0);
  };

  useInput((input, key) => {
    if (!candidates) return;

    if (key.upArrow || (key.ctrl && input === 'p')) return setCursor((value) => Math.max(0, value - 1));
    if (key.downArrow || (key.ctrl && input === 'n')) {
      return setCursor((value) => Math.min(Math.max(0, visible.length - 1), value + 1));
    }
    if (key.pageUp) return setCursor((value) => Math.max(0, value - 10));
    if (key.pageDown) return setCursor((value) => Math.min(Math.max(0, visible.length - 1), value + 10));

    if (key.escape) {
      if (query !== '') return typed('');
      return onCancel();
    }
    if (key.tab) {
      setShowDelivered((value) => !value);
      return setCursor(0);
    }
    if (key.return) {
      if (query !== '' && current) {
        add(current.ticket);
        setQuery('');
        return setCursor(0);
      }
      if (query === '' && (chosen.length > 0 || allowEmpty)) return onDone(chosen);
      return;
    }
    if (input === ' ') {
      if (!current) return;
      if (chosen.includes(current.ticket)) {
        setChosen((list) => list.filter((ticket) => ticket !== current.ticket));
        return setNotice(`${current.ticket} retiré.`);
      }
      return add(current.ticket);
    }
    if (key.backspace || key.delete) {
      if (query !== '') return typed(query.slice(0, -1));
      if (chosen.length > 0) {
        const last = chosen[chosen.length - 1];
        setChosen((list) => list.slice(0, -1));
        setNotice(`${last} retiré.`);
      }
      return;
    }
    if (input && !key.ctrl && !key.meta && /^[^\s]+$/.test(input)) typed(query + input);
  });

  if (!candidates) return <Spinner label="Lecture des tickets du serveur…" />;

  const deliveredCount = candidates.filter((candidate) => candidate.delivered).length;
  const height = listHeight(rows, RESERVED_ROWS);
  const position = pending
    ? visible.findIndex((candidate) => candidate.ticket === pending)
    : Math.min(cursor, Math.max(0, visible.length - 1));
  const { start, end } = windowAround(visible.length, position, height);

  return (
    <Box flexDirection="column">
      <Title>{title}</Title>
      <Text dimColor>{`  base ${base ?? '?'} · ${candidates.length - deliveredCount} ticket(s) disponible(s)`}</Text>

      <Box marginTop={1}>
        <Text color="cyan">{'› '}</Text>
        <Text>{query}</Text>
        <Text inverse> </Text>
        {query === '' ? <Text dimColor>{'  tapez pour filtrer (numéro, nom, message…)'}</Text> : null}
      </Box>

      <Box flexDirection="column">
        {visible.length === 0 ? (
          <Text dimColor>{'  Aucun ticket ne correspond.'}</Text>
        ) : (
          <>
            {start > 0 ? <Text dimColor>{`  ↑ ${start} de plus`}</Text> : null}
            {visible.slice(start, end).map((candidate, offset) => {
              const index = start + offset;
              const selected = index === position;
              const rank = chosen.indexOf(candidate.ticket);
              const mark = rank >= 0 ? `[${rank + 1}]` : candidate.ticket === pending ? '[✓]' : '[ ]';
              return (
                <Text
                  key={candidate.ticket}
                  inverse={selected}
                  color={candidate.ticket === pending && !selected ? 'green' : undefined}
                  dimColor={candidate.delivered && !selected}
                  wrap="truncate-end"
                >
                  {selected ? '❯ ' : '  '}
                  {mark} {pad(candidate.ticket, 30)}
                  {candidate.delivered
                    ? `déjà livré dans ${base}`
                    : `${candidate.updated_at.slice(0, 10)}  ${candidate.last_subject}`}
                </Text>
              );
            })}
            {end < visible.length ? <Text dimColor>{`  ↓ ${visible.length - end} de plus`}</Text> : null}
          </>
        )}
      </Box>

      <Box marginTop={1} flexDirection="column">
        {pending ? <Text color="green">{`✓ ${pending} sélectionné : ⏎ pour l'ajouter`}</Text> : null}
        {chosen.length === 0 ? (
          <Text dimColor>Aucun ticket choisi.</Text>
        ) : (
          <Text wrap="wrap">
            <Text bold>Dans la démo, dans l'ordre : </Text>
            {chosen.map((ticket, index) => `${index + 1}. ${ticket}`).join('   ')}
          </Text>
        )}
        {notice ? <Text color="green">{notice}</Text> : null}
      </Box>

      <KeyHints
        hints={[
          ['abc', 'filtrer'],
          ['↑↓', 'choisir'],
          ['espace', 'cocher'],
          ['⏎', query !== '' ? 'ajouter' : chosen.length > 0 ? `valider (${chosen.length})` : allowEmpty ? 'sans ticket' : 'valider'],
          ['⌫', 'retirer'],
          ...(deliveredCount > 0
            ? ([['tab', showDelivered ? 'masquer livrés' : `livrés (${deliveredCount})`]] as [string, string][])
            : []),
          ['esc', query !== '' ? 'effacer' : 'annuler'],
        ]}
      />
    </Box>
  );
}
