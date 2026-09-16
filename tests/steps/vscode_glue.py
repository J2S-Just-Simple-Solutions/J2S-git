# Fichier généré par tests/steps/generate_vscode_glue.sh — ne pas éditer.
#
# Ce module n'est jamais exécuté. Il existe uniquement pour l'extension Cucumber
# de VS Code, qui ne sait pas lire les définitions d'étapes écrites en bash : il
# lui redéclare les phrases de tests/steps/*.steps.sh dans un format qu'elle
# comprend, ce qui supprime les avertissements « Undefined step » et active
# l'autocomplétion des étapes.
#
# Les vraies définitions sont dans tests/steps/*.steps.sh.
# Après y avoir ajouté une phrase : ./tests/steps/generate_vscode_glue.sh


def given(expression):
    """Décorateur factice : seule l'extension Cucumber lit ce fichier."""

    def decorate(function):
        return function

    return decorate


@given("un projet git initialisé pour jgit")
def step_projet_git(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("je lance {string}")
def step_lance_commande(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("je lance {string} et que je réponds aux questions :")
def step_lance_commande_interactive(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("je commite le fichier {string} contenant {string} avec le message {string}")
def step_commite_fichier(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("je pousse la branche courante")
def step_pousse_branche_courante(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("je me place sur la branche {string}")
def step_checkout(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la PR de {string} est squash-mergée sur GitHub avec le message {string}")
def step_squash_merge_pr(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la branche {string} est supprimée sur GitHub")
def step_github_supprime_branche(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le client gh échoue pour les commandes {string}")
def step_github_en_echec(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("jgit se termine sans erreur")
def step_jgit_ok(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("jgit se termine en erreur")
def step_jgit_ko(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la sortie contient {string}")
def step_sortie_contient(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la sortie ne contient pas {string}")
def step_sortie_ne_contient_pas(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la branche locale {string} existe")
def step_branche_locale_existe(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la branche locale {string} n'existe pas")
def step_branche_locale_absente(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la branche distante {string} existe")
def step_branche_distante_existe(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la branche distante {string} n'existe pas")
def step_branche_distante_absente(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("je suis sur la branche {string}")
def step_branche_courante(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le tag {string} existe sur le remote")
def step_tag_existe(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le fichier {string} existe sur la branche distante {string}")
def step_fichier_present(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le fichier {string} n'existe pas sur la branche distante {string}")
def step_fichier_absent(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le fichier {string} de la branche distante {string} contient {string}")
def step_fichier_contient(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le fichier {string} existe dans le tag {string}")
def step_fichier_dans_tag(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le dernier commit de {string} contient {string}")
def step_dernier_commit_contient(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("l'historique de {string} contient {string}")
def step_historique_contient(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("GitHub a reçu {string}")
def step_github_a_recu(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("GitHub n'a pas reçu {string}")
def step_github_na_pas_recu(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("GitHub a reçu exactement {int} appels")
def step_github_nombre_appels(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("je modifie le fichier {string} avec {string}")
def step_modifie_fichier(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("je crée la branche locale {string}")
def step_cree_branche_locale(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("je crée la branche locale {string} depuis {string}")
def step_cree_branche_locale_depuis(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("je supprime la branche locale {string}")
def step_supprime_branche_locale(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("je merge la branche {string} dans la branche courante")
def step_merge_branche(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le dépôt n'a plus de remote")
def step_sans_remote(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le tag {string} est supprimé partout")
def step_supprime_tag(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("un autre développeur pousse le fichier {string} contenant {string} sur la branche {string} avec le message {string}")
def step_autre_dev_pousse(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("je note l'état de la branche distante {string}")
def step_note_etat_branche_distante(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la branche distante {string} est inchangée")
def step_branche_distante_inchangee(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la branche distante {string} a changé")
def step_branche_distante_modifiee(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("l'historique local de {string} contient {string}")
def step_historique_local_contient(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("l'historique local de {string} ne contient pas {string}")
def step_historique_local_ne_contient_pas(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le dernier commit local de {string} contient {string}")
def step_dernier_commit_local(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("l'historique de {string} ne contient pas {string}")
def step_historique_ne_contient_pas(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la branche distante {string} a {int} commits d'avance sur {string}")
def step_nombre_commits_distants(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la branche locale {string} a {int} commits d'avance sur {string}")
def step_nombre_commits_locaux(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("je récupère les nouveautés du remote")
def step_fetch(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le tag {string} n'existe pas sur le remote")
def step_tag_absent(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le fichier de travail {string} contient {string}")
def step_fichier_travail_contient(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("l'espace de travail est propre")
def step_espace_propre(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("l'espace de travail contient encore mes modifications")
def step_espace_sale(context):
    """Définie dans tests/steps/jgit.steps.sh."""
