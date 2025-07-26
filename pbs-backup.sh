#!/usr/bin/env bash
# =============================================================================
# Script : pbs-backup.sh
# But    : Backup Linux Instance complète sur PBS Server avec chiffrement
# Auteur : Youkyi
# Date   : 2025-07-25
# Licence: MIT
# =============================================================================

set -euo pipefail

###############################################################################
# 1. CONFIGURATION PAR DÉFAUT                                                  #
###############################################################################
PBS_SERVER="user@pbs!token@pbs.example.com"
PBS_PASSWORD="password"
DEFAULT_DATASTORE="datastore"
NAMESPACE="VPS"  # Namespace PBS
BACKUP_ID="cloud-01"  # Format autorisé : alphanumériques, tirets, underscores

# Configuration du chiffrement - CLÉ SANS MOT DE PASSE
CRYPT_MODE="encrypt"  # ou "sign-only" pour signature seule
KEYFILE="/etc/pve/priv/pbs-encryption.key"  # Clé PVE existante
CRYPT_PASSWORD=""  # Vide car pas de mot de passe
USE_ENCRYPTION_PASSWORD=false  # Désactive l'utilisation du mot de passe de chiffrement

# Répertoires à exclure de la sauvegarde complète
EXCLUDES=(
  "/proc"
  "/sys"
  "/dev"
  "/run"
  "/tmp"
  "/var/tmp"
  "/var/run"
  "/var/lock"
  "/var/cache"
  "/var/log"
  "/mnt"
  "/media"
  "/lost+found"
  "/swapfile"
  "/swap.img"
  "*.sock"
  "*.pid"
  "/var/lib/docker/overlay2"  # Optionnel: éviter les couches Docker en doublon
)

# Nom de l'archive PXAR
ARCHIVE_NAME="root"

# Logs
LOG_FILE="/var/log/pbs-backup.log"

# Webhook Discord
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/WEBHOOK-ID/WEBHOOK-TOKEN"

# Nom du VPS pour notification
VPS_NAME="Hostname"

###############################################################################
# 2. VARIABLES POUR OPTIONS                                                    #
###############################################################################
SELECTED_DATASTORE="$DEFAULT_DATASTORE"

###############################################################################
# 3. FONCTIONS D'AIDE                                                          #
###############################################################################
show_help() {
  cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
  -d, --datastore DATASTORE    Spécifier le datastore PBS (défaut: $DEFAULT_DATASTORE)
  -p, --password PASSWORD      Mot de passe de la clé de chiffrement
  -n, --namespace NAMESPACE    Spécifier le namespace PBS (défaut: $NAMESPACE)
  -b, --backup-id BACKUP_ID    Spécifier le backup-id (défaut: $BACKUP_ID)
  -h, --help                   Afficher cette aide

EXEMPLES:
  $0                                    # Utilise les valeurs par défaut
  $0 -d backup-storage                  # Utilise le datastore 'backup-storage'
  $0 -d backup-storage -p monmotdepasse # Avec datastore et mot de passe
  $0 -n production -d backup-storage    # Avec namespace et datastore
  $0 -b "mon-backup-id"                 # Avec backup-id personnalisé
  $0 --datastore backup-storage --password monmotdepasse --namespace production

DESCRIPTION:
  Ce script effectue une sauvegarde COMPLÈTE chiffrée de la machine vers un serveur 
  Proxmox Backup Server. Tous les fichiers sont sauvegardés sauf les répertoires 
  système temporaires et virtuels (/proc, /sys, /dev, /tmp, etc.).
  
  Le backup-id est configuré par défaut pour utiliser un format compatible.
  
  Configuration actuelle : clé de chiffrement SANS mot de passe.

CONFIGURATION ACTUELLE:
  Serveur PBS : $PBS_SERVER
  Datastore   : $DEFAULT_DATASTORE
  Namespace   : $NAMESPACE
  Backup-ID   : $BACKUP_ID
  Clé chiffrement : $(if [[ "$USE_ENCRYPTION_PASSWORD" == true ]]; then echo "avec mot de passe"; else echo "sans mot de passe"; fi)

EXCLUSIONS AUTOMATIQUES:
$(printf '  %s\n' "${EXCLUDES[@]}")

EOF
}

###############################################################################
# 4. TRAITEMENT DES ARGUMENTS                                                  #
###############################################################################
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -d|--datastore)
        if [[ -n "${2:-}" ]]; then
          SELECTED_DATASTORE="$2"
          shift 2
        else
          echo "Erreur: -d/--datastore nécessite un argument" >&2
          exit 1
        fi
        ;;
      -p|--password)
        if [[ -n "${2:-}" ]]; then
          CRYPT_PASSWORD="$2"
          USE_ENCRYPTION_PASSWORD=true  # Active l'utilisation du mot de passe si fourni
          shift 2
        else
          echo "Erreur: -p/--password nécessite un argument" >&2
          exit 1
        fi
        ;;
      -n|--namespace)
        if [[ -n "${2:-}" ]]; then
          NAMESPACE="$2"
          shift 2
        else
          echo "Erreur: -n/--namespace nécessite un argument" >&2
          exit 1
        fi
        ;;
      -b|--backup-id)
        if [[ -n "${2:-}" ]]; then
          BACKUP_ID="$2"
          shift 2
        else
          echo "Erreur: -b/--backup-id nécessite un argument" >&2
          exit 1
        fi
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        echo "Option inconnue: $1" >&2
        echo "Utilisez -h/--help pour voir l'aide" >&2
        exit 1
        ;;
    esac
  done
}

###############################################################################
# 5. ENVIRONNEMENT                                                             #
###############################################################################
export PBS_PASSWORD
export LANG=C.UTF-8
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Validation des variables requises
if [[ -z "$SELECTED_DATASTORE" ]]; then
  echo "ERREUR: datastore absent" >&2
  exit 1
fi

if [[ -z "$NAMESPACE" ]]; then
  echo "ERREUR: namespace absent" >&2
  exit 1
fi

if [[ -z "$BACKUP_ID" ]]; then
  echo "ERREUR: backup-id absent" >&2
  exit 1
fi

# Construction du repository SANS namespace (le namespace sera passé avec --ns)
PBS_REPOSITORY="${PBS_SERVER}:${SELECTED_DATASTORE}"

###############################################################################
# 6. FONCTIONS UTILITAIRES                                                     #
###############################################################################
log() {
  local message="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$message"
  echo "$message" >> "$LOG_FILE"
}

discord_notify() {
  local status="$1"
  local message="$2"
  
  # Vérifier que l'URL du webhook est définie
  if [[ -z "$DISCORD_WEBHOOK_URL" ]] || [[ "$DISCORD_WEBHOOK_URL" == "https://discord.com/api/webhooks/WEBHOOK-ID/WEBHOOK-TOKEN" ]]; then
    log "ATTENTION: URL Discord webhook non configurée"
    return 0
  fi
  
  # Échapper les caractères spéciaux pour JSON
  local escaped_message
  escaped_message=$(echo "$message" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/`/\\`/g')
  
  # Construire le payload JSON manuellement pour éviter les problèmes jq
  local payload
  payload=$(cat << EOF
{
  "content": "**Backup VPS $VPS_NAME** : $status",
  "embeds": [
    {
      "description": "\`\`\`$escaped_message\`\`\`",
      "color": $(if [[ "$status" == *"✅"* ]]; then echo "65280"; else echo "16711680"; fi),
      "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
    }
  ]
}
EOF
)
  
  # Envoyer la notification avec gestion d'erreur
  local response
  response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "$payload" \
    "$DISCORD_WEBHOOK_URL" 2>&1)
  
  local http_code
  http_code=$(echo "$response" | tail -n1 | cut -d: -f2)
  
  if [[ "$http_code" == "204" ]] || [[ "$http_code" == "200" ]]; then
    log "Notification Discord envoyée avec succès"
  else
    log "ERREUR: Échec envoi notification Discord (HTTP $http_code)"
    log "Réponse: $(echo "$response" | head -n -1)"
  fi
}

get_encryption_password() {
  # Si la clé n'utilise pas de mot de passe, ne rien faire
  if [[ "$USE_ENCRYPTION_PASSWORD" == false ]]; then
    log "Clé de chiffrement sans mot de passe - aucune saisie requise"
    return 0
  fi
  
  # Si le mot de passe est déjà défini et non vide, l'utiliser
  if [[ -n "$CRYPT_PASSWORD" ]] && [[ "$CRYPT_PASSWORD" != "votre_mot_de_passe_ici" ]]; then
    log "Utilisation du mot de passe défini dans la configuration"
    return 0
  fi
  
  # Sinon, demander interactivement
  echo "Entrez le mot de passe de la clé de chiffrement :"
  read -s CRYPT_PASSWORD
  echo
  
  if [[ -z "$CRYPT_PASSWORD" ]]; then
    log "ERREUR: Mot de passe vide"
    exit 1
  fi
}

check_encryption_key() {
  if [[ ! -f "$KEYFILE" ]]; then
    log "ERREUR: Clé de chiffrement non trouvée : $KEYFILE"
    
    if [[ "$USE_ENCRYPTION_PASSWORD" == false ]]; then
      log "Génération d'une nouvelle clé sans mot de passe..."
      # Générer une clé sans mot de passe
      proxmox-backup-client key create --kdf none "$KEYFILE"
    else
      log "Génération d'une nouvelle clé avec mot de passe..."
      # Obtenir le mot de passe si nécessaire
      get_encryption_password
      # Générer une nouvelle clé avec mot de passe
      echo "$CRYPT_PASSWORD" | proxmox-backup-client key create --kdf scrypt "$KEYFILE"
    fi
    
    chmod 600 "$KEYFILE"
    log "Clé générée et sauvegardée dans $KEYFILE"
    log "IMPORTANT: Sauvegardez cette clé dans un endroit sûr !"
  else
    # Clé existante, obtenir le mot de passe seulement si nécessaire
    if [[ "$USE_ENCRYPTION_PASSWORD" == true ]]; then
      get_encryption_password
    else
      log "Utilisation de la clé existante sans mot de passe"
    fi
  fi
}

###############################################################################
# 7. VALIDATION                                                                #
###############################################################################
validate_environment() {
  # Vérifier les commandes requises
  local required_commands=("proxmox-backup-client" "curl")
  for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
      log "ERREUR: Commande requise non trouvée : $cmd"
      exit 1
    fi
  done
  
  # jq n'est plus obligatoire avec la nouvelle fonction Discord
  if ! command -v "jq" &> /dev/null; then
    log "ATTENTION: jq non trouvé, mais pas nécessaire pour les notifications Discord"
  fi
  
  # Vérifier l'espace disque disponible (approximatif)
  local available_space
  available_space=$(df / | awk 'NR==2 {print $4}')
  log "Espace disponible sur / : ${available_space}K"
  
  # Avertir si peu d'espace (moins de 1GB)
  if [[ $available_space -lt 1048576 ]]; then
    log "ATTENTION: Espace disque faible. La sauvegarde pourrait échouer."
  fi
}

estimate_backup_size() {
  log "Estimation de la taille de sauvegarde..."
  
  # Construire les exclusions pour du
  local du_excludes=()
  for exclude in "${EXCLUDES[@]}"; do
    if [[ "$exclude" != *"*"* ]]; then  # Éviter les patterns avec *
      du_excludes+=("--exclude=$exclude")
    fi
  done
  
  local estimated_size
  estimated_size=$(du -sh "${du_excludes[@]}" / 2>/dev/null | cut -f1 || echo "N/A")
  log "Taille estimée à sauvegarder : $estimated_size"
}

###############################################################################
# 8. EXÉCUTION PRINCIPALE                                                      #
###############################################################################
main() {
  # Parser les arguments
  parse_arguments "$@"
  
  log "========== Début backup COMPLET PBS avec chiffrement ($TIMESTAMP) =========="
  log "Serveur PBS      : $PBS_SERVER"
  log "Datastore        : $SELECTED_DATASTORE"
  log "Namespace        : $NAMESPACE"
  log "Backup-ID        : $BACKUP_ID"
  log "Repository       : $PBS_REPOSITORY"
  log "Mode chiffrement : $(if [[ "$USE_ENCRYPTION_PASSWORD" == true ]]; then echo "avec mot de passe"; else echo "sans mot de passe"; fi)"
  log "Clé de chiffrement : $KEYFILE"
  log "Mode: Sauvegarde complète de la machine"
  
  # Validation de l'environnement
  validate_environment
  
  # Estimation de la taille
  estimate_backup_size
  
  # Vérifier la présence de la clé de chiffrement
  check_encryption_key

  log "Authentification…"
  if ! proxmox-backup-client login --repository "$PBS_REPOSITORY"; then
    log "ERREUR: Échec de l'authentification PBS"
    log "Tentative d'envoi notification Discord d'échec d'authentification..."
    discord_notify "❌ Échec Authentification" "Échec authentification PBS pour $VPS_NAME à $TIMESTAMP"
    exit 1
  fi

  # Préparer les arguments d'exclusion
  EXCLUDE_ARGS=()
  for exclude in "${EXCLUDES[@]}"; do
    EXCLUDE_ARGS+=( --exclude "$exclude" )
  done

  log "Lancement du backup complet chiffré…"
  log "Exclusions appliquées: ${#EXCLUDES[@]} répertoires/patterns"
  
  # Utiliser le mot de passe pour le chiffrement seulement si nécessaire
  if [[ "$USE_ENCRYPTION_PASSWORD" == true ]] && [[ -n "$CRYPT_PASSWORD" ]]; then
    export PBS_ENCRYPTION_PASSWORD="$CRYPT_PASSWORD"
    log "Variable d'environnement PBS_ENCRYPTION_PASSWORD définie"
  else
    log "Pas de mot de passe de chiffrement - variable PBS_ENCRYPTION_PASSWORD non définie"
  fi
  
  # Créer un fichier temporaire pour capturer les erreurs
  local temp_error_file
  temp_error_file=$(mktemp)
  
  log "Démarrage de la sauvegarde... (progression affichée ci-dessous)"
  echo "════════════════════════════════════════════════════════════════"
  
  # Commande backup avec affichage en temps réel ET capture des erreurs
  if proxmox-backup-client backup \
      --repository "$PBS_REPOSITORY" \
      --ns "$NAMESPACE" \
      --backup-id "$BACKUP_ID" \
      --change-detection-mode metadata \
      --crypt-mode "$CRYPT_MODE" \
      --keyfile "$KEYFILE" \
      "${EXCLUDE_ARGS[@]}" \
      "${ARCHIVE_NAME}.pxar:/" 2> >(tee "$temp_error_file" >&2); then

    echo "════════════════════════════════════════════════════════════════"
    log "Backup complet chiffré réussi sur '$SELECTED_DATASTORE' namespace '$NAMESPACE' backup-id '$BACKUP_ID'."
    log "Tentative d'envoi notification Discord de succès..."
    discord_notify "✅ Succès (sauvegarde complète chiffrée)" "Sauvegarde complète chiffrée de $VPS_NAME terminée à $TIMESTAMP sur datastore '$SELECTED_DATASTORE' namespace '$NAMESPACE' backup-id '$BACKUP_ID'"

  else
    echo "════════════════════════════════════════════════════════════════"
    # Lire les erreurs du fichier temporaire
    local error_content
    error_content=$(cat "$temp_error_file" 2>/dev/null || echo "Erreur inconnue")
    
    # Extraire l'erreur spécifique
    local error_line
    error_line=$(echo "$error_content" | grep -i "error\|failed\|enospc" | tail -1 || echo "Erreur de sauvegarde")
    
    log "ERREUR lors du backup complet chiffré !"
    log "Détails de l'erreur: $error_line"
    log "Sortie complète des erreurs: $error_content"
    log "Tentative d'envoi notification Discord d'échec..."
    
    # Notification avec l'erreur spécifique
    discord_notify "❌ Échec Sauvegarde" "Sauvegarde de $VPS_NAME échouée à $TIMESTAMP. ERREUR: $error_line"
    
    # Nettoyer le fichier temporaire
    rm -f "$temp_error_file"
    exit 1
  fi

  # Nettoyer le fichier temporaire
  rm -f "$temp_error_file"
  
  log "========== Fin backup PBS ($TIMESTAMP) =========="
}

###############################################################################
# 9. POINT D'ENTRÉE                                                            #
###############################################################################
main "$@"

exit 0
