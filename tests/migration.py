"""Migration autonome : vrais dépôts locaux, HOME isolé, confirmation par PTY."""
import errno
import io
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest

BASH = sys.argv.pop(1) if len(sys.argv) > 1 else '/bin/bash'
SCRIPT = Path(__file__).resolve().parents[1] / 'Mettre-a-jour-jgit.sh'
URL = 'git@github.com:J2S-Just-Simple-Solutions/J2S-git.git'
GIT = shutil.which('git')


class DepotMigration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='migration-jgit-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.home = self.root / 'home'
        self.home.mkdir()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{self.bin}:/usr/bin:/bin',
                        GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=str(self.home / '.gitconfig'),
                        LC_ALL='C', TERM='dumb')
        for name in list(self.env):
            if name.startswith('GIT_') and name not in ('GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL'):
                del self.env[name]
        self.mock('uname', 'echo Darwin')
        self.mock('id', 'echo 501')
        self.mock('ps', 'exit 0')
        self.mock('ssh', 'echo "Hi test! You have successfully authenticated"; exit 1')
        self.source = self.root / 'officiel'
        self.git('init', '-q', '-b', 'main', str(self.source))
        self.git('config', '--global', 'user.name', 'Test migration')
        self.git('config', '--global', 'user.email', 'migration@example.invalid')
        self.git('config', '--global', f'url.{self.source}.insteadOf', URL)
        (self.source / 'jgit.sh').write_text('#!/bin/bash\nexit 0\n')
        (self.source / 'README.md').write_text('jgit officiel\n')
        (self.source / '.gitignore').write_text('suivi-ignore.txt\nsecret-local.txt\n')
        (self.source / 'suivi-ignore.txt').write_text('fichier suivi malgré le gitignore\n')
        self.git('-C', str(self.source), 'add', '-f', '.')
        self.commit('Version initiale')
        self.old = self.git('-C', str(self.source), 'rev-parse', 'HEAD').strip()
        self.git('-C', str(self.source), 'tag', '1.0.0')
        self.install = self.home / 'jgit'
        self.alias = self.home / '.zprofile'
        self.alias.write_text(f"alias jgit='{self.install}/jgit.sh'\n")

    def mock(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/sh\n' + body + '\n')
        path.chmod(0o755)

    def git(self, *args):
        return subprocess.check_output([GIT, *args], env=self.env, stderr=subprocess.PIPE).decode()

    def commit(self, message):
        self.git('-C', str(self.source), 'add', '-f', '.')
        self.git('-C', str(self.source), 'commit', '-qm', message)

    def nouveau(self, invalide=False):
        (self.source / 'README.md').write_text('jgit nouvelle version\n')
        if invalide:
            (self.source / 'jgit.sh').write_text('#!/bin/bash\nexit 1\n')
        self.commit('Nouvelle version')

    def zip(self):
        self.install.mkdir()
        archive = subprocess.check_output([GIT, '-C', str(self.source), 'archive', self.old], env=self.env)
        with tarfile.open(fileobj=io.BytesIO(archive)) as contenu:
            contenu.extractall(self.install)

    def clone(self):
        self.git('clone', '-q', URL, str(self.install))

    def lancer(self, reponse='oui', avant_confirmation=None, programme=SCRIPT,
               direct=False, repertoire_depart=None, arguments=()):
        pid, fd = pty.fork()
        if pid == 0:
            os.chdir(repertoire_depart or self.home)
            self.env["JGIT_TEST_CALLER_PID"] = str(os.getpid())
            if direct:
                os.execve(str(programme), [str(programme), *arguments], self.env)
            os.execve(BASH, [BASH, str(programme), *arguments], self.env)
        sortie = b''
        repondu = False
        status = None
        try:
            limite = time.monotonic() + 25
            while time.monotonic() < limite:
                if select.select([fd], [], [], 0.1)[0]:
                    try:
                        bloc = os.read(fd, 65536)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            break
                        raise
                    if not bloc:
                        break
                    sortie += bloc
                    if b'[o/N]' in sortie and not repondu:
                        repondu = True
                        if avant_confirmation:
                            avant_confirmation()
                        os.write(fd, (reponse + '\n').encode())
            else:
                self.fail('Délai dépassé : ' + sortie.decode(errors='replace'))
        finally:
            os.close(fd)
            termine, status = os.waitpid(pid, os.WNOHANG)
            if not termine:
                # Le PTY peut se fermer juste avant la fin du processus.
                for _ in range(50):
                    termine, status = os.waitpid(pid, os.WNOHANG)
                    if termine:
                        break
                    time.sleep(0.02)
                if not termine:
                    os.kill(pid, signal.SIGKILL)
                    _, status = os.waitpid(pid, 0)
        return os.waitstatus_to_exitcode(status), sortie.decode(errors='replace')

    def sauvegardes(self):
        return list(self.home.glob('jgit.zip-sauvegarde-*'))



class Migration(DepotMigration):
    def test_sh_seul_sans_droit_execution_depuis_un_autre_dossier(self):
        self.zip()
        copie = self.root / 'Mettre à jour jgit.sh'
        shutil.copy2(SCRIPT, copie)
        copie.chmod(0o644)
        code, sortie = self.lancer('non', programme=copie,
                                  repertoire_depart=self.install)
        self.assertEqual(code, 0, sortie)
        self.assertIn('Annulé', sortie)
        self.assertNotIn('Appuyez sur Entrée pour terminer', sortie)

    def test_zip_migre_et_conserve_sauvegarde(self):
        self.zip()
        self.nouveau()
        code, sortie = self.lancer()
        self.assertEqual(code, 0, sortie)
        self.assertTrue((self.install / '.git').is_dir(), sortie)
        self.assertEqual(len(self.sauvegardes()), 1)
        self.assertEqual((self.sauvegardes()[0] / 'README.md').read_text(), 'jgit officiel\n')
        self.assertIn('Migration terminée', sortie)
        self.assertNotIn('Appuyez sur Entrée pour terminer', sortie)

    def test_zip_modifie_refuse(self):
        self.zip()
        (self.install / 'suivi-ignore.txt').write_text('modification masquée par gitignore\n')
        code, sortie = self.lancer()
        self.assertNotEqual(code, 0, sortie)
        self.assertIn('modifié', sortie)
        self.assertFalse(self.sauvegardes())

    def test_zip_ajout_ignore_refuse(self):
        self.zip()
        (self.install / '.gitignore').write_text('*\n')
        (self.install / 'personnel.txt').write_text('à conserver\n')
        code, sortie = self.lancer()
        self.assertNotEqual(code, 0, sortie)
        self.assertIn('personnel.txt', sortie)

    def test_annulation_sans_modification(self):
        self.zip()
        code, sortie = self.lancer('non')
        self.assertEqual(code, 0, sortie)
        self.assertIn('Annulé', sortie)
        self.assertFalse((self.install / '.git').exists())
        self.assertFalse(self.sauvegardes())

    def test_zip_echec_restaure(self):
        self.zip()
        self.nouveau(invalide=True)
        code, sortie = self.lancer()
        self.assertNotEqual(code, 0, sortie)
        self.assertIn('Ancien dossier remis en place', sortie)
        self.assertFalse((self.install / '.git').exists())
        self.assertEqual((self.install / 'README.md').read_text(), 'jgit officiel\n')

    def test_clone_a_jour(self):
        self.clone()
        code, sortie = self.lancer()
        self.assertEqual(code, 0, sortie)
        self.assertIn('déjà à jour', sortie)

    def test_clone_avance_rapide(self):
        self.clone()
        self.nouveau()
        code, sortie = self.lancer()
        self.assertEqual(code, 0, sortie)
        self.assertEqual(self.git('-C', str(self.install), 'rev-parse', 'HEAD'),
                         self.git('-C', str(self.source), 'rev-parse', 'HEAD'))

    def test_clone_echec_restaure(self):
        self.clone()
        self.nouveau(invalide=True)
        code, sortie = self.lancer()
        self.assertNotEqual(code, 0, sortie)
        self.assertIn('Clone revenu', sortie)
        self.assertEqual(self.git('-C', str(self.install), 'rev-parse', 'HEAD').strip(), self.old)

    def test_clone_non_suivi_conserve(self):
        self.clone()
        (self.install / '.DS_Store').write_text('Finder')
        (self.install / 'travail.txt').write_text('travail personnel')
        self.nouveau()
        code, sortie = self.lancer()
        self.assertEqual(code, 0, sortie)
        self.assertEqual(self.git('-C', str(self.install), 'rev-parse', 'HEAD'),
                         self.git('-C', str(self.source), 'rev-parse', 'HEAD'))
        self.assertEqual((self.install / '.DS_Store').read_text(), 'Finder')
        self.assertEqual((self.install / 'travail.txt').read_text(), 'travail personnel')

    def test_clone_non_suivi_non_ecrase(self):
        self.clone()
        (self.install / 'notes.txt').write_text('mes notes')
        (self.source / 'notes.txt').write_text('nouveau fichier officiel')
        self.commit('Fichier notes.txt ajouté')
        code, sortie = self.lancer()
        self.assertNotEqual(code, 0, sortie)
        self.assertEqual((self.install / 'notes.txt').read_text(), 'mes notes')
        self.assertEqual(self.git('-C', str(self.install), 'rev-parse', 'HEAD').strip(), self.old)

    def test_clone_fichier_ignore_non_ecrase(self):
        self.clone()
        (self.install / 'secret-local.txt').write_text('configuration personnelle')
        (self.source / 'secret-local.txt').write_text('nouveau fichier officiel')
        self.commit('Fichier désormais suivi')
        code, sortie = self.lancer()
        self.assertNotEqual(code, 0, sortie)
        self.assertEqual((self.install / 'secret-local.txt').read_text(), 'configuration personnelle')
        self.assertEqual(self.git('-C', str(self.install), 'rev-parse', 'HEAD').strip(), self.old)

    def test_clone_branche_travail_refuse(self):
        self.clone()
        self.git('-C', str(self.install), 'switch', '-qc', 'travail')
        code, sortie = self.lancer()
        self.assertNotEqual(code, 0, sortie)
        self.assertIn('branche travail', sortie)

    def test_clone_divergent_refuse(self):
        self.clone()
        (self.install / 'README.md').write_text('jgit travail local')
        self.git('-C', str(self.install), 'commit', '-qam', 'Travail local')
        self.nouveau()
        code, sortie = self.lancer()
        self.assertNotEqual(code, 0, sortie)
        self.assertIn('commits qui ne sont pas', sortie)

    def test_commit_confirme_reste_celui_installe(self):
        self.clone()
        self.nouveau()
        attendu = self.git('-C', str(self.source), 'rev-parse', 'HEAD')
        code, sortie = self.lancer(avant_confirmation=lambda: self.nouveau(invalide=True))
        self.assertEqual(code, 0, sortie)
        self.assertEqual(self.git('-C', str(self.install), 'rev-parse', 'HEAD'), attendu)

    def test_ssh_echec_avant_migration(self):
        self.zip()
        self.mock('ssh', 'echo "Host key verification failed"; exit 255')
        self.mock('pbcopy', 'exit 1')
        code, sortie = self.lancer()
        self.assertNotEqual(code, 0, sortie)
        self.assertIn('Guide-moi pas à pas', sortie)
        self.assertNotIn('Appuyez sur Entrée pour terminer', sortie)
        self.assertFalse(self.sauvegardes())

    def test_zip_interrompu_restaure(self):
        self.zip()
        self.mock('mv', '/bin/mv "$@" || exit 1\ncase "$2" in *.zip-sauvegarde-*) kill -TERM "$PPID" ;; esac')
        code, sortie = self.lancer()
        self.assertEqual(code, 143, sortie)
        self.assertNotIn('Appuyez sur Entrée pour terminer', sortie)
        self.assertIn('Ancien dossier remis en place', sortie)
        self.assertFalse((self.install / '.git').exists())

    def test_zip_echec_installation_restaure(self):
        self.zip()
        self.mock('mv', 'case "$1" in */clone) exit 1 ;; esac\nexec /bin/mv "$@"')
        code, sortie = self.lancer()
        self.assertNotEqual(code, 0, sortie)
        self.assertIn('Ancien dossier remis en place', sortie)
        self.assertFalse((self.install / '.git').exists())

    def test_clone_modifie_pendant_confirmation_refuse(self):
        self.clone()
        self.nouveau()
        code, sortie = self.lancer(avant_confirmation=lambda: (self.install / 'README.md').write_text('travail'))
        self.assertNotEqual(code, 0, sortie)
        self.assertIn('changé pendant la confirmation', sortie)
        self.assertEqual(self.git('-C', str(self.install), 'rev-parse', 'HEAD').strip(), self.old)

    def test_alias_commande_supplementaire_refuse(self):
        self.zip()
        self.alias.write_text(f"alias jgit='{self.install}/jgit.sh'; touch '{self.home}/intrus'\n")
        code, sortie = self.lancer()
        self.assertNotEqual(code, 0, sortie)
        self.assertIn('Alias jgit non reconnu', sortie)
        self.assertFalse((self.home / 'intrus').exists())

    def test_alias_home_et_commentaire_acceptes(self):
        self.zip()
        self.alias.write_text('alias jgit="bash $HOME/jgit/jgit.sh" # installation\n')
        code, sortie = self.lancer('non')
        self.assertEqual(code, 0, sortie)
        self.assertIn('Annulé', sortie)

    def test_origine_ressemblante_refusee(self):
        self.clone()
        self.git('-C', str(self.install), 'remote', 'set-url', 'origin',
                 'https://example.invalid/J2S-Just-Simple-Solutions/J2S-git.git')
        code, sortie = self.lancer()
        self.assertNotEqual(code, 0, sortie)
        self.assertIn('pas celui du dépôt jgit officiel', sortie)

    def test_zip_lien_symbolique_refuse(self):
        self.zip()
        cible = self.install / 'README.md'
        cible.unlink()
        cible.symlink_to(self.source / 'README.md')
        code, sortie = self.lancer()
        self.assertNotEqual(code, 0, sortie)
        self.assertIn('lien symbolique', sortie)


class AutoUpdate(DepotMigration):
    def setUp(self):
        super().setUp()
        for fichier in SCRIPT.parent.glob('*.sh'):
            shutil.copy2(fichier, self.source / fichier.name)
        self.commit('Installation avec auto-update')
        self.old = self.git('-C', str(self.source), 'rev-parse', 'HEAD').strip()

    def cli(self, *arguments):
        return subprocess.run([BASH, str(self.install / 'jgit.sh'), *arguments],
                              cwd=self.home, env=self.env, capture_output=True, text=True,
                              timeout=25)

    def interactif(self, reponse='oui'):
        return self.lancer(reponse, programme=self.install / 'jgit.sh',
                           arguments=('auto-update',))

    def test_met_a_jour_hors_projet_sans_alias(self):
        self.clone()
        self.alias.unlink()
        self.nouveau()
        self.git('config', '--global', '--unset', 'user.name')
        self.git('config', '--global', '--unset', 'user.email')
        code, sortie = self.interactif()
        self.assertEqual(code, 0, sortie)
        self.assertIn('jgit est à jour', sortie)
        self.assertEqual(self.git('-C', str(self.install), 'rev-parse', 'HEAD'),
                         self.git('-C', str(self.source), 'rev-parse', 'HEAD'))

    def test_alias_different_ignore(self):
        self.clone()
        self.alias.write_text("alias jgit='/installation/inconnue/jgit.sh'\n")
        self.nouveau()
        code, sortie = self.interactif()
        self.assertEqual(code, 0, sortie)
        self.assertEqual((self.install / 'README.md').read_text(), 'jgit nouvelle version\n')

    def test_zip_utilise_meme_moteur(self):
        self.zip()
        self.nouveau()
        code, sortie = self.interactif()
        self.assertEqual(code, 0, sortie)
        self.assertIn('Migration terminée', sortie)
        self.assertEqual(len(self.sauvegardes()), 1)

    def test_mise_a_jour_de_son_propre_script(self):
        self.clone()
        moteur = self.source / SCRIPT.name
        moteur.write_text(moteur.read_text() + '\n# Nouvelle version du moteur.\n')
        self.commit('Moteur mis à jour')
        code, sortie = self.interactif()
        self.assertEqual(code, 0, sortie)
        self.assertIn('Nouvelle version du moteur.', (self.install / SCRIPT.name).read_text())

    def test_echec_restaure_installation(self):
        self.clone()
        self.nouveau(invalide=True)
        code, sortie = self.interactif()
        self.assertNotEqual(code, 0, sortie)
        self.assertIn('Clone revenu', sortie)
        self.assertEqual(self.git('-C', str(self.install), 'rev-parse', 'HEAD').strip(), self.old)

    def test_sans_interaction_annule_par_defaut(self):
        self.clone()
        self.nouveau()
        resultat = self.cli('auto-update', '--no-interaction')
        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        self.assertIn('[no-interaction]', resultat.stdout)
        self.assertEqual(self.git('-C', str(self.install), 'rev-parse', 'HEAD').strip(), self.old)

    def test_json_unique_sans_interaction(self):
        self.clone()
        self.nouveau()
        resultat = self.cli('--json', 'auto-update')
        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        document = json.loads(resultat.stdout)
        self.assertEqual(document['command'], 'auto-update')
        self.assertTrue(document['ok'])
        self.assertIn('[no-interaction]', resultat.stderr)
        self.assertEqual(self.git('-C', str(self.install), 'rev-parse', 'HEAD').strip(), self.old)

    def test_erreur_json_unique(self):
        self.clone()
        (self.install / 'README.md').write_text('travail')
        resultat = self.cli('auto-update', '--json')
        self.assertNotEqual(resultat.returncode, 0)
        document = json.loads(resultat.stdout)
        self.assertEqual(document['error']['code'], 'auto_update_failed')
        self.assertIn('README.md', resultat.stderr)

    def test_option_non_acceptee_refusee_avant_git(self):
        self.clone()
        self.mock('git', 'exit 99')
        resultat = self.cli('auto-update', '--no-fetch', '--json')
        self.assertEqual(resultat.returncode, 1)
        self.assertEqual(json.loads(resultat.stdout)['error']['code'], 'usage')

    def test_aide_accessible_sans_git(self):
        self.clone()
        self.mock('git', 'exit 99')
        resultat = self.cli('auto-update', '--help')
        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        self.assertIn('jgit auto-update', resultat.stdout)
        self.assertEqual(resultat.stderr, '')

    def test_lien_symbolique_choisit_installation_reelle(self):
        self.clone()
        self.nouveau()
        lien = self.home / 'raccourci-jgit'
        lien.symlink_to(self.install / 'jgit.sh')
        code, sortie = self.lancer(programme=lien, arguments=('auto-update',))
        self.assertEqual(code, 0, sortie)
        self.assertEqual(self.git('-C', str(self.install), 'rev-parse', 'HEAD'),
                         self.git('-C', str(self.source), 'rev-parse', 'HEAD'))

    def test_configuration_projet_non_chargee(self):
        self.clone()
        self.nouveau()
        projet = self.root / 'projet'
        configuration = projet / '.jgit'
        configuration.mkdir(parents=True)
        (configuration / 'conf_local.sh').write_text('echo CONFIGURATION_CHARGEE; exit 97\n')
        code, sortie = self.lancer(programme=self.install / 'jgit.sh',
                                   repertoire_depart=projet, arguments=('auto-update',))
        self.assertEqual(code, 0, sortie)
        self.assertNotIn('CONFIGURATION_CHARGEE', sortie)

    def test_processus_jgit_appelant_accepte(self):
        self.clone()
        self.nouveau()
        self.mock('ps', f'echo "$JGIT_TEST_CALLER_PID bash {self.install}/jgit.sh auto-update"')
        code, sortie = self.interactif()
        self.assertEqual(code, 0, sortie)
        self.assertIn('jgit est à jour', sortie)

    def test_autre_processus_jgit_refuse(self):
        self.clone()
        self.mock('ps', f'echo "999999 bash {self.install}/jgit.sh ui"')
        code, sortie = self.interactif()
        self.assertNotEqual(code, 0, sortie)
        self.assertIn("jgit est en cours d'utilisation", sortie)

    def test_argument_supplementaire_refuse(self):
        self.clone()
        resultat = self.cli('auto-update', 'auto-update', '--json')
        self.assertEqual(resultat.returncode, 1)
        self.assertEqual(json.loads(resultat.stdout)['error']['code'], 'usage')

    def test_moteur_manquant_diagnostique(self):
        self.clone()
        (self.install / SCRIPT.name).unlink()
        resultat = self.cli('auto-update', '--json')
        self.assertEqual(resultat.returncode, 1)
        self.assertEqual(json.loads(resultat.stdout)['error']['code'], 'updater_missing')


if __name__ == '__main__':
    unittest.main(verbosity=2)
