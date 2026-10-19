import { useEffect, useState } from 'react';
import { Box, Text } from 'ink';
import type { DemoTicket } from './types.js';

export function KeyHints({ hints }: { hints: [string, string][] }) {
  return (
    <Box marginTop={1}>
      <Text dimColor>{hints.map(([key, label]) => `${key} ${label}`).join(' · ')}</Text>
    </Box>
  );
}

export type FlashKind = 'success' | 'error' | 'info';
export interface Flash {
  kind: FlashKind;
  text: string;
}

export function FlashLine({ flash }: { flash: Flash | null }) {
  if (!flash) return null;
  const color = flash.kind === 'success' ? 'green' : flash.kind === 'error' ? 'red' : 'yellow';
  return (
    <Box marginTop={1} flexDirection="column">
      {flash.text.split('\n').map((line, index) => (
        <Text key={index} color={color}>
          {line}
        </Text>
      ))}
    </Box>
  );
}

const FRAMES = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];

export function Spinner({ label }: { label: string }) {
  const [frame, setFrame] = useState(0);
  useEffect(() => {
    const timer = setInterval(() => setFrame((value) => (value + 1) % FRAMES.length), 80);
    return () => clearInterval(timer);
  }, []);
  return (
    <Text>
      <Text color="cyan">{FRAMES[frame]}</Text> {label}
    </Text>
  );
}

export function Title({ children }: { children: React.ReactNode }) {
  return (
    <Text bold color="blue">
      {children}
    </Text>
  );
}

// Libellé d'un ticket, aligné sur « jgit demo show ».
export function ticketState(ticket: DemoTicket, base: string | null): { text: string; color: string } {
  if (ticket.delivered) return { text: `✔ livré dans ${base ?? 'la base'}`, color: 'green' };
  switch (ticket.status) {
    case 'up_to_date':
      return { text: '✔ à jour', color: 'green' };
    case 'ahead': {
      const count = ticket.commits_not_in_demo ?? 0;
      return {
        text: `↻ ${count} commit${count > 1 ? 's' : ''} pas encore dans la démo`,
        color: 'yellow',
      };
    }
    case 'diverged':
      return { text: '≠ réécrit depuis son ajout (squash…)', color: 'yellow' };
    case 'missing':
      return { text: '✖ branche supprimée du serveur', color: 'red' };
    default:
      return { text: '? ancien format', color: 'gray' };
  }
}

export function pad(text: string, width: number): string {
  return text.length >= width ? text.slice(0, width - 1) + ' ' : text + ' '.repeat(width - text.length);
}
