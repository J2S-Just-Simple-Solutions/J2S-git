import { useState } from 'react';
import { Box, Text, useInput } from 'ink';
import { KeyHints, Title } from '../components.js';

// Même règle que jgit (demo_name_is_valid) : on prévient avant d'appeler.
const VALID = /^[A-Za-z0-9][A-Za-z0-9._-]{0,59}$/;

export function isValidDemoName(name: string): boolean {
  return VALID.test(name) && !name.includes('..') && !name.endsWith('.lock') && !name.endsWith('.');
}

interface Props {
  onDone: (name: string) => void;
  onCancel: () => void;
}

export function NameScreen({ onDone, onCancel }: Props) {
  const [name, setName] = useState('');
  const [error, setError] = useState<string | null>(null);

  useInput((input, key) => {
    if (key.escape) return onCancel();
    if (key.return) {
      if (isValidDemoName(name)) return onDone(name);
      return setError('Lettres, chiffres, « . », « _ » ou « - », en commençant par une lettre ou un chiffre.');
    }
    if (key.backspace || key.delete) {
      setName((value) => value.slice(0, -1));
      setError(null);
      return;
    }
    if (input && !key.ctrl && !key.meta && /^[A-Za-z0-9._-]+$/.test(input)) {
      setName((value) => (value + input).slice(0, 60));
      setError(null);
    }
  });

  return (
    <Box flexDirection="column">
      <Title>Nouvelle démo</Title>
      <Box marginTop={1}>
        <Text>Nom : </Text>
        <Text color="cyan">{name}</Text>
        <Text inverse> </Text>
      </Box>
      <Text dimColor>{`  La branche sera demo/${name || '<nom>'}`}</Text>
      {error ? <Text color="red">{error}</Text> : null}
      <KeyHints hints={[['⏎', 'choisir les tickets'], ['esc', 'annuler']]} />
    </Box>
  );
}
