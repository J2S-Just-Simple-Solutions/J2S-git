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

@given("je lance {string} en lisant le JSON")
def step_lance_commande_json(context):
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

@given("je résous le conflit du fichier {string} avec {string}")
def step_resout_conflit(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("je marque le fichier {string} résolu sans retirer les marqueurs")
def step_marque_resolu(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la PR de {string} est squash-mergée sur GitHub avec le message {string}")
def step_squash_merge_pr(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le projet utilise {string} au lieu de develop, master ou main")
def step_branches_non_standard(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le système détecté est {string}")
def step_systeme_non_macos(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le dépôt de travail est un clone superficiel")
def step_clone_superficiel(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le dépôt de travail est un clone de la seule branche {string}")
def step_clone_une_branche(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("aucune identité git n'est configurée")
def step_sans_identite(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("jgit est installé par un lien symbolique")
def step_appel_par_lien(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le terminal n'est pas défini")
def step_terminal_non_defini(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("une démo à l'ancien format {string} basée sur {string} contient les tickets {string}")
def step_demo_ancien_format(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("une démo à l'ancien format {string} sans base enregistrée contient les tickets {string}")
def step_demo_ancien_format_sans_base(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la PR de {string} est livrée dans {string}")
def step_pr_livree(context):
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

@given("jgit se termine avec le code {int}")
def step_jgit_code(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la sortie contient {string}")
def step_sortie_contient(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la sortie ne contient pas {string}")
def step_sortie_ne_contient_pas(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la sortie ne contient aucune séquence de couleur")
def step_sortie_sans_couleur(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la sortie standard est un unique document JSON")
def step_json_unique(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le JSON a {string} égal à {string}")
def step_json_egal(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le JSON a {string} qui contient {string}")
def step_json_contient(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le JSON a {string} égal au nombre {int}")
def step_json_nombre(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le JSON a {string} vrai")
def step_json_vrai(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le JSON a {string} faux")
def step_json_faux(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le JSON a {string} nul")
def step_json_nul(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la liste JSON {string} contient {int} éléments")
def step_json_longueur(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("le JSON n'a pas de {string}")
def step_json_absent(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la démo distante {string} contient dans l'ordre les tickets :")
def step_demo_tickets(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la démo distante {string} ne contient aucun ticket")
def step_demo_sans_ticket(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("une opération jgit est en pause")
def step_operation_en_pause(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("aucune opération jgit n'est en pause")
def step_aucune_operation_en_pause(context):
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

@given("la branche locale {string} est partie de {string}")
def step_locale_partie_de(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la branche distante {string} est partie de {string}")
def step_distante_partie_de(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("la branche distante {string} ne porte aucune branche d'origine")
def step_distante_sans_origine(context):
    """Définie dans tests/steps/jgit.steps.sh."""

@given("aucun sujet de commit de la branche distante {string} ne montre la branche d'origine")
def step_origine_invisible(context):
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

@given("la branche distante {string} a avancé sans réécriture")
def step_branche_distante_avance_rapide(context):
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

@given("je récupère la branche distante {string} en local")
def step_recupere_branche_en_local(context):
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
