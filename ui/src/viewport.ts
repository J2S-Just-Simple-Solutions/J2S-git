import { useEffect, useState } from 'react';
import { useStdout } from 'ink';

// Ink ne sait redessiner que ce qui est encore à l'écran : un écran plus haut
// que le terminal se réimprime à chaque touche et fait défiler le terminal au
// lieu de bouger la sélection. Toute liste longue n'affiche donc qu'une
// fenêtre, qui suit le curseur.

export function useTerminalSize(): { rows: number; columns: number } {
  const { stdout } = useStdout();
  const read = () => ({ rows: stdout.rows || 24, columns: stdout.columns || 80 });
  const [size, setSize] = useState(read);

  useEffect(() => {
    const onResize = () => setSize(read());
    stdout.on('resize', onResize);
    return () => {
      stdout.off('resize', onResize);
    };
  }, [stdout]);

  return size;
}

export function useTerminalRows(): number {
  return useTerminalSize().rows;
}

// Lignes occupées par un texte qui revient à la ligne.
export function wrappedRows(text: string, columns: number): number {
  return Math.max(1, Math.ceil(text.length / Math.max(20, columns)));
}

// Lignes de la liste à afficher : une fenêtre de `size` lignes qui contient
// toujours le curseur.
export function windowAround(total: number, cursor: number, size: number): { start: number; end: number } {
  const height = Math.max(1, size);
  if (total <= height) return { start: 0, end: total };
  let start = Math.max(0, cursor - Math.floor(height / 2));
  start = Math.min(start, total - height);
  return { start, end: start + height };
}

// Nombre de lignes de liste qui tiennent à l'écran, une fois retirées les
// lignes fixes de l'écran (titre, saisie, aide…).
export function listHeight(rows: number, reserved: number): number {
  return Math.max(3, rows - reserved);
}
