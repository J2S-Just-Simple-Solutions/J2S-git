#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"

# Annule un rebase interrompu et restaure l'état local d'avant la commande :
# abandon du cherry-pick, suppression des branches temporaires et retour à
# l'historique initial de la branche de travail si un squash avait été appliqué.
# Le remote n'ayant pas encore été poussé à ce stade, il reste intact.
abort_rebase() {
    local branch="$1"
    local reference_branch="$2"
    local branch_rebase="$3"
    local branch_PR_rebase="$4"
    local original_head="$5"
    local squash_done="$6"

    git cherry-pick --abort >/dev/null 2>&1
    switch_branch "$reference_branch" discard

    if [[ "$squash_done" == true ]]; then
        echo "Restauration de l'historique initial de $branch (annulation du squash)."
        switch_branch "$branch" discard
        git reset --hard "$original_head" --quiet
        switch_branch "$reference_branch" discard
    fi

    git branch -D "$branch_rebase" --quiet 2>/dev/null
    git branch -D "$branch_PR_rebase" --quiet 2>/dev/null

    printf "%sLe rebase a été annulé, l'état local est restauré et le remote n'a pas été modifié.%s\n" \
        "$(jgit_tput setaf 1)" "$(jgit_tput sgr0)"
}

feature_rebase() {
    local feature_type=$1
    local feature_name=$2
    local BASED_ON=$3
    local branch=$1/$feature_name
    local branch_PR=$prefix_PR$branch
    local branch_rebase="jgit_rebase_"$branch
    local branch_PR_rebase="jgit_rebase_"$branch_PR

    current_date=`date '+%s'`

    jgit_fetch_once || exit_safe 1

    git branch -D "$branch_rebase" --quiet 2>/dev/null
    git branch -D $branch_PR_rebase --quiet 2>/dev/null

    # Une fois la PR squash-mergée, la branche de travail ne sert plus : elle a
    # pu être supprimée, et seule la branche de PR reste à remettre à jour.
    local work_exists=false
    if branch_exists "$branch"; then
        work_exists=true
        switch_branch "$branch"
    elif ! branch_exists "$branch_PR"; then
        jgit_fail branch_not_found "$JGIT_EXIT_ERROR" \
            "La branche $branch n'existe pas (ni en local ni sur $j2s_remote)."
    fi
    switch_branch "$branch_PR"

    local relaunch="jgit $feature_type rebase $feature_name"
    local base_provenance="reference"

    if [[ -n "$BASED_ON" ]]; then
        reference_branch="$BASED_ON"
        base_provenance="option"
    else
        if ! reference_branch=$(get_reference_branch "$feature_type"); then
            exit_safe 1
        fi

        # Une feature partie d'une démo ou d'une release n'a rien à faire sur
        # develop sous prétexte que c'est la référence du projet : jusqu'ici le
        # rebase l'y envoyait sans rien dire. La branche d'origine enregistrée à
        # la création est donc proposée, et comme c'est la réponse par défaut,
        # c'est aussi celle que --no-interaction applique.
        local recorded_base
        if [[ $work_exists == true ]]; then
            recorded_base=$(read_based_on "$branch" "$branch") || recorded_base=""
        else
            recorded_base=$(read_based_on "$branch_PR" "$branch_PR") || recorded_base=""
        fi

        if [[ -n "$recorded_base" ]]; then
            # La base enregistrée est une valeur par défaut comme une autre : on
            # la contrôle avant de la proposer, sinon la question porterait sur
            # une branche disparue et la réponse par défaut mènerait droit dans
            # le mur.
            if ! ensure_base_branch "$recorded_base" "record" "$feature_type" "$relaunch" "$branch"; then
                printf "\nPour retrouver d'où part la branche :\n" >&2
                printf "  jgit util check_rebase --from %s\n" "$branch" >&2
                exit_safe 1
            fi

            if [[ "$recorded_base" != "$reference_branch" ]]; then
                printf "%sLa branche %s%s%s%s est partie de %s%s%s%s, et non de la référence du projet %s%s%s.%s\n" \
                    "$(jgit_tput setaf 2)" "$(jgit_tput setaf 1)" "$branch" "$(jgit_tput sgr0)" "$(jgit_tput setaf 2)" \
                    "$(jgit_tput setaf 1)" "$recorded_base" "$(jgit_tput sgr0)" "$(jgit_tput setaf 2)" \
                    "$(jgit_tput setaf 1)" "$reference_branch" "$(jgit_tput setaf 2)" "$(jgit_tput sgr0)"
                if confirm_action "Rebaser sur $recorded_base ?" "y"; then
                    reference_branch="$recorded_base"
                    base_provenance="record"
                fi
            fi
        fi
    fi

    # Le contrôle final porte sur la valeur retenue, d'où qu'elle vienne : une
    # saisie --based-on erronée et une référence de projet introuvable donnent
    # le même refus.
    if ! ensure_base_branch "$reference_branch" "$base_provenance" "$feature_type" "$relaunch" "$branch"; then
        exit_safe 1
    fi

    # La branche de PR est celle qui sera reconstruite, et publiée : sans elle
    # sur le serveur, il n'y a rien à faire.
    if ! git show-ref --verify --quiet "refs/remotes/$j2s_remote/$branch_PR"; then
        jgit_fail branch_not_on_remote "$JGIT_EXIT_ERROR" \
            "La branche $branch_PR n'existe pas sur $j2s_remote : il n'y a rien à rebaser."
    fi

    # Les commits de la branche de PR depuis son dernier commit d'init : le
    # commit d'init seul tant que la PR n'a pas été validée, suivi d'un commit
    # par « squash and merge » ensuite.
    last_init_commit=$(get_last_commit_with_pattern "$prefix_init_commit $feature_type")
    if [ -z "$last_init_commit" ]; then
        echo "Aucun commit trouvé avec le pattern jgit"
        exit_safe 1
    fi
    local commits_on_PR=($(list_commits_since "$last_init_commit"))

    ##################################################
    # Où en est le ticket ?
    #   work : en cours de développement, la branche de travail descend de la
    #          branche de PR : les deux branches sont reconstruites ;
    #   pr   : la PR a été squash-mergée : seule la branche de PR est
    #          reconstruite, la branche de travail (même code) est supprimée.
    ##################################################
    local mode="work"
    local delete_work=false

    if [[ $work_exists == true ]] && is_fast_forward "$branch_PR" "$branch"; then
        mode="work"
    elif [[ ${#commits_on_PR[@]} -le 1 ]]; then
        if [[ $work_exists == true ]]; then
            jgit_fail history_diverged "$JGIT_EXIT_ERROR" \
                "La branche $branch ne descend plus de $branch_PR, alors que la PR n'a jamais été validée : l'une des deux a été réécrite à la main." \
                "jgit ne choisit pas entre deux historiques : réconciliez-les, puis relancez."
        fi
        jgit_fail pr_not_validated "$JGIT_EXIT_REFUSED" \
            "La branche $branch n'existe plus et la PR n'a jamais été validée : $branch_PR ne contient que son commit d'initialisation, il n'y a rien à rebaser." \
            "Si le ticket est abandonné, $branch_PR ne sert plus à rien : git push $j2s_remote --delete $branch_PR"
    elif [[ $work_exists == true ]] && ! branches_have_same_code "$branch" "$branch_PR"; then
        jgit_fail pr_validated_new_work "$JGIT_EXIT_REFUSED" \
            "La PR de $branch a été validée (squash and merge), mais $branch contient du code absent de $branch_PR : du travail ajouté après la validation, qui n'a pas été relu. Rien n'a été modifié." \
            "Pour voir ce travail : git diff $branch_PR $branch"
    else
        mode="pr"
        delete_work=$work_exists
    fi

    if [[ $mode == "work" ]] && ! git show-ref --verify --quiet "refs/remotes/$j2s_remote/$branch"; then
        jgit_fail branch_not_on_remote "$JGIT_EXIT_ERROR" \
            "La branche $branch n'existe pas sur $j2s_remote : poussez-la, puis relancez."
    fi

    # Déjà mergée dans sa branche finale : il n'y a plus rien à rebaser, et ses
    # branches ne servent plus.
    if [[ $mode == "pr" ]] && feature_rebase_is_delivered "$branch_PR" "$reference_branch"; then
        feature_rebase_delivered "$branch" "$branch_PR" "$reference_branch" "$delete_work"
        return 0
    fi

    local commits=()
    if [[ $mode == "work" ]]; then
        switch_branch "$branch"
        # Les commits de la branche de travail absents de la branche de PR, du plus ancien au plus récent.
        commits=($(git rev-list --reverse "$branch_PR..$branch"))
    fi

    # On ne peut pas automatiser un rebase s'il y a un commit de fusion, on refuse l'action
    for commit in "${commits_on_PR[@]}" "${commits[@]}"; do
        if is_merge_commit "$commit"; then
            printf "${C_RED}Le commit ${C_GREEN}%s${C_RED} est un commit de fusion. On ne peut pas rebase automatiquement un commit de fusion.${C_RESET}\n" "$commit"
            printf "Il ne faut pas mélanger rebase et merge, la prochaine fois merci de ne faire que des rebases ;).\nPensez à toujours squash and merge vos PRs\n"

            exit_safe 1
        fi
    done

    ##################################################
    # Validation visuelle + confirmation utilisateur
    ##################################################

    if [[ $mode == "pr" ]]; then
        printf "%sLa PR de %s%s%s%s a été validée : seule la branche %s%s%s%s est reconstruite, pour que son merge dans %s%s%s%s passe sans conflit.%s\n" \
        "$(jgit_tput setaf 2)" "$(jgit_tput setaf 1)" "$branch" "$(jgit_tput sgr0)" "$(jgit_tput setaf 2)" \
        "$(jgit_tput setaf 1)" "$branch_PR" "$(jgit_tput sgr0)" "$(jgit_tput setaf 2)" \
        "$(jgit_tput setaf 1)" "$reference_branch" "$(jgit_tput sgr0)" "$(jgit_tput setaf 2)" \
        "$(jgit_tput sgr0)"
        if [[ $delete_work == true ]]; then
            printf "%sLa branche de travail %s%s%s%s a exactement le même code : elle ne sert plus, elle sera supprimée en local et sur le serveur.%s\n" \
            "$(jgit_tput setaf 2)" "$(jgit_tput setaf 1)" "$branch" "$(jgit_tput sgr0)" "$(jgit_tput setaf 2)" "$(jgit_tput sgr0)"
        fi
        if [[ $JGIT_SQUASH == true ]]; then
            echo "--squash est sans effet ici : les commits validés sont repris tels quels."
        fi
        printf "Liste des commits repris :\n"
        for commit in "${commits_on_PR[@]}"; do
            get_commit_info "$commit"
        done
    elif [[ ${#commits_on_PR[@]} -gt 1 ]]; then
        # On est dans le cas d'une PR qui déjà été mergée puis réouverte, on affiche la liste complète pour bien la valider visuellement.
        printf "%sLes commits suivants sont présents sur la branche %s%s%s actuelle mais pas sur la branche %s%s%s. Il seront repris sur la future branche %s%s%s%s\n" \
        "$(jgit_tput setaf 2)"  \
        "$(jgit_tput setaf 1)" "$branch_PR" "$(jgit_tput setaf 2)" \
        "$(jgit_tput setaf 1)" "$reference_branch" "$(jgit_tput setaf 2)" \
        "$(jgit_tput setaf 1)" "$branch_PR" "$(jgit_tput setaf 2)" \
        "$(jgit_tput sgr0)"
        printf "Liste des commits repris :\n"
        for commit in "${commits_on_PR[@]}"; do
            get_commit_info "$commit"
        done
    fi

    ##################################################
    # Squash optionnel des commits de la branche de travail
    # Un seul commit à rebaser = un seul conflit à résoudre.
    ##################################################
    local original_head=""
    if [[ $mode == "work" ]]; then
        original_head=$(git rev-parse HEAD)
    elif [[ $work_exists == true ]]; then
        original_head=$(git rev-parse "$branch")
    fi
    local squash_done=false

    local squash_base_index
    squash_base_index=$(find_last_init_commit_index "${commits[@]}")

    if [[ $squash_base_index -ge 0 ]]; then
        local squashable_count=$(( ${#commits[@]} - squash_base_index - 1 ))

        if [[ $squashable_count -le 1 ]]; then
            if [[ $JGIT_SQUASH == true ]]; then
                echo "Rien à squasher : la branche $branch ne contient qu'un seul commit de travail."
            fi
        else
            local do_squash=$JGIT_SQUASH

            if [[ $do_squash == false && $squashable_count -gt $JGIT_SQUASH_THRESHOLD ]]; then
                # Simple rappel de l'existence de --squash : sans demande explicite,
                # le rebase reprend l'historique complet.
                printf "%sLa branche %s%s%s%s contient %s commits de travail.%s\n" \
                    "$(jgit_tput setaf 2)" "$(jgit_tput setaf 1)" "$branch" "$(jgit_tput sgr0)" "$(jgit_tput setaf 2)" "$squashable_count" "$(jgit_tput sgr0)"
                printf "%sLes squasher en un seul commit (option %s--squash%s%s) limiterait les conflits à résoudre à un seul.%s\n" \
                    "$(jgit_tput setaf 2)" "$(jgit_tput setaf 1)" "$(jgit_tput sgr0)" "$(jgit_tput setaf 2)" "$(jgit_tput sgr0)"

                if confirm_action "Souhaitez-vous squasher ces commits avant le rebase ?" "n"; then
                    do_squash=true
                fi
            fi

            if [[ $do_squash == true ]]; then
                if ! squash_commits_after "${commits[$squash_base_index]}" "${commits[$((squash_base_index + 1))]}"; then
                    git reset --hard "$original_head" --quiet
                    exit_safe 1
                fi
                squash_done=true
                # L'historique local vient d'être réécrit, on recalcule la liste des commits à reprendre.
                commits=($(git rev-list --reverse "$branch_PR..$branch"))
            fi
        fi
    fi

    if [[ $mode == "work" ]]; then
        printf "%sjgit va reprendre, dans l'ordre, tous les commits ci-dessous qui existe dans la branche locale %s%s%s\n" "$(jgit_tput setaf 2)" "$(jgit_tput setaf 1)" "$branch" "$(jgit_tput sgr0)"

        for commit in "${commits[@]}"; do
            get_commit_info "$commit"
        done
    fi

    printf "%sEn se basant sur la branche de référence distante %s%s%s\n" \
    "$(jgit_tput setaf 2)" "$(jgit_tput setaf 1)" "$reference_branch" "$(jgit_tput sgr0)"
    
    # Demander confirmation à l'utilisateur
    if ! confirm_action "Souhaitez-vous continuer ?" "y"; then
        echo "Opération annulée."
        if [[ $squash_done == true ]]; then
            echo "Annulation du squash : restauration de l'historique initial de $branch."
            git reset --hard "$original_head" --quiet
        fi
        exit_safe 1
    fi

    ###################################
    # Gestion du rebase en cherrypick
    ###################################
    # Tout ce qu'il faut pour mener le rebase à son terme est rangé dans les
    # variables OP_* : en cas de conflit avec --on-conflict pause, elles sont
    # enregistrées telles quelles, et « jgit feature continue » repart d'elles.
    OP_operation="feature_rebase"
    OP_type="$feature_type"
    OP_ticket="$feature_name"
    OP_target="$branch"
    OP_mode="$mode"
    OP_delete_work="$delete_work"
    OP_label="le rebase de $branch sur $reference_branch"
    OP_continue_command="jgit $feature_type continue $feature_name"
    OP_abort_command="jgit $feature_type abort $feature_name"
    OP_work_branch="$branch"
    OP_pr_branch="$branch_PR"
    OP_work_rebase="$branch_rebase"
    OP_pr_rebase="$branch_PR_rebase"
    OP_reference="$reference_branch"
    OP_original_head="$original_head"
    OP_original_head_pr=$(git rev-parse "$branch_PR")
    OP_squash_done="$squash_done"
    # Version serveur des deux branches au moment où on les a lues : le push
    # final ne les écrasera que si personne ne les a déplacées entre-temps.
    OP_lease_work=$(git rev-parse -q --verify "refs/remotes/$j2s_remote/$branch")
    OP_lease_pr=$(git rev-parse -q --verify "refs/remotes/$j2s_remote/$branch_PR")
    OP_phase="pr"
    OP_pending="${commits_on_PR[*]}"
    OP_pending_work="${commits[*]}"
    OP_head_before=""
    OP_done=0
    OP_total=$(( ${#commits_on_PR[@]} + ${#commits[@]} ))
    OP_return_branch="$current_branch"
    OP_stash="$stash"
    OP_branch=""
    # La reprise garde la conduite choisie au départ face aux conflits.
    OP_on_conflict=$(jgit_conflict_mode)

    # On met à jour la branche de référence par rapport au remote pour être bien à jour
    echo "Checkout and pull $reference_branch branch"
    switch_branch "$reference_branch"

    # rebase de la branche PR par application des commits déjà présents sur l'ancienne branche PR en cherry pick
    echo "Starting cherry picking on $branch_PR_rebase branch"
    switch_branch "$branch_PR_rebase" create

    feature_rebase_run
}

# Variables d'un rebase, enregistrées quand il se met en pause sur un conflit.
FEATURE_REBASE_STATE=(OP_operation OP_type OP_ticket OP_target OP_mode OP_delete_work OP_label
    OP_continue_command OP_abort_command OP_work_branch OP_pr_branch
    OP_work_rebase OP_pr_rebase OP_reference OP_original_head OP_original_head_pr
    OP_squash_done OP_lease_work OP_lease_pr OP_phase OP_pending OP_pending_work
    OP_head_before OP_done OP_total OP_return_branch OP_stash OP_branch
    OP_on_conflict)

# Déroule le rebase à partir de là où il en est (OP_phase) : branche de PR,
# puis branche de travail, puis publication. Appelé au premier passage comme
# à la reprise après un conflit.
feature_rebase_run() {
    # Les deux branches sont reconstruites sur la référence : les commits
    # d'init rejoués doivent désigner cette base, pas celle d'il y a trois
    # semaines. cherry_pick_commits s'en charge au moment où il les repose, et
    # chaque phase ne rejoue que les commits d'init de sa propre branche.
    JGIT_RESTAMP_BASED_ON="$OP_reference"

    if [[ "$OP_phase" == "pr" ]]; then
        JGIT_RESTAMP_BRANCH="$OP_pr_branch"
        # shellcheck disable=SC2086
        feature_rebase_replay $OP_pending

        # PR validée : il n'y a pas de branche de travail à reconstruire.
        if [[ "$OP_mode" == "pr" ]]; then
            JGIT_RESTAMP_BASED_ON=""
            JGIT_RESTAMP_BRANCH=""
            feature_rebase_publish_pr
            return 0
        fi

        OP_phase="work"
        OP_pending="$OP_pending_work"
        OP_pending_work=""

        # rebase de la branche principal par application de tous les commits en cherry pick
        echo "Starting cherry picking on $OP_work_rebase branch"
        switch_branch "$OP_work_rebase" create
    fi

    JGIT_RESTAMP_BRANCH="$OP_work_branch"
    # shellcheck disable=SC2086
    feature_rebase_replay $OP_pending

    JGIT_RESTAMP_BASED_ON=""
    JGIT_RESTAMP_BRANCH=""

    feature_rebase_publish
}

# Rejoue une liste de commits de la phase en cours et traite l'issue d'un
# conflit : pause enregistrée, abandon, ou annulation par le développeur.
feature_rebase_replay() {
    local commits=("$@")
    local status

    [[ ${#commits[@]} -gt 0 ]] || return 0

    cherry_pick_commits "${commits[@]}"
    status=$?

    case $status in
        0)
            OP_done=$((OP_done + ${#commits[@]}))
            OP_pending=""
            return 0
            ;;
        3)
            OP_done=$((OP_done + ${#commits[@]} - ${#REPLAY_PENDING[@]}))
            OP_pending="${REPLAY_PENDING[*]}"
            OP_head_before="$REPLAY_HEAD_BEFORE"
            OP_branch=$(git rev-parse --abbrev-ref HEAD)
            jgit_state_save "${FEATURE_REBASE_STATE[@]}"
            replay_pause_exit conflict "Conflit pendant $OP_label."
            ;;
    esac

    abort_rebase "$OP_work_branch" "$OP_reference" "$OP_work_rebase" "$OP_pr_rebase" "$OP_original_head" "$OP_squash_done"
    jgit_state_clear

    if [[ $status -eq 2 ]]; then
        replay_report_aborted_conflict "Conflit pendant $OP_label : le rebase a été annulé."
        exit_safe "$JGIT_EXIT_CONFLICT"
    fi

    jgit_error_set cancelled "Le rebase a été annulé à votre demande."
    exit_safe 1
}

# Remplace les branches historiques par les branches reconstruites, fait
# vérifier l'historique, puis publie les deux d'un seul geste.
feature_rebase_publish() {
    local branch="$OP_work_branch"
    local branch_PR="$OP_pr_branch"
    local reference_branch="$OP_reference"

    # On vient écraser les branches historiques par les branches que l'on vient de rebase
    switch_branch "$reference_branch"
    rename_branch "$OP_pr_rebase" "$branch_PR"
    rename_branch "$OP_work_rebase" "$branch"

    # À partir d'ici $branch et $branch_PR ont un historique réécrit : elles
    # divergent du serveur par construction, et c'est précisément ce qu'on
    # s'apprête à pousser en force. D'où le mode nosync.
    #
    # On propose à l'utlisateur de vérifier son arbre GIT avant de pusher en force sur le remote.
    switch_branch "$branch" nosync
    git_history_with_merges "$branch" "$reference_branch"

    if ! confirm_action "Confirmez-vous que le rebase s'est bien passé, les branches vont être push --force ?" "y"; then
        echo "les branches locales ne sont plus correctes ($branch et $branch_PR), elles vont être supprimées en local."
        jgit_state_clear
        switch_branch "$reference_branch"
        git branch -D $branch
        git branch -D $branch_PR
        echo "Pull de la branche $branch en local depuis Github."
        switch_branch "$branch"
        jgit_error_set cancelled "Le rebase n'a pas été publié : vous ne l'avez pas confirmé."
        exit_safe 1
    fi

    # Les deux branches partent ensemble (--atomic), et seulement si le serveur
    # est toujours dans l'état lu au départ (--force-with-lease explicite) : un
    # collègue qui a poussé entre-temps n'est jamais écrasé.
    if ! git push --atomic --set-upstream \
            --force-with-lease="refs/heads/$branch_PR:$OP_lease_pr" \
            --force-with-lease="refs/heads/$branch:$OP_lease_work" \
            "$j2s_remote" "$branch_PR" "$branch"; then
        feature_rebase_push_refused
    fi

    jgit_state_clear
    current_branch="$branch"
    clean_branches
    printf "%sRebase terminé avec succès%s\n" "$(jgit_tput setaf 2)" "$(jgit_tput sgr0)"
}

# Publication d'une PR validée : seule la branche de PR a été reconstruite. La
# branche de travail, qui n'a plus rien à apporter, est supprimée dans le même
# push : le serveur accepte les deux, ou aucun.
feature_rebase_publish_pr() {
    local branch="$OP_work_branch"
    local branch_PR="$OP_pr_branch"
    local reference_branch="$OP_reference"
    local question="Confirmez-vous que le rebase s'est bien passé, la branche $branch_PR va être push --force"

    switch_branch "$reference_branch"
    rename_branch "$OP_pr_rebase" "$branch_PR"

    switch_branch "$branch_PR" nosync
    git_history_with_merges "$branch_PR" "$reference_branch"

    if [[ "$OP_delete_work" == true ]]; then
        question="$question et $branch supprimée"
    fi

    if ! confirm_action "$question ?" "y"; then
        echo "La branche locale $branch_PR n'est plus correcte, elle va être supprimée en local."
        jgit_state_clear
        switch_branch "$reference_branch"
        git branch -D "$branch_PR" --quiet
        jgit_error_set cancelled "Le rebase n'a pas été publié : vous ne l'avez pas confirmé."
        exit_safe 1
    fi

    local leases=("--force-with-lease=refs/heads/$branch_PR:$OP_lease_pr")
    local refspecs=("$branch_PR")
    if [[ "$OP_delete_work" == true && -n "$OP_lease_work" ]]; then
        leases+=("--force-with-lease=refs/heads/$branch:$OP_lease_work")
        refspecs+=(":refs/heads/$branch")
    fi

    if ! git push --atomic "${leases[@]}" "$j2s_remote" "${refspecs[@]}"; then
        feature_rebase_push_refused
    fi

    jgit_state_clear
    switch_branch "$reference_branch" nosync
    if [[ "$OP_delete_work" == true ]]; then
        git branch -D "$branch" --quiet 2>/dev/null
        echo "La branche $branch a été supprimée."
    fi
    current_branch="$reference_branch"
    clean_branches
    printf "%sRebase terminé avec succès : %s%s%s%s peut être mergée dans %s%s%s%s.%s\n" \
        "$(jgit_tput setaf 2)" "$(jgit_tput setaf 1)" "$branch_PR" "$(jgit_tput sgr0)" "$(jgit_tput setaf 2)" \
        "$(jgit_tput setaf 1)" "$reference_branch" "$(jgit_tput sgr0)" "$(jgit_tput setaf 2)" "$(jgit_tput sgr0)"
}

# Vrai si la branche de PR est déjà entièrement mergée dans sa branche finale.
# La version du serveur fait foi, des deux côtés.
feature_rebase_is_delivered() {
    local branch_PR="$1"
    local reference_branch="$2"
    local target="refs/remotes/$j2s_remote/$reference_branch"

    git show-ref --verify --quiet "$target" || target="refs/heads/$reference_branch"
    git merge-base --is-ancestor "refs/remotes/$j2s_remote/$branch_PR" "$target" 2>/dev/null
}

# La PR est déjà mergée dans sa branche finale : rien à rebaser. Ses branches
# ne servent plus, on propose de les supprimer, en local et sur le serveur.
feature_rebase_delivered() {
    local branch="$1"
    local branch_PR="$2"
    local reference_branch="$3"
    local delete_work="$4"
    local lease_pr lease_work
    local leases=() refspecs=() names="$branch_PR"

    lease_pr=$(git rev-parse -q --verify "refs/remotes/$j2s_remote/$branch_PR")
    lease_work=$(git rev-parse -q --verify "refs/remotes/$j2s_remote/$branch")
    leases=("--force-with-lease=refs/heads/$branch_PR:$lease_pr")
    refspecs=(":refs/heads/$branch_PR")
    if [[ $delete_work == true ]]; then
        names="$branch_PR et $branch"
        if [[ -n "$lease_work" ]]; then
            leases+=("--force-with-lease=refs/heads/$branch:$lease_work")
            refspecs+=(":refs/heads/$branch")
        fi
    fi

    printf "%sLa branche %s%s%s%s est déjà mergée dans %s%s%s%s : il n'y a rien à rebaser.%s\n" \
        "$(jgit_tput setaf 2)" "$(jgit_tput setaf 1)" "$branch_PR" "$(jgit_tput sgr0)" "$(jgit_tput setaf 2)" \
        "$(jgit_tput setaf 1)" "$reference_branch" "$(jgit_tput sgr0)" "$(jgit_tput setaf 2)" "$(jgit_tput sgr0)"
    if [[ $delete_work == true ]]; then
        echo "La branche de travail $branch a le même code : elle ne sert plus non plus."
    fi

    if ! confirm_action "Supprimer $names, en local et sur le serveur ?" "y"; then
        echo "Rien n'a été supprimé."
        return 0
    fi

    current_branch="$reference_branch"
    switch_branch "$reference_branch"

    if ! git push --atomic "${leases[@]}" "$j2s_remote" "${refspecs[@]}"; then
        jgit_fail push_failed "$JGIT_EXIT_ERROR" \
            "La suppression de $names sur $j2s_remote a échoué : rien n'a été supprimé." \
            "Si quelqu'un y a poussé entre-temps, son travail est intact. Sinon, vérifiez votre accès au serveur puis relancez : jgit ${branch%%/*} rebase ${branch#*/}"
    fi

    git branch -D "$branch_PR" --quiet 2>/dev/null
    if [[ $delete_work == true ]]; then
        git branch -D "$branch" --quiet 2>/dev/null
    fi
    printf "%s%s supprimée(s).%s\n" "$(jgit_tput setaf 2)" "$names" "$(jgit_tput sgr0)"
}

# Le push a été refusé. Si le serveur a bougé, c'est qu'un collègue a poussé
# pendant le rebase : on remet les branches locales comme avant et on le dit.
feature_rebase_push_refused() {
    local branch="$OP_work_branch"
    local branch_PR="$OP_pr_branch"
    local moved=false

    jgit_state_clear

    # Retour à l'état d'avant le rebase : la reconstruction se refera sur la
    # version du serveur, au prochain lancement.
    switch_branch "$OP_reference" discard
    # Une PR validée n'a pas forcément de branche de travail à restaurer.
    if [[ -n "$OP_original_head" ]]; then
        git branch -f "$branch" "$OP_original_head" >/dev/null 2>&1
        current_branch="$branch"
    else
        current_branch="$OP_reference"
    fi
    git branch -f "$branch_PR" "$OP_original_head_pr" >/dev/null 2>&1

    git fetch --quiet "$j2s_remote" \
        "+refs/heads/$branch:refs/remotes/$j2s_remote/$branch" \
        "+refs/heads/$branch_PR:refs/remotes/$j2s_remote/$branch_PR" 2>/dev/null
    if [[ "$(git rev-parse -q --verify "refs/remotes/$j2s_remote/$branch")" != "$OP_lease_work" \
          || "$(git rev-parse -q --verify "refs/remotes/$j2s_remote/$branch_PR")" != "$OP_lease_pr" ]]; then
        moved=true
    fi

    if [[ $moved == true ]]; then
        jgit_fail lease_rejected "$JGIT_EXIT_LEASE" \
            "Quelqu'un a poussé sur $branch ou $branch_PR pendant le rebase : rien n'a été écrasé, rien n'a été poussé." \
            "Vos branches locales sont revenues à leur état d'avant. Relancez : jgit $OP_type rebase $OP_ticket"
    fi

    jgit_fail push_failed "$JGIT_EXIT_ERROR" \
        "La publication de $branch et $branch_PR a échoué : rien n'a été poussé." \
        "Vos branches locales sont revenues à leur état d'avant. Vérifiez votre accès au serveur puis relancez : jgit $OP_type rebase $OP_ticket"
}

# Charge l'opération en pause et vérifie qu'elle correspond à la commande.
#   feature_rebase_load_paused <type> <ticket>
feature_rebase_load_paused() {
    local feature_type="$1"
    local feature_name="$2"

    if ! jgit_state_exists; then
        jgit_fail no_operation_in_progress "$JGIT_EXIT_REFUSED" \
            "Aucune opération jgit n'est en pause dans ce dépôt : il n'y a rien à reprendre ni à annuler."
    fi

    jgit_state_load

    if [[ "$OP_operation" != "feature_rebase" || "$OP_type" != "$feature_type" || "$OP_ticket" != "$feature_name" ]]; then
        jgit_fail operation_mismatch "$JGIT_EXIT_REFUSED" \
            "L'opération en pause n'est pas celle-ci : c'est $OP_label." \
            "$OP_continue_command   (ou : $OP_abort_command)"
    fi

    local head_branch
    head_branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$head_branch" != "$OP_branch" ]]; then
        jgit_fail state_mismatch "$JGIT_EXIT_REFUSED" \
            "L'opération en pause travaille sur la branche $OP_branch, mais l'espace de travail est sur $head_branch." \
            "Revenez sur $OP_branch (git switch $OP_branch) puis relancez."
    fi

    stash="$OP_stash"
    current_branch="$OP_return_branch"

    # Sauf avis contraire sur la ligne de commande, la reprise garde la
    # conduite choisie au départ : un rebase lancé en pause se remet en pause
    # au conflit suivant, même repris avec --json.
    if [[ -z "$JGIT_ON_CONFLICT" ]]; then
        JGIT_ON_CONFLICT="$OP_on_conflict"
    fi
}

# Reprend un rebase en pause, une fois le conflit résolu.
feature_rebase_continue() {
    local feature_type="$1"
    local feature_name="$2"
    local first status

    feature_rebase_load_paused "$feature_type" "$feature_name"

    jgit_fetch_once || exit_safe "$JGIT_EXIT_REMOTE"

    JGIT_RESTAMP_BASED_ON="$OP_reference"
    if [[ "$OP_phase" == "pr" ]]; then
        JGIT_RESTAMP_BRANCH="$OP_pr_branch"
    else
        JGIT_RESTAMP_BRANCH="$OP_work_branch"
    fi

    first="${OP_pending%% *}"
    replay_finish_paused_pick "$OP_head_before" "$first"
    status=$?

    case $status in
        10) replay_pause_exit unresolved_files \
                "Des fichiers sont encore en conflit : résolvez-les et marquez-les résolus (git add) avant de reprendre." ;;
        11) REPLAY_CONFLICT_LINES=$(replay_conflict_marker_lines)
            replay_pause_exit conflict_markers_left \
                "Des marqueurs de conflit (<<<<<<<, =======, >>>>>>>) sont restés dans des fichiers marqués résolus." ;;
        12) replay_pause_exit conflict \
                "git n'a pas pu terminer le cherry-pick : vérifiez l'état du dépôt (git status) avant de reprendre." ;;
    esac

    OP_done=$((OP_done + 1))
    if [[ "$OP_pending" == *" "* ]]; then
        OP_pending="${OP_pending#* }"
    else
        OP_pending=""
    fi

    printf "%sConflit résolu, le rebase reprend.%s\n" "$C_GREEN" "$C_RESET"
    feature_rebase_run
}

# Annule un rebase en pause : l'état d'avant est restauré, rien n'a été poussé.
feature_rebase_abort() {
    local feature_type="$1"
    local feature_name="$2"

    feature_rebase_load_paused "$feature_type" "$feature_name"

    abort_rebase "$OP_work_branch" "$OP_reference" "$OP_work_rebase" "$OP_pr_rebase" "$OP_original_head" "$OP_squash_done"
    jgit_state_clear
    switch_branch "$OP_return_branch" recover
}
