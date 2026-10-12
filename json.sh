#!/bin/bash

###############################################
###############################################
#      Sortie machine : le contrat --json
###############################################
###############################################
#
# jgit est piloté par des humains, mais aussi par une IA (Claude Code), par
# l'interface en terminal et, à terme, par Jenkins. Ces trois-là ne lisent pas
# des phrases : ils lisent un document.
#
# Le contrat, détaillé dans docs/06-contrat-cli.md :
#
#   - avec --json, la sortie standard porte UN SEUL document JSON, suivi d'un
#     retour à la ligne, et rien d'autre ;
#   - tous les messages destinés aux humains partent sur la sortie d'erreur ;
#   - le code de sortie suit la table JGIT_EXIT_* ci-dessous.
#
# Mise en œuvre : jgit.sh détecte --json avant toute chose, duplique la sortie
# standard sur le descripteur 3 et redirige la sortie standard vers la sortie
# d'erreur. Le code existant continue d'écrire ses messages comme avant ; seul
# json_emit écrit sur le descripteur 3.
#
# Tout est en bash pur (aucun jq sur les postes) et compatible bash 3.2 comme
# 5.2. Piège de bash 5.2 : dans ${s//motif/remplacement}, un remplacement non
# protégé par des guillemets donne un sens spécial à « & » (patsub_replacement).
# Les remplacements ci-dessous sont donc tous entre guillemets.

# Codes de sortie. Le code « error.code » du document JSON est plus précis ; le
# code de sortie donne la famille, pour un script qui ne lit pas le JSON.
JGIT_EXIT_OK=0          # succès, y compris quand il n'y avait rien à faire
JGIT_EXIT_ERROR=1       # usage incorrect, ou échec inattendu d'une commande git
JGIT_EXIT_REFUSED=2     # précondition refusée : rien n'a été modifié
JGIT_EXIT_CONFLICT=3    # conflit : opération en pause, ou abandonnée
JGIT_EXIT_LEASE=4       # quelqu'un a poussé entre-temps : rien n'a été écrasé
JGIT_EXIT_PAUSED=5      # une opération attend déjà une résolution de conflit
JGIT_EXIT_REMOTE=6      # serveur injoignable

JGIT_JSON=false
JGIT_JSON_EMITTED=false

# Contexte de la dernière erreur, repris par le document jgit.error/1.
JGIT_ERROR_CODE=""
JGIT_ERROR_MESSAGE=""
JGIT_ERROR_HINT=""

# Commande en cours (« demo show »…), rappelée dans chaque document.
JGIT_COMMAND=""

###############################################
#            Fragments JSON
###############################################
#
# Chaque fonction écrit un fragment sur la sortie standard ; on les assemble
# par substitution de commande :
#
#   json_object "$(json_kv_str name "$name")" "$(json_kv_num count "$n")"

# Chaîne JSON, guillemets compris.
json_str() {
  local s="$1"
  local bs='\'
  local q='"'

  case "$s" in
    *[[:cntrl:]\"\\]*)
      # Caractères de contrôle autres que tabulation, saut de ligne et retour
      # chariot : supprimés (ils n'ont rien à faire dans un nom de branche ou
      # un message). Le point final protège les sauts de ligne terminaux, que
      # la substitution de commande supprimerait.
      s=$(printf '%s.' "$s" | LC_ALL=C tr -d '\000-\010\013\014\016-\037')
      s=${s%.}
      s=${s//"$bs"/"$bs$bs"}
      s=${s//"$q"/"$bs$q"}
      s=${s//$'\t'/"${bs}t"}
      s=${s//$'\r'/"${bs}r"}
      s=${s//$'\n'/"${bs}n"}
      ;;
  esac

  printf '"%s"' "$s"
}

# Chaîne, ou null si vide.
json_str_or_null() {
  if [[ -z "$1" ]]; then
    printf 'null'
  else
    json_str "$1"
  fi
}

# Entier, ou null si la valeur n'en est pas un.
json_num() {
  if [[ "$1" =~ ^-?[0-9]+$ ]]; then
    printf '%s' "$1"
  else
    printf 'null'
  fi
}

json_bool() {
  if [[ "$1" == true ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

# "clé":<valeur JSON déjà formée>
json_kv() {
  printf '%s:%s' "$(json_str "$1")" "$2"
}

json_kv_str() {
  json_kv "$1" "$(json_str "$2")"
}

json_kv_str_or_null() {
  json_kv "$1" "$(json_str_or_null "$2")"
}

json_kv_num() {
  json_kv "$1" "$(json_num "$2")"
}

json_kv_bool() {
  json_kv "$1" "$(json_bool "$2")"
}

json_kv_null() {
  json_kv "$1" "null"
}

# {fragment,fragment,…} ; les fragments vides sont ignorés.
json_object() {
  local parts=()
  local part

  for part in "$@"; do
    [[ -n "$part" ]] && parts[${#parts[@]}]="$part"
  done

  local IFS=','
  printf '{%s}' "${parts[*]}"
}

# [valeur,valeur,…] ; les valeurs vides sont ignorées.
json_array() {
  local parts=()
  local part

  for part in "$@"; do
    [[ -n "$part" ]] && parts[${#parts[@]}]="$part"
  done

  local IFS=','
  printf '[%s]' "${parts[*]}"
}

# ["chaîne","chaîne",…]
json_str_array() {
  local parts=()
  local item

  for item in "$@"; do
    parts[${#parts[@]}]="$(json_str "$item")"
  done

  json_array ${parts[@]+"${parts[@]}"}
}

###############################################
#            Émission
###############################################

# Active le mode --json : la sortie standard devient le canal du document, et
# tout le reste part sur la sortie d'erreur. À appeler une seule fois, avant
# tout affichage.
jgit_json_enable() {
  JGIT_JSON=true
  exec 3>&1 1>&2
  trap jgit_json_on_exit EXIT
}

# Écrit LE document de la commande. Un second appel serait une erreur de
# programmation : le contrat promet un seul document.
json_emit() {
  [[ $JGIT_JSON == true ]] || return 0

  if [[ $JGIT_JSON_EMITTED == true ]]; then
    printf "Erreur interne : un second document JSON a été demandé, il est ignoré.\n" >&2
    return 1
  fi

  printf '%s\n' "$1" >&3
  JGIT_JSON_EMITTED=true
}

# Mémorise l'erreur qui va interrompre la commande, pour le document JSON.
jgit_error_set() {
  JGIT_ERROR_CODE="$1"
  JGIT_ERROR_MESSAGE="$2"
  JGIT_ERROR_HINT="${3:-}"
}

# Document d'erreur : jgit.error/1.
jgit_error_document() {
  local exit_code="$1"
  local code="${JGIT_ERROR_CODE:-failed}"
  local message="$JGIT_ERROR_MESSAGE"

  if [[ -z "$message" ]]; then
    message="La commande a échoué : le détail est sur la sortie d'erreur."
  fi

  json_object \
    "$(json_kv_str schema "jgit.error/1")" \
    "$(json_kv_bool ok false)" \
    "$(json_kv_str_or_null command "$JGIT_COMMAND")" \
    "$(json_kv error "$(json_object \
        "$(json_kv_str code "$code")" \
        "$(json_kv_num exit_code "$exit_code")" \
        "$(json_kv_str message "$message")" \
        "$(json_kv_str_or_null hint "$JGIT_ERROR_HINT")")")"
}

# Filet de sécurité : quelle que soit la façon dont jgit se termine (exit_safe,
# exit direct, erreur), la sortie standard porte un document. Une commande qui
# n'a pas de document propre produit un résultat générique.
jgit_json_on_exit() {
  local status=$?

  [[ $JGIT_JSON == true && $JGIT_JSON_EMITTED != true ]] || return 0

  if [[ $status -eq 0 ]]; then
    json_emit "$(json_object \
      "$(json_kv_str schema "jgit.result/1")" \
      "$(json_kv_bool ok true)" \
      "$(json_kv_str_or_null command "$JGIT_COMMAND")")"
  else
    json_emit "$(jgit_error_document "$status")"
  fi
}

# Arrête la commande sur une erreur identifiée.
#
#   jgit_fail <code> <code_de_sortie> <message> [remède]
#
# Le message part en rouge sur la sortie d'erreur, le remède en dessous ; en
# mode --json, les deux sont repris dans le document jgit.error/1.
jgit_fail() {
  local code="$1"
  local exit_code="$2"
  local message="$3"
  local hint="${4:-}"

  jgit_error_set "$code" "$message" "$hint"

  printf "%s%s%s\n" "$C_RED" "$message" "$C_RESET" >&2
  if [[ -n "$hint" ]]; then
    printf "%s\n" "$hint" >&2
  fi

  exit_safe "$exit_code"
}
