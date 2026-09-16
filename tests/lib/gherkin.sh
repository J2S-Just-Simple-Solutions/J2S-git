#!/bin/bash
#
# Mini moteur Gherkin (style Cucumber) pour bash.
#
# Un fichier .feature decrit les scenarios en francais ; les definitions
# d'etapes (tests/steps/*.steps.sh) associent une expression reguliere a une
# fonction bash. Les groupes captures sont passes en arguments a la fonction.
#
# Mots-cles reconnus :
#   Fonctionnalite: / Feature:        titre du fichier
#   Contexte:       / Background:     etapes rejouees avant chaque scenario
#   Scenario:       / Scenario:       un scenario (bac a sable dedie)
#   Etant donne / Quand / Alors / Et / Mais  (et leurs equivalents anglais)
#   | tableau | de | donnees |        attache a l'etape qui precede
#   # commentaire                     ignore

###############################################
#            Registre des etapes
###############################################

STEP_PATTERNS=()
STEP_HANDLERS=()
STEP_DEF_COUNT=0

# Echappe les caracteres speciaux d'une expression reguliere.
gherkin_escape_regex() {
    local text="$1"
    text="${text//\\/\\\\}"
    text="${text//./\\.}"
    text="${text//\*/\\*}"
    text="${text//+/\\+}"
    text="${text//\?/\\?}"
    text="${text//(/\\(}"
    text="${text//)/\\)}"
    text="${text//[/\\[}"
    text="${text//]/\\]}"
    text="${text//^/\\^}"
    text="${text//\$/\\$}"
    text="${text//|/\\|}"
    text="${text//\{/\\{}"
    # L'accolade fermante passe par une variable : la mettre directement dans
    # l'expansion la terminerait prematurement.
    local close_brace='}'
    text="${text//$close_brace/\\$close_brace}"
    printf '%s' "$text"
}

# step_def <phrase> <fonction>
#
# La phrase est ecrite telle qu'elle apparait dans le .feature, avec des
# marqueurs a la place des valeurs :
#
#   {chaine}   une valeur entre guillemets, non vide  -> capturee
#   {texte}    une valeur entre guillemets, possiblement vide
#   {nombre}   un entier
#
# Chaque valeur capturee est passee en argument a la fonction, dans l'ordre.
step_def() {
    local phrase="$1"
    local handler="$2"
    local marker_string=$'\001'
    local marker_text=$'\002'
    local marker_number=$'\003'
    local pattern

    pattern="${phrase//\{chaine\}/$marker_string}"
    pattern="${pattern//\{texte\}/$marker_text}"
    pattern="${pattern//\{nombre\}/$marker_number}"
    pattern=$(gherkin_escape_regex "$pattern")
    pattern="${pattern//$marker_string/\"([^\"]+)\"}"
    pattern="${pattern//$marker_text/\"([^\"]*)\"}"
    pattern="${pattern//$marker_number/([0-9]+)}"

    STEP_PATTERNS[$STEP_DEF_COUNT]="^${pattern}\$"
    STEP_HANDLERS[$STEP_DEF_COUNT]="$handler"
    STEP_DEF_COUNT=$((STEP_DEF_COUNT + 1))
}

# Separateurs internes des tableaux (lignes / cellules).
GHERKIN_ROW_SEP=$'\036'
GHERKIN_CELL_SEP=$'\037'

# Tableau attache a l'etape en cours d'execution.
STEP_TABLE=""

# Renvoie la cellule <colonne> (base 1) de la ligne <ligne> (base 1) du tableau.
step_table_cell() {
    local wanted_row="$1"
    local wanted_col="$2"
    local row_index=0
    local row

    [[ -n "$STEP_TABLE" ]] || return 1

    local old_ifs="$IFS"
    IFS="$GHERKIN_ROW_SEP"
    # shellcheck disable=SC2206
    local rows=($STEP_TABLE)
    IFS="$old_ifs"

    for row in "${rows[@]}"; do
        row_index=$((row_index + 1))
        if [[ $row_index -eq $wanted_row ]]; then
            IFS="$GHERKIN_CELL_SEP"
            # shellcheck disable=SC2206
            local cells=($row)
            IFS="$old_ifs"
            printf '%s' "${cells[$((wanted_col - 1))]:-}"
            return 0
        fi
    done

    return 1
}

step_table_row_count() {
    [[ -n "$STEP_TABLE" ]] || { printf '0'; return 0; }

    local old_ifs="$IFS"
    IFS="$GHERKIN_ROW_SEP"
    # shellcheck disable=SC2206
    local rows=($STEP_TABLE)
    IFS="$old_ifs"
    printf '%s' "${#rows[@]}"
}

###############################################
#            Analyse du fichier .feature
###############################################

FEATURE_TITLE=""
SCENARIO_TITLES=()
SCENARIO_COUNT=0
PARSED_KEYWORDS=()
PARSED_TEXTS=()
PARSED_TABLES=()
PARSED_SCENARIOS=()   # -1 = etape de contexte
PARSED_COUNT=0

gherkin_trim() {
    local text="$1"
    text="${text#"${text%%[![:space:]]*}"}"
    text="${text%"${text##*[![:space:]]}"}"
    printf '%s' "$text"
}

gherkin_parse() {
    local file="$1"
    local raw line trimmed keyword text found kw
    local current_scenario=-1
    local in_feature_header=1

    FEATURE_TITLE=""
    SCENARIO_TITLES=()
    SCENARIO_COUNT=0
    PARSED_KEYWORDS=()
    PARSED_TEXTS=()
    PARSED_TABLES=()
    PARSED_SCENARIOS=()
    PARSED_COUNT=0

    while IFS= read -r raw || [[ -n "$raw" ]]; do
        line="${raw%$'\r'}"
        trimmed=$(gherkin_trim "$line")

        [[ -z "$trimmed" ]] && continue
        case "$trimmed" in
            '#'*|'@'*) continue ;;
        esac

        case "$trimmed" in
            "Fonctionnalité:"*|"Fonctionnalite:"*|"Feature:"*)
                FEATURE_TITLE=$(gherkin_trim "${trimmed#*:}")
                in_feature_header=1
                continue
                ;;
            "Contexte:"*|"Background:"*)
                current_scenario=-1
                in_feature_header=0
                continue
                ;;
            "Scénario:"*|"Scenario:"*|"Exemple:"*|"Example:"*)
                SCENARIO_TITLES[$SCENARIO_COUNT]=$(gherkin_trim "${trimmed#*:}")
                current_scenario=$SCENARIO_COUNT
                SCENARIO_COUNT=$((SCENARIO_COUNT + 1))
                in_feature_header=0
                continue
                ;;
            '|'*)
                if [[ $PARSED_COUNT -eq 0 ]]; then
                    printf 'Tableau sans etape associee : %s\n' "$trimmed" >&2
                    return 1
                fi
                local row="${trimmed#|}"
                row="${row%|}"
                local cells=""
                local old_ifs="$IFS"
                IFS='|'
                # shellcheck disable=SC2206
                local raw_cells=($row)
                IFS="$old_ifs"
                local cell
                for cell in "${raw_cells[@]}"; do
                    cell=$(gherkin_trim "$cell")
                    if [[ -z "$cells" ]]; then
                        cells="$cell"
                    else
                        cells="$cells$GHERKIN_CELL_SEP$cell"
                    fi
                done
                local last=$((PARSED_COUNT - 1))
                if [[ -z "${PARSED_TABLES[$last]}" ]]; then
                    PARSED_TABLES[$last]="$cells"
                else
                    PARSED_TABLES[$last]="${PARSED_TABLES[$last]}$GHERKIN_ROW_SEP$cells"
                fi
                continue
                ;;
        esac

        found=0
        for kw in "Étant donné que" "Étant donné" "Etant donné que" "Etant donné" \
                  "Soit" "Lorsque" "Quand" "Alors" "Et que" "Et" "Mais" \
                  "Given" "When" "Then" "And" "But"; do
            if [[ "$trimmed" == "$kw "* ]]; then
                keyword="$kw"
                text="${trimmed#$kw }"
                found=1
                break
            fi
        done

        if [[ $found -eq 0 ]]; then
            # Les lignes libres sous "Fonctionnalité:" sont une description.
            if [[ $in_feature_header -eq 1 ]]; then
                continue
            fi
            printf 'Ligne non comprise : %s\n' "$trimmed" >&2
            return 1
        fi

        PARSED_KEYWORDS[$PARSED_COUNT]="$keyword"
        PARSED_TEXTS[$PARSED_COUNT]=$(gherkin_trim "$text")
        PARSED_TABLES[$PARSED_COUNT]=""
        PARSED_SCENARIOS[$PARSED_COUNT]=$current_scenario
        PARSED_COUNT=$((PARSED_COUNT + 1))
    done < "$file"

    if [[ $SCENARIO_COUNT -eq 0 ]]; then
        printf 'Aucun scenario dans %s\n' "$file" >&2
        return 1
    fi

    return 0
}

###############################################
#            Execution
###############################################

# Retrouve la definition correspondant au texte de l'etape et l'execute.
gherkin_execute_step() {
    local text="$1"
    local table="$2"
    local index=0

    STEP_TABLE="$table"

    while [[ $index -lt $STEP_DEF_COUNT ]]; do
        if [[ "$text" =~ ${STEP_PATTERNS[$index]} ]]; then
            "${STEP_HANDLERS[$index]}" "${BASH_REMATCH[@]:1}"
            return 0
        fi
        index=$((index + 1))
    done

    assert_failed "etape non definie" \
        "aucune definition ne correspond a : $text" \
        "ajoutez-la dans tests/steps/*.steps.sh"
}

# Joue un scenario (contexte compris) dans un sous-shell dedie : une assertion
# en echec interrompt ce scenario sans empecher les suivants de tourner.
gherkin_run_scenario() {
    local scenario_index="$1"
    local index=0
    local scenario_of keyword text table

    printf '\n  %s: %s\n' "Scénario" "${SCENARIO_TITLES[$scenario_index]}"

    ASSERT_INDENT="        "
    trap sandbox_cleanup EXIT

    while [[ $index -lt $PARSED_COUNT ]]; do
        scenario_of="${PARSED_SCENARIOS[$index]}"
        if [[ "$scenario_of" == "-1" || "$scenario_of" == "$scenario_index" ]]; then
            keyword="${PARSED_KEYWORDS[$index]}"
            text="${PARSED_TEXTS[$index]}"
            table="${PARSED_TABLES[$index]}"
            printf '    %s %s\n' "$keyword" "$text"
            gherkin_execute_step "$text" "$table"
        fi
        index=$((index + 1))
    done

    printf '\n    -> scenario OK (%s assertions)\n' "$TEST_ASSERTIONS"
}

# Joue un fichier .feature complet. Renvoie 1 si au moins un scenario echoue.
run_feature() {
    local file="$1"
    local scenario_index=0
    local failures=0
    local status

    if ! gherkin_parse "$file"; then
        return 1
    fi

    printf 'Fonctionnalité: %s\n' "$FEATURE_TITLE"

    while [[ $scenario_index -lt $SCENARIO_COUNT ]]; do
        status=0
        ( gherkin_run_scenario "$scenario_index" ) || status=$?
        if [[ $status -ne 0 ]]; then
            failures=$((failures + 1))
            printf '\n    -> SCENARIO EN ECHEC : %s\n' "${SCENARIO_TITLES[$scenario_index]}"
        fi
        scenario_index=$((scenario_index + 1))
    done

    printf '\n'
    [[ $failures -eq 0 ]]
}
