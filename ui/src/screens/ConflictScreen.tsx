import { useState } from 'react';
import { Box, Text, useInput } from 'ink';
import type { ConflictView } from '../jgit.js';
import { KeyHints, Title } from '../components.js';

const KINDS: Record<string, string> = {
  both_modified: 'modifié des deux côtés',
  both_added: 'ajouté des deux côtés',
  both_deleted: 'supprimé des deux côtés',
  added_by_us: "ajouté d'un seul côté",
  added_by_them: "ajouté d'un seul côté",
  deleted_by_us: "supprimé d'un côté, modifié de l'autre",
  deleted_by_them: "modifié d'un côté, supprimé de l'autre",
  conflict_markers: 'des marqueurs <<<<<<< sont restés',
};

export type ConflictAction =
  | { kind: 'continue' }
  | { kind: 'abort' }
  | { kind: 'edit'; file: string }
  | { kind: 'stage'; file: string }
  | { kind: 'claude' }
  | { kind: 'refresh' };

interface Props {
  view: ConflictView;
  claudeAvailable: boolean;
  onAction: (action: ConflictAction) => void;
}

export function ConflictScreen({ view, claudeAvailable, onAction }: Props) {
  const [cursor, setCursor] = useState(0);
  const [confirmAbort, setConfirmAbort] = useState(false);
  const current = view.files[cursor];

  useInput((input, key) => {
    if (confirmAbort) {
      if (input === 'y' || input === 'o' || key.return) onAction({ kind: 'abort' });
      setConfirmAbort(false);
      return;
    }
    if (key.upArrow) return setCursor((value) => Math.max(0, value - 1));
    if (key.downArrow) return setCursor((value) => Math.min(view.files.length - 1, value + 1));
    if (input === 'e' && current) return onAction({ kind: 'edit', file: current.path });
    if (input === 's' && current) return onAction({ kind: 'stage', file: current.path });
    if (input === 'c') return onAction({ kind: 'continue' });
    if (input === 'x') return setConfirmAbort(true);
    if (input === 'i' && claudeAvailable) return onAction({ kind: 'claude' });
    if (input === 'r') return onAction({ kind: 'refresh' });
  });

  const hints: [string, string][] = [];
  if (view.files.length > 0) hints.push(['↑↓', 'fichier'], ['e', 'éditer'], ['s', 'marquer résolu']);
  hints.push(['c', 'reprendre'], ['x', 'tout annuler']);
  if (claudeAvailable) hints.push(['i', 'résoudre avec Claude']);
  hints.push(['r', 'actualiser']);

  return (
    <Box flexDirection="column">
      <Title>
        <Text color="red">⏸ Conflit en attente</Text>
      </Title>
      <Text>{view.label}</Text>
      {view.ticket ? <Text>{`  Ticket       ${view.ticket}`}</Text> : null}
      {view.commitSubject ? <Text>{`  Commit       « ${view.commitSubject} »`}</Text> : null}
      <Box marginTop={1} flexDirection="column">
        {view.files.length === 0 ? (
          <Text color="green">  Plus aucun fichier en conflit : c pour reprendre.</Text>
        ) : (
          <>
            <Text>Fichiers à résoudre :</Text>
            {view.files.map((file, index) => (
              <Text key={file.path} inverse={index === cursor}>
                {index === cursor ? '❯ ' : '  '}
                {file.path} <Text dimColor>({KINDS[file.kind] ?? file.kind})</Text>
              </Text>
            ))}
          </>
        )}
      </Box>
      <Text dimColor>{"\n  Rien n'a été publié. La démo doit montrer les deux tickets ensemble : fusionnez les intentions,"}</Text>
      <Text dimColor>{'  retirez les marqueurs <<<<<<< ======= >>>>>>>, puis marquez le fichier résolu.'}</Text>
      {!claudeAvailable ? (
        <Text dimColor>{'  Avec Claude Code : dans un autre terminal, « claude », puis « résous le conflit de la démo » (skill jgit-demo).'}</Text>
      ) : null}
      {confirmAbort ? <Text color="yellow">{'\nTout annuler ? Rien ne sera publié. (y/N)'}</Text> : null}
      <KeyHints hints={hints} />
    </Box>
  );
}
