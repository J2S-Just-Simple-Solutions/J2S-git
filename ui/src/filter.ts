// Filtrage à la frappe : sans tenir compte de la casse ni des accents, chaque
// mot saisi doit apparaître quelque part dans le texte.

export function normalize(text: string): string {
  return text.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
}

// Pertinence d'un ticket pour une saisie, de 0 (le plus pertinent) à 3 :
// identifiant exact, identifiant qui commence par la saisie, nom de branche
// qui la contient, message seul. Taper « PERF-17 » met PERF-17 en tête,
// devant PERF-170 à PERF-179.
export function rank(query: string, ticket: string): number {
  const wanted = normalize(query.trim());
  const name = normalize(ticket);
  const id = name.slice(name.indexOf('/') + 1);
  if (wanted === '') return 3;
  if (id === wanted || name === wanted) return 0;
  if (id.startsWith(wanted) || name.startsWith(wanted)) return 1;
  if (name.includes(wanted)) return 2;
  return 3;
}

export function matches(query: string, text: string): boolean {
  const words = normalize(query).split(/\s+/).filter(Boolean);
  if (words.length === 0) return true;
  const haystack = normalize(text);
  return words.every((word) => haystack.includes(word));
}
