#!/usr/bin/env python3
"""Lecture du document JSON produit par « jgit … --json », pour les tests.

    json_query.py <fichier> check            le fichier contient exactement un document
                                             JSON, sur une seule ligne terminée par \\n
    json_query.py <fichier> get <chemin>     affiche la valeur (chaîne brute, sinon JSON)
    json_query.py <fichier> len <chemin>     affiche la longueur d'une liste ou d'un objet
    json_query.py <fichier> type <chemin>    string | number | boolean | null | array | object

Chemin : clés séparées par des points, index entre crochets, par exemple
« demos[0].name » ou « error.code ». Une clé absente sort en code 2.
Un élément de liste peut aussi être choisi par la valeur d'un champ :
« tickets[ticket=feature/A].status ».
"""

import json
import re
import sys

TOKEN = re.compile(r"\.?([^.\[\]]+)|\[([^\]]*)\]")


def fail(message, code=2):
    sys.stderr.write(message + "\n")
    sys.exit(code)


def load(path):
    with open(path, encoding="utf-8") as handle:
        raw = handle.read()
    return raw


def parse_single(raw):
    if not raw.endswith("\n"):
        fail("la sortie standard ne se termine pas par un retour à la ligne", 1)
    body = raw[:-1]
    if "\n" in body:
        fail("la sortie standard contient plus d'une ligne :\n" + raw, 1)
    try:
        return json.loads(body)
    except json.JSONDecodeError as error:
        fail("JSON invalide (%s) :\n%s" % (error, raw), 1)


def walk(document, path):
    current = document
    position = 0
    for match in TOKEN.finditer(path):
        if match.start() != position:
            fail("chemin invalide : " + path)
        position = match.end()
        key, index = match.group(1), match.group(2)
        if key is not None:
            if not isinstance(current, dict) or key not in current:
                fail("clé absente : %s (dans %s)" % (key, path))
            current = current[key]
        elif "=" in index:
            field, expected = index.split("=", 1)
            if not isinstance(current, list):
                fail("pas une liste : " + path)
            found = [item for item in current
                     if isinstance(item, dict) and str(item.get(field)) == expected]
            if not found:
                fail("aucun élément avec %s=%s (dans %s)" % (field, expected, path))
            current = found[0]
        else:
            if not isinstance(current, list):
                fail("pas une liste : " + path)
            try:
                current = current[int(index)]
            except (ValueError, IndexError):
                fail("index absent : [%s] (dans %s)" % (index, path))
    if position != len(path):
        fail("chemin invalide : " + path)
    return current


def type_name(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, (int, float)):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    return "object"


def main(argv):
    if len(argv) < 3:
        fail(__doc__, 64)
    document = parse_single(load(argv[1]))
    command = argv[2]
    if command == "check":
        return 0
    if len(argv) != 4:
        fail(__doc__, 64)
    value = walk(document, argv[3]) if argv[3] else document
    if command == "get":
        if isinstance(value, str):
            sys.stdout.write(value)
        else:
            sys.stdout.write(json.dumps(value, ensure_ascii=False))
    elif command == "len":
        if not isinstance(value, (list, dict)):
            fail("ni liste ni objet : " + argv[3])
        sys.stdout.write(str(len(value)))
    elif command == "type":
        sys.stdout.write(type_name(value))
    else:
        fail(__doc__, 64)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
