import { Box, Text, useInput } from 'ink';
import type { DemoResultDoc } from '../types.js';
import { KeyHints, Title } from '../components.js';

const REASONS: Record<string, string> = {
  requested: 'retiré à votre demande',
  delivered: 'déjà livré dans la base',
  missing: 'branche supprimée du serveur',
  foreign: 'commits ajoutés à la main',
};

const WARNINGS: Record<string, string> = {
  foreign_commits_kept: 'des commits ajoutés à la main seront rejoués à la fin',
  delivered_with_pending_work: 'livré, mais sa branche porte encore du code non livré',
  local_branch_stale: 'votre copie locale porte des commits absents du serveur',
};

interface Props {
  title: string;
  plan: DemoResultDoc;
  onConfirm: () => void;
  onCancel: () => void;
}

// Plan annoncé par « --dry-run » : rien n'a encore été fait.
export function ConfirmScreen({ title, plan, onConfirm, onCancel }: Props) {
  useInput((input, key) => {
    if (key.return || input === 'y' || input === 'o') onConfirm();
    else if (key.escape || input === 'n') onCancel();
  });

  const added = plan.added ?? [];
  const updated = plan.updated ?? [];
  const dropped = plan.dropped ?? [];
  const warnings = plan.warnings ?? [];
  const nothing = added.length + updated.length + dropped.length === 0;

  return (
    <Box flexDirection="column">
      <Title>{title}</Title>
      <Box marginTop={1} flexDirection="column">
        {plan.operation === 'archive' ? <Text>{`  → ${plan.branch}`}</Text> : null}
        {added.map((ticket) => (
          <Text key={`+${ticket}`} color="green">{`  + ${ticket}`}</Text>
        ))}
        {updated.map((ticket) => (
          <Text key={`~${ticket}`} color="yellow">{`  ↻ ${ticket}`}</Text>
        ))}
        {dropped.map((item) => (
          <Text key={`-${item.ticket}`} color="red">{`  - ${item.ticket === '-' ? 'commits ajoutés à la main' : item.ticket} (${REASONS[item.reason] ?? item.reason})`}</Text>
        ))}
        {nothing && plan.operation === 'rebase' ? <Text>  Reconstruction sur la version actuelle de la base, tickets inchangés.</Text> : null}
        {warnings.map((warning, index) => (
          <Text key={index} color="yellow">{`  ⚠ ${WARNINGS[warning.code] ?? warning.code}${warning.ticket ? ` : ${warning.ticket}` : ''}`}</Text>
        ))}
      </Box>
      <Text dimColor>{'\n  Rien n\'a encore été modifié. La démo ne sera publiée que si personne ne l\'a changée entre-temps.'}</Text>
      <KeyHints hints={[['⏎', 'appliquer'], ['esc', 'annuler']]} />
    </Box>
  );
}
