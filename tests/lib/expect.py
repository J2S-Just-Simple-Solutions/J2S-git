#!/usr/bin/env python3
"""Pilote de scenario interactif.

Lance une commande dans un pseudo-terminal (donc jgit se croit devant un vrai
utilisateur : les `read -p` affichent bien leur invite) et deroule un scenario
d'etapes :

    expect<TAB><expression reguliere attendue dans la sortie>
    send<TAB><reponse a taper (un retour chariot est ajoute)>

Codes de sortie :
    0..89  code de sortie de la commande pilotee
    90     une etape `expect` n'a jamais ete satisfaite avant la fin du process
    91     timeout global
    92     erreur d'utilisation du pilote
"""

import argparse
import os
import pty
import re
import select
import signal
import sys
import time

# Sequences ANSI (couleurs tput) et retours chariot : on les retire du tampon
# compare aux attentes, sinon les regex devraient connaitre les codes couleur.
ANSI = re.compile(r"\x1b\][^\x07]*(?:\x07|\x1b\\)|\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b[()][B0]|\r")


def clean(text):
    return ANSI.sub("", text)


def load_steps(path):
    steps = []
    with open(path, "r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            if not line.strip():
                continue
            kind, _, value = line.partition("\t")
            if kind not in ("expect", "send"):
                sys.stderr.write("Etape inconnue dans le scenario : %r\n" % line)
                sys.exit(92)
            steps.append((kind, value))
    return steps


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--steps", required=True, help="fichier decrivant le scenario")
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument("--output", help="fichier ou ecrire la sortie complete")
    parser.add_argument("cmd", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    cmd = args.cmd
    if cmd and cmd[0] == "--":
        cmd = cmd[1:]
    if not cmd:
        sys.stderr.write("Aucune commande a piloter.\n")
        return 92

    steps = load_steps(args.steps)

    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.execvp(cmd[0], cmd)
        except Exception as error:  # pragma: no cover - chemin d'erreur du fils
            sys.stderr.write("Impossible de lancer %s : %s\n" % (cmd[0], error))
        os._exit(127)

    pending = ""      # sortie nettoyee, pas encore consommee par un `expect`
    transcript = []   # sortie brute complete
    index = 0
    eof = False
    deadline = time.time() + args.timeout
    status = None

    def finish(code):
        if args.output:
            with open(args.output, "w", encoding="utf-8") as handle:
                handle.write("".join(transcript))
        return code

    while True:
        # Consommer toutes les etapes que la sortie deja lue permet de traiter.
        while index < len(steps):
            kind, value = steps[index]
            if kind == "send":
                os.write(fd, (value + "\n").encode("utf-8"))
                index += 1
                continue
            match = re.search(value, pending)
            if not match:
                break
            pending = pending[match.end():]
            index += 1

        if eof:
            break

        remaining = deadline - time.time()
        if remaining <= 0:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
            attendu = steps[index][1] if index < len(steps) else "(fin du process)"
            sys.stderr.write(
                "Timeout apres %.0fs en attendant : %s\n" % (args.timeout, attendu)
            )
            sys.stderr.write("--- sortie recue ---\n%s\n" % clean("".join(transcript)))
            return finish(91)

        readable, _, _ = select.select([fd], [], [], min(remaining, 0.2))
        if not readable:
            continue

        try:
            data = os.read(fd, 4096)
        except OSError:
            data = b""

        if not data:
            eof = True
            continue

        text = data.decode("utf-8", "replace")
        transcript.append(text)
        pending += clean(text)

    _, wait_status = os.waitpid(pid, 0)
    if os.WIFEXITED(wait_status):
        status = os.WEXITSTATUS(wait_status)
    elif os.WIFSIGNALED(wait_status):
        status = 128 + os.WTERMSIG(wait_status)
    else:  # pragma: no cover
        status = 1

    if index < len(steps):
        kind, value = steps[index]
        libelle = "attendre" if kind == "expect" else "envoyer"
        sys.stderr.write(
            "Le process s'est termine avant d'avoir pu %s : %s\n" % (libelle, value)
        )
        sys.stderr.write("--- sortie recue ---\n%s\n" % clean("".join(transcript)))
        return finish(90)

    if status >= 90:
        # On garde les codes 90+ pour le pilote lui-meme.
        status = 89
    return finish(status)


if __name__ == "__main__":
    sys.exit(main())
