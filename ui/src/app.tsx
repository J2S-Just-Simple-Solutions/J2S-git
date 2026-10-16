import { useEffect, useState } from 'react';
import { Box, Text, useApp } from 'ink';
import type { JgitResult, JgitRunner, ConflictView } from './jgit.js';
import { conflictFromDoc, conflictFromStatus, failureText } from './jgit.js';
import type { CheckDoc, DemoResultDoc } from './types.js';
import { FlashLine, Spinner } from './components.js';
import type { Flash } from './components.js';
import { ListScreen } from './screens/ListScreen.js';
import { DetailScreen } from './screens/DetailScreen.js';
import type { DetailAction } from './screens/DetailScreen.js';
import { PickTicketsScreen } from './screens/PickTicketsScreen.js';
import { NameScreen } from './screens/NameScreen.js';
import { BasePickScreen } from './screens/BasePickScreen.js';
import { ConfirmScreen } from './screens/ConfirmScreen.js';
import { ConflictScreen } from './screens/ConflictScreen.js';
import { CheckScreen } from './screens/CheckScreen.js';
import type { ConflictAction } from './screens/ConflictScreen.js';

export type Screen =
  | { kind: 'boot' }
  | { kind: 'list' }
  | { kind: 'detail'; branch: string }
  | { kind: 'name' }
  | { kind: 'base'; name: string }
  | { kind: 'pick'; mode: 'add'; demo: string }
  | { kind: 'pick'; mode: 'create'; name: string; base: string }
  | { kind: 'confirm'; title: string; plan: DemoResultDoc; args: string[]; back: Screen }
  | { kind: 'running'; label: string }
  | { kind: 'conflict'; view: ConflictView; back: Screen }
  | { kind: 'check'; doc: CheckDoc; demo: string | null; back: Screen };

// Ce que l'interface ne peut pas faire elle-même pendant qu'elle occupe le
// terminal : ouvrir un éditeur, lancer Claude Code. Le lanceur (cli.tsx) rend
// la main, exécute, puis relance l'interface.
export type SpawnRequest = { kind: 'editor'; file: string } | { kind: 'claude'; prompt: string };

export interface AppProps {
  runner: JgitRunner;
  claudeAvailable: boolean;
  stage: (file: string) => Promise<void>;
  onSpawn: (request: SpawnRequest) => void;
  initialFlash?: Flash | null;
}

function resultText(doc: DemoResultDoc): string {
  if (!doc.changed) return 'Rien à faire : la démo était déjà dans cet état, rien n’a été publié.';
  switch (doc.operation) {
    case 'archive':
      return `Démo archivée : ${doc.branch}. Son nom est libre pour une nouvelle démo.`;
    case 'unarchive':
      return `Démo restaurée : ${doc.branch}.`;
    case 'delete':
      return 'Démo supprimée.';
    default: {
      const parts: string[] = [];
      if (doc.added?.length) parts.push(`ajouté : ${doc.added.join(', ')}`);
      if (doc.updated?.length) parts.push(`mis à jour : ${doc.updated.join(', ')}`);
      if (doc.dropped?.length) parts.push(`retiré : ${doc.dropped.map((item) => item.ticket).join(', ')}`);
      return `Démo ${doc.branch ?? doc.demo} publiée.${parts.length ? ` (${parts.join(' · ')})` : ''}`;
    }
  }
}

export function App({ runner, claudeAvailable, stage, onSpawn, initialFlash = null }: AppProps) {
  const { exit } = useApp();
  const [screen, setScreen] = useState<Screen>({ kind: 'boot' });
  const [flash, setFlash] = useState<Flash | null>(initialFlash);
  const [reloadKey, setReloadKey] = useState(0);

  const go = (next: Screen) => {
    if (next.kind === 'detail') setReloadKey((value) => value + 1);
    setScreen(next);
  };
  const error = (text: string) => setFlash({ kind: 'error', text });

  // Au démarrage (et au retour d'un éditeur ou de Claude) : une opération
  // attend-elle la résolution d'un conflit ?
  const checkStatus = async (fallback: Screen) => {
    const result = await runner.run(['util', 'status', '--no-fetch']);
    const doc = result.doc;
    if (doc && doc.schema === 'jgit.status/1' && doc.operation_in_progress) {
      setScreen({ kind: 'conflict', view: conflictFromStatus(doc.operation_in_progress), back: { kind: 'list' } });
    } else {
      go(fallback);
    }
  };

  useEffect(() => {
    if (screen.kind === 'boot') void checkStatus({ kind: 'list' });
  }, []);

  const handleResult = (result: JgitResult, back: Screen) => {
    const doc = result.doc;
    if (doc && doc.schema === 'jgit.conflict/1' && doc.paused) {
      setFlash(null);
      setScreen({ kind: 'conflict', view: conflictFromDoc(doc), back });
      return;
    }
    if (doc && doc.schema === 'jgit.demo.result/1') {
      setFlash({ kind: 'success', text: resultText(doc) });
      if (doc.operation === 'archive' || doc.operation === 'delete') return go({ kind: 'list' });
      if (doc.branch && ['create', 'migrate', 'unarchive'].includes(doc.operation)) {
        return go({ kind: 'detail', branch: doc.branch });
      }
      return go(back.kind === 'conflict' || back.kind === 'running' ? { kind: 'list' } : back);
    }
    if (doc && doc.ok && doc.schema === 'jgit.status/1') return go(back);
    error(failureText(result));
    go(back);
  };

  const apply = async (args: string[], title: string, back: Screen) => {
    setFlash(null);
    setScreen({ kind: 'running', label: `${title}…` });
    handleResult(await runner.run([...args, '--on-conflict', 'pause']), back);
  };

  const mutate = async (args: string[], title: string, preview: boolean, back: Screen) => {
    if (!preview) return apply(args, title, back);
    setFlash(null);
    setScreen({ kind: 'running', label: 'Préparation du plan…' });
    const result = await runner.run([...args, '--dry-run']);
    const doc = result.doc;
    if (doc && doc.schema === 'jgit.demo.result/1') {
      if (!doc.changed) {
        setFlash({ kind: 'info', text: resultText(doc) });
        return go(back);
      }
      return setScreen({ kind: 'confirm', title, plan: doc, args, back });
    }
    error(failureText(result));
    go(back);
  };

  // Vérification (simulation, rien n'est modifié) : toutes les démos, ou une.
  const check = async (demo: string | null, back: Screen) => {
    setFlash(null);
    setScreen({ kind: 'running', label: 'Vérification des mises à jour (simulation, rien ne sera modifié)…' });
    const result = await runner.run(demo ? ['demo', 'check', demo] : ['demo', 'check']);
    if (result.doc && result.doc.schema === 'jgit.demo.check/1') {
      return setScreen({ kind: 'check', doc: result.doc, demo, back });
    }
    error(failureText(result));
    go(back);
  };

  const onDetailAction = (branch: string) => (action: DetailAction) => {
    const back: Screen = { kind: 'detail', branch };
    if (action.kind === 'back') return go({ kind: 'list' });
    if (action.kind === 'check') return void check(action.demo, back);
    if (action.kind === 'pick') return setScreen({ kind: 'pick', mode: 'add', demo: action.demo });
    void mutate(action.args, action.title, action.preview, back);
  };

  const onConflictAction = (view: ConflictView, back: Screen) => async (action: ConflictAction) => {
    switch (action.kind) {
      case 'continue':
        setScreen({ kind: 'running', label: 'Reprise…' });
        return handleResult(await runner.run(view.continueArgs), back);
      case 'abort': {
        setScreen({ kind: 'running', label: 'Annulation…' });
        const result = await runner.run(view.abortArgs);
        if (result.exitCode === 0) setFlash({ kind: 'info', text: 'Opération annulée : rien n’a été publié.' });
        else error(failureText(result));
        return go({ kind: 'list' });
      }
      case 'edit':
        return onSpawn({ kind: 'editor', file: action.file });
      case 'claude':
        return onSpawn({
          kind: 'claude',
          prompt:
            `Une opération jgit est en pause sur un conflit (${view.label}). ` +
            'Lis « jgit util status --json », résous le conflit en suivant le skill jgit-demo, puis reprends.',
        });
      case 'stage':
        await stage(action.file);
        return checkStatus({ kind: 'list' });
      case 'refresh':
        return checkStatus({ kind: 'list' });
    }
  };

  let body: React.ReactNode;
  switch (screen.kind) {
    case 'boot':
      body = <Spinner label="jgit…" />;
      break;
    case 'running':
      body = <Spinner label={screen.label} />;
      break;
    case 'list':
      body = (
        <ListScreen
          runner={runner}
          onOpen={(demo) => go({ kind: 'detail', branch: demo.branch })}
          onCreate={() => setScreen({ kind: 'name' })}
          onCheck={() => void check(null, { kind: 'list' })}
          onQuit={() => exit()}
          onError={error}
        />
      );
      break;
    case 'detail':
      body = (
        <DetailScreen
          runner={runner}
          branch={screen.branch}
          reloadKey={reloadKey}
          onAction={onDetailAction(screen.branch)}
          onError={error}
        />
      );
      break;
    case 'name':
      body = (
        <NameScreen
          onDone={(name) => setScreen({ kind: 'base', name })}
          onCancel={() => go({ kind: 'list' })}
        />
      );
      break;
    case 'base': {
      const name = screen.name;
      body = (
        <BasePickScreen
          runner={runner}
          title={`Base de la nouvelle démo ${name}`}
          onDone={(base) => setScreen({ kind: 'pick', mode: 'create', name, base })}
          onCancel={() => setScreen({ kind: 'name' })}
          onError={error}
        />
      );
      break;
    }
    case 'pick':
      if (screen.mode === 'add') {
        const demo = screen.demo;
        body = (
          <PickTicketsScreen
            runner={runner}
            demo={demo}
            title={`Ajouter des tickets à la démo ${demo}`}
            allowEmpty={false}
            onDone={(tickets) =>
              void apply(
                ['demo', 'add', demo, ...tickets.flatMap((ticket) => ['--from', ticket])],
                `Ajout de ${tickets.join(', ')}`,
                { kind: 'detail', branch: `demo/${demo}` },
              )
            }
            onCancel={() => go({ kind: 'detail', branch: `demo/${demo}` })}
            onError={error}
          />
        );
      } else {
        const { name, base } = screen;
        body = (
          <PickTicketsScreen
            runner={runner}
            demo={null}
            base={base}
            title={`Tickets de la nouvelle démo ${name} (base ${base})`}
            allowEmpty={true}
            onDone={(tickets) =>
              void mutate(
                ['demo', 'create', name, '--based-on', base, ...tickets.flatMap((ticket) => ['--from', ticket])],
                `Créer la démo demo/${name} sur ${base}`,
                true,
                { kind: 'list' },
              )
            }
            onCancel={() => setScreen({ kind: 'base', name })}
            onError={error}
          />
        );
      }
      break;
    case 'confirm': {
      const { title, plan, args, back } = screen;
      body = (
        <ConfirmScreen
          title={title}
          plan={plan}
          onConfirm={() => void apply(args, title, back)}
          onCancel={() => go(back)}
        />
      );
      break;
    }
    case 'check': {
      const { doc, demo, back } = screen;
      body = <CheckScreen doc={doc} onBack={() => go(back)} onRerun={() => void check(demo, back)} />;
      break;
    }
    case 'conflict':
      body = (
        <ConflictScreen
          view={screen.view}
          claudeAvailable={claudeAvailable}
          onAction={(action) => void onConflictAction(screen.view, screen.back)(action)}
        />
      );
      break;
  }

  return (
    <Box flexDirection="column" paddingX={1}>
      <Text dimColor>jgit · démos</Text>
      {body}
      <FlashLine flash={flash} />
    </Box>
  );
}
