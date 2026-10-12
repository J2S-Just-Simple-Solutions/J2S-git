import { useEffect, useState } from 'react';
import { Box, Text, useInput } from 'ink';
import type { JgitRunner } from '../jgit.js';
import { failureText } from '../jgit.js';
import type { Candidate } from '../types.js';
import { KeyHints, Spinner, Title, pad } from '../components.js';

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

export function PickTicketsScreen({ runner, demo, title, allowEmpty, onDone, onCancel, onError }: Props) {
  const [candidates, setCandidates] = useState<Candidate[] | null>(null);
  const [base, setBase] = useState<string | null>(null);
  const [cursor, setCursor] = useState(0);
  const [chosen, setChosen] = useState<string[]>([]);

  useEffect(() => {
    const args = ['demo', 'candidates'];
    if (demo) args.push(demo);
    runner.run(args).then((result) => {
      if (result.doc && result.doc.schema === 'jgit.demo.candidates/1') {
        // Les tickets déjà livrés vont en bas : inutile de les ajouter.
        const list = [...result.doc.candidates].sort((a, b) => Number(a.delivered) - Number(b.delivered));
        setCandidates(list);
        setBase(result.doc.base);
      } else {
        onError(failureText(result));
        onCancel();
      }
    });
  }, [demo]);

  useInput((input, key) => {
    if (!candidates) return;
    const current = candidates[cursor];
    if (key.escape) return onCancel();
    if (key.upArrow) return setCursor((value) => Math.max(0, value - 1));
    if (key.downArrow) return setCursor((value) => Math.min(candidates.length - 1, value + 1));
    if (input === ' ' && current) {
      // L'ordre de sélection est l'ordre dans la démo.
      setChosen((list) =>
        list.includes(current.ticket) ? list.filter((ticket) => ticket !== current.ticket) : [...list, current.ticket],
      );
      return;
    }
    if (key.return && (chosen.length > 0 || allowEmpty)) onDone(chosen);
  });

  if (!candidates) return <Spinner label="Lecture des tickets du serveur…" />;

  return (
    <Box flexDirection="column">
      <Title>{title}</Title>
      <Text dimColor>{`  base ${base ?? '?'} · cochez dans l'ordre voulu dans la démo`}</Text>
      <Box marginTop={1} flexDirection="column">
        {candidates.length === 0 ? <Text>  Aucun ticket disponible.</Text> : null}
        {candidates.map((candidate, index) => {
          const selected = index === cursor;
          const rank = chosen.indexOf(candidate.ticket);
          const mark = rank >= 0 ? `[${rank + 1}]` : '[ ]';
          return (
            <Text key={candidate.ticket} inverse={selected} dimColor={candidate.delivered && !selected}>
              {selected ? '❯ ' : '  '}
              {mark} {pad(candidate.ticket, 30)}
              {candidate.delivered ? `déjà livré dans ${base}` : `${candidate.updated_at.slice(0, 10)}  ${candidate.last_subject}`}
            </Text>
          );
        })}
      </Box>
      <KeyHints
        hints={[
          ['↑↓', 'choisir'],
          ['espace', 'cocher'],
          ['⏎', chosen.length > 0 ? `valider (${chosen.length})` : allowEmpty ? 'continuer sans ticket' : 'valider'],
          ['esc', 'annuler'],
        ]}
      />
    </Box>
  );
}
