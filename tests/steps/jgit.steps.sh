#!/bin/bash
#
# Definitions d'etapes pour les fichiers .feature.
#
# Chaque phrase est declaree avec step_def, les valeurs entre guillemets du
# fichier .feature etant passees en arguments a la fonction bash correspondante.
# Pour ecrire un nouveau scenario, on reutilise ces phrases ; on n'ajoute du
# bash que lorsqu'une phrase manque.

###############################################
#            Contexte
###############################################

step_projet_git() {
    sandbox_create
}
step_def "un projet git initialisé pour jgit" step_projet_git

###############################################
#            Actions : jgit
###############################################

# Decoupe "jgit feature start TEST-123" en arguments pour run_jgit.
jgit_args_from_command() {
    local command="$1"
    JGIT_ARGS=()
    local word
    local index=0
    for word in $command; do
        if [[ $index -eq 0 && "$word" == "jgit" ]]; then
            index=1
            continue
        fi
        JGIT_ARGS[${#JGIT_ARGS[@]}]="$word"
        index=$((index + 1))
    done
}

step_lance_commande() {
    jgit_args_from_command "$1"
    # ${x[@]+…} : "jgit" tout court se lance sans le moindre argument.
    run_jgit ${JGIT_ARGS[@]+"${JGIT_ARGS[@]}"}
}
step_def "je lance {chaine}" step_lance_commande

# Variante pour le contrat --json : la sortie standard (le document) est
# capturee a part de la sortie d'erreur (les messages).
step_lance_commande_json() {
    jgit_args_from_command "$1"
    run_jgit_json ${JGIT_ARGS[@]+"${JGIT_ARGS[@]}"}
}
step_def "je lance {chaine} en lisant le JSON" step_lance_commande_json

# Variante interactive : le tableau fournit les questions attendues et les
# reponses a taper.
#
#   Quand je lance "jgit feature start TEST-1" et que je réponds aux questions :
#     | Souhaitez-vous continuer | y |
step_lance_commande_interactive() {
    local rows
    local row=1

    rows=$(step_table_row_count)
    if [[ "$rows" == "0" ]]; then
        assert_failed "scenario interactif" "aucune question fournie dans le tableau de l'etape"
    fi

    expect_reset
    while [[ $row -le $rows ]]; do
        expect_wait "$(step_table_cell "$row" 1)"
        expect_answer "$(step_table_cell "$row" 2)"
        row=$((row + 1))
    done

    jgit_args_from_command "$1"
    run_jgit_interactive ${JGIT_ARGS[@]+"${JGIT_ARGS[@]}"}
}
step_def "je lance {chaine} et que je réponds aux questions :" step_lance_commande_interactive

###############################################
#            Actions : le developpeur
###############################################

step_commite_fichier() {
    repo_commit_file "$1" "$2" "$3"
}
step_def "je commite le fichier {chaine} contenant {texte} avec le message {chaine}" step_commite_fichier

step_pousse_branche_courante() {
    repo_push_current_branch
    info "branche $(repo_current_branch) poussée"
}
step_def "je pousse la branche courante" step_pousse_branche_courante

step_checkout() {
    repo_git checkout --quiet "$1"
    info "bascule sur $1"
}
step_def "je me place sur la branche {chaine}" step_checkout

step_resout_conflit() {
    repo_resolve_file "$1" "$2"
}
step_def "je résous le conflit du fichier {chaine} avec {texte}" step_resout_conflit

step_marque_resolu() {
    repo_mark_resolved "$1"
}
step_def "je marque le fichier {chaine} résolu sans retirer les marqueurs" step_marque_resolu

###############################################
#            Actions : GitHub (simule)
###############################################

step_squash_merge_pr() {
    github_squash_merge_pr "$1" "$2"
}
step_def "la PR de {chaine} est squash-mergée sur GitHub avec le message {chaine}" step_squash_merge_pr

step_branches_non_standard() {
    repo_use_non_standard_branches "$1"
}
step_def "le projet utilise {chaine} au lieu de develop, master ou main" step_branches_non_standard

# jgit ne tourne que sur macOS et Linux (docs/05-portabilite.md). Le bac a sable
# place deja $SANDBOX/bin en tete du PATH : y deposer un faux `uname` suffit a
# faire croire a jgit qu'il tourne sur un autre systeme.
step_systeme_non_macos() {
    local systeme="${1:-Linux}"
    cat > "$SANDBOX/bin/uname" <<UNAME_MOCK
#!/bin/bash
# Faux uname : simule un autre systeme.
printf '%s\n' "$systeme"
UNAME_MOCK
    chmod +x "$SANDBOX/bin/uname"
    info "uname simule : $systeme"
}
step_def "le système détecté est {chaine}" step_systeme_non_macos

step_clone_superficiel() {
    repo_reclone --depth 1 --no-single-branch
}
step_def "le dépôt de travail est un clone superficiel" step_clone_superficiel

step_clone_une_branche() {
    repo_reclone --single-branch --branch "$1"
}
step_def "le dépôt de travail est un clone de la seule branche {chaine}" step_clone_une_branche

step_sans_identite() {
    repo_remove_git_identity
}
step_def "aucune identité git n'est configurée" step_sans_identite

step_appel_par_lien() {
    jgit_use_symlink
}
step_def "jgit est installé par un lien symbolique" step_appel_par_lien

step_terminal_non_defini() {
    unset TERM
    info "variable TERM retiree"
}
step_def "le terminal n'est pas défini" step_terminal_non_defini

step_demo_ancien_format() {
    # shellcheck disable=SC2086
    github_create_legacy_demo "$1" "$2" true $3
}
step_def "une démo à l'ancien format {chaine} basée sur {chaine} contient les tickets {chaine}" step_demo_ancien_format

step_demo_ancien_format_sans_base() {
    # shellcheck disable=SC2086
    github_create_legacy_demo "$1" develop false $2
}
step_def "une démo à l'ancien format {chaine} sans base enregistrée contient les tickets {chaine}" step_demo_ancien_format_sans_base

step_pr_livree() {
    github_deliver_pr "$1" "$2"
}
step_def "la PR de {chaine} est livrée dans {chaine}" step_pr_livree

step_github_supprime_branche() {
    github_delete_branch "$1"
}
step_def "la branche {chaine} est supprimée sur GitHub" step_github_supprime_branche

step_github_renomme_pr() {
    github_rename_pr "$1" "$2"
}
step_def "la PR de {chaine} s'intitule {chaine} sur GitHub" step_github_renomme_pr

step_ancien_ticket() {
    github_create_old_ticket "$1" "$2" "$3" "$4"
}
step_def "un ancien ticket {chaine} parti de {chaine}, sans branche d'origine enregistrée, ajoute le fichier {chaine} contenant {texte}" step_ancien_ticket

step_github_en_echec() {
    export JGIT_GH_FAIL="$1"
    info "le client gh echouera pour : $1"
}
step_def "le client gh échoue pour les commandes {chaine}" step_github_en_echec

###############################################
#            Verifications : resultat de jgit
###############################################

step_jgit_ok() {
    assert_jgit_success
}
step_def "jgit se termine sans erreur" step_jgit_ok

step_jgit_ko() {
    assert_jgit_failure
}
step_def "jgit se termine en erreur" step_jgit_ko

# util check_rebase ne repond pas par oui ou non mais par un code : 0 a jour,
# 2 en retard mais rebasable, 3 en retard avec conflits.
step_jgit_code() {
    assert_jgit_exit_code "$1"
}
step_def "jgit se termine avec le code {nombre}" step_jgit_code

step_sortie_contient() {
    assert_jgit_output_contains "$1"
}
step_def "la sortie contient {chaine}" step_sortie_contient

step_sortie_ne_contient_pas() {
    assert_jgit_output_not_contains "$1"
}
step_def "la sortie ne contient pas {chaine}" step_sortie_ne_contient_pas

step_sortie_sans_couleur() {
    assert_jgit_output_plain
}
step_def "la sortie ne contient aucune séquence de couleur" step_sortie_sans_couleur

###############################################
#            Verifications : document JSON
###############################################

step_json_unique() {
    assert_json_document
}
step_def "la sortie standard est un unique document JSON" step_json_unique

step_json_egal() {
    assert_json_equals "$1" "$2"
}
step_def "le JSON a {chaine} égal à {texte}" step_json_egal

step_json_contient() {
    local actual
    actual=$(json_value_at "$1") || exit 1
    assert_contains "$actual" "$2" "JSON $1 contient [$2]"
}
step_def "le JSON a {chaine} qui contient {chaine}" step_json_contient

step_json_nombre() {
    assert_json_equals "$1" "$2"
    assert_json_type "$1" number
}
step_def "le JSON a {chaine} égal au nombre {nombre}" step_json_nombre

step_json_vrai() {
    assert_json_equals "$1" true
}
step_def "le JSON a {chaine} vrai" step_json_vrai

step_json_faux() {
    assert_json_equals "$1" false
}
step_def "le JSON a {chaine} faux" step_json_faux

step_json_nul() {
    assert_json_type "$1" null
}
step_def "le JSON a {chaine} nul" step_json_nul

step_json_longueur() {
    assert_json_length "$1" "$2"
}
step_def "la liste JSON {chaine} contient {nombre} éléments" step_json_longueur

step_json_absent() {
    assert_json_missing "$1"
}
step_def "le JSON n'a pas de {chaine}" step_json_absent

###############################################
#            Verifications : demos
###############################################

# Le tableau liste les tickets attendus, un par ligne, dans l'ordre.
step_demo_tickets() {
    local rows row=1 expected=""

    rows=$(step_table_row_count)
    while [[ $row -le $rows ]]; do
        expected="$expected$(step_table_cell "$row" 1)"$'\n'
        row=$((row + 1))
    done
    assert_remote_demo_tickets "$1" "${expected%$'\n'}"
}
step_def "la démo distante {chaine} contient dans l'ordre les tickets :" step_demo_tickets

step_demo_sans_ticket() {
    assert_remote_demo_tickets "$1" ""
}
step_def "la démo distante {chaine} ne contient aucun ticket" step_demo_sans_ticket

###############################################
#            Verifications : operation en pause
###############################################

step_operation_en_pause() {
    assert_operation_paused
}
step_def "une opération jgit est en pause" step_operation_en_pause

step_aucune_copie_temporaire() {
    assert_no_extra_worktree
}
step_def "aucune copie de travail temporaire ne reste" step_aucune_copie_temporaire

step_aucune_operation_en_pause() {
    assert_no_operation_paused
}
step_def "aucune opération jgit n'est en pause" step_aucune_operation_en_pause

###############################################
#            Verifications : branches
###############################################

step_branche_locale_existe() {
    assert_local_branch_exists "$1"
}
step_def "la branche locale {chaine} existe" step_branche_locale_existe

step_branche_locale_absente() {
    assert_local_branch_missing "$1"
}
step_def "la branche locale {chaine} n'existe pas" step_branche_locale_absente

step_branche_distante_existe() {
    assert_remote_branch_exists "$1"
}
step_def "la branche distante {chaine} existe" step_branche_distante_existe

step_branche_distante_absente() {
    assert_remote_branch_missing "$1"
}
step_def "la branche distante {chaine} n'existe pas" step_branche_distante_absente

step_branche_courante() {
    assert_current_branch "$1"
}
step_def "je suis sur la branche {chaine}" step_branche_courante

step_tag_existe() {
    assert_remote_tag_exists "$1"
}
step_def "le tag {chaine} existe sur le remote" step_tag_existe

###############################################
#            Verifications : contenu
###############################################

step_fichier_present() {
    assert_remote_file_exists "$2" "$1"
}
step_def "le fichier {chaine} existe sur la branche distante {chaine}" step_fichier_present

step_fichier_absent() {
    assert_remote_file_missing "$2" "$1"
}
step_def "le fichier {chaine} n'existe pas sur la branche distante {chaine}" step_fichier_absent

step_fichier_contient() {
    assert_remote_file_content "$2" "$1" "$3"
}
step_def "le fichier {chaine} de la branche distante {chaine} contient {texte}" step_fichier_contient

step_fichier_dans_tag() {
    assert_tag_file_exists "$2" "$1"
}
step_def "le fichier {chaine} existe dans le tag {chaine}" step_fichier_dans_tag

step_dernier_commit_contient() {
    assert_commit_subject_contains "refs/heads/$1" "$2"
}
step_def "le dernier commit de {chaine} contient {chaine}" step_dernier_commit_contient

step_historique_contient() {
    assert_remote_log_contains "refs/heads/$1" "$2"
}
step_def "l'historique de {chaine} contient {chaine}" step_historique_contient

###############################################
#            Verifications : branche d'origine
###############################################

step_locale_partie_de() {
    assert_local_based_on "$1" "$2"
}
step_def "la branche locale {chaine} est partie de {chaine}" step_locale_partie_de

step_distante_partie_de() {
    assert_remote_based_on "$1" "$2"
}
step_def "la branche distante {chaine} est partie de {chaine}" step_distante_partie_de

step_distante_sans_origine() {
    assert_remote_without_based_on "$1"
}
step_def "la branche distante {chaine} ne porte aucune branche d'origine" step_distante_sans_origine

step_origine_invisible() {
    assert_remote_subject_without_based_on "$1"
}
step_def "aucun sujet de commit de la branche distante {chaine} ne montre la branche d'origine" step_origine_invisible

###############################################
#            Verifications : appels a GitHub
###############################################

step_github_a_recu() {
    assert_gh_called "$1"
}
step_def "GitHub a reçu {chaine}" step_github_a_recu

step_github_na_pas_recu() {
    assert_gh_not_called "$1"
}
step_def "GitHub n'a pas reçu {chaine}" step_github_na_pas_recu

step_github_nombre_appels() {
    assert_gh_call_count "$1"
}
step_def "GitHub a reçu exactement {nombre} appels" step_github_nombre_appels

###############################################
#            Actions : preparation du depot
###############################################

step_modifie_fichier() {
    repo_write_file "$1" "$2"
}
step_def "je modifie le fichier {chaine} avec {texte}" step_modifie_fichier

step_cree_branche_locale() {
    repo_create_local_branch "$1"
}
step_def "je crée la branche locale {chaine}" step_cree_branche_locale

step_cree_branche_locale_depuis() {
    repo_create_local_branch "$1" "$2"
}
step_def "je crée la branche locale {chaine} depuis {chaine}" step_cree_branche_locale_depuis

step_supprime_branche_locale() {
    repo_delete_local_branch "$1"
}
step_def "je supprime la branche locale {chaine}" step_supprime_branche_locale

step_merge_branche() {
    repo_merge_branch "$1"
}
step_def "je merge la branche {chaine} dans la branche courante" step_merge_branche

step_sans_remote() {
    repo_remove_remote
}
step_def "le dépôt n'a plus de remote" step_sans_remote

step_supprime_tag() {
    repo_delete_tag "$1"
}
step_def "le tag {chaine} est supprimé partout" step_supprime_tag

###############################################
#            Actions : GitHub (suite)
###############################################

step_autre_dev_pousse() {
    github_commit_file "$3" "$1" "$2" "$4"
}
step_def "un autre développeur pousse le fichier {chaine} contenant {texte} sur la branche {chaine} avec le message {chaine}" step_autre_dev_pousse

step_personne_pousse() {
    github_commit_file_as "$1" "$4" "$2" "$3" "$5"
}
step_def "{chaine} pousse le fichier {chaine} contenant {texte} sur la branche {chaine} avec le message {chaine}" step_personne_pousse

step_note_etat_branche_distante() {
    remote_snapshot_save "$1"
}
step_def "je note l'état de la branche distante {chaine}" step_note_etat_branche_distante

###############################################
#            Verifications : etat du remote
###############################################

step_branche_distante_inchangee() {
    assert_remote_branch_unchanged "$1"
}
step_def "la branche distante {chaine} est inchangée" step_branche_distante_inchangee

step_branche_distante_avance_rapide() {
    assert_remote_branch_fast_forwarded "$1"
}
step_def "la branche distante {chaine} a avancé sans réécriture" step_branche_distante_avance_rapide

step_branche_distante_modifiee() {
    assert_remote_branch_changed "$1"
}
step_def "la branche distante {chaine} a changé" step_branche_distante_modifiee

###############################################
#            Verifications : historique local
###############################################

step_historique_local_contient() {
    assert_local_log_contains "$1" "$2"
}
step_def "l'historique local de {chaine} contient {chaine}" step_historique_local_contient

step_historique_local_ne_contient_pas() {
    assert_local_log_not_contains "$1" "$2"
}
step_def "l'historique local de {chaine} ne contient pas {chaine}" step_historique_local_ne_contient_pas

step_dernier_commit_local() {
    assert_local_commit_subject_contains "$1" "$2"
}
step_def "le dernier commit local de {chaine} contient {chaine}" step_dernier_commit_local

step_historique_ne_contient_pas() {
    assert_remote_log_not_contains "refs/heads/$1" "$2"
}
step_def "l'historique de {chaine} ne contient pas {chaine}" step_historique_ne_contient_pas

step_nombre_commits_distants() {
    assert_remote_commit_count_since "$1" "$3" "$2"
}
step_def "la branche distante {chaine} a {nombre} commits d'avance sur {chaine}" step_nombre_commits_distants

step_nombre_commits_locaux() {
    assert_local_commit_count_since "$1" "$3" "$2"
}
step_def "la branche locale {chaine} a {nombre} commits d'avance sur {chaine}" step_nombre_commits_locaux

step_fetch() {
    repo_git fetch --quiet origin
    info "remote recupere dans le depot de travail"
}
step_def "je récupère les nouveautés du remote" step_fetch

# Rapatrie une branche du serveur en local, telle qu'elle est a cet instant.
# C'est la seule facon realiste d'avoir une branche __PR__ en local : on la
# recupere depuis origin, avec son commit d'initialisation et son historique.
# On ne la recree jamais a la main.
step_recupere_branche_en_local() {
    repo_git fetch --quiet origin "$1:$1"
    info "branche $1 rapatriee depuis origin"
}
step_def "je récupère la branche distante {chaine} en local" step_recupere_branche_en_local

step_tag_absent() {
    assert_remote_tag_missing "$1"
}
step_def "le tag {chaine} n'existe pas sur le remote" step_tag_absent

###############################################
#            Verifications : espace de travail
###############################################

step_fichier_travail_contient() {
    assert_worktree_file_content "$1" "$2"
}
step_def "le fichier de travail {chaine} contient {texte}" step_fichier_travail_contient

step_espace_propre() {
    assert_worktree_clean
}
step_def "l'espace de travail est propre" step_espace_propre

step_espace_sale() {
    assert_worktree_dirty
}
step_def "l'espace de travail contient encore mes modifications" step_espace_sale
