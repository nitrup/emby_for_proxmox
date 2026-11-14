#!/usr/bin/env bash
# ============================================================
#  Emby Server – mise à jour vers la dernière release GitHub
#  Usage : ./install_emby_lastest.sh [-y] [--stable] [--no-ui]
#    -y        : pas de confirmation (cron / Proxmox hook)
#    --stable  : ignorer les versions bêta
#    --no-ui   : forcer le mode texte (pas de whiptail)
# ============================================================
set -Eeuo pipefail

# ---------- Options ----------
AUTO_YES=0; STABLE_ONLY=0; USE_UI=1
for arg in "$@"; do
  case "$arg" in
    -y|--yes)   AUTO_YES=1 ;;
    --stable)   STABLE_ONLY=1 ;;
    --no-ui)    USE_UI=0 ;;
    -h|--help)
      cat <<'EOF'
Emby Server – mise à jour vers la dernière release GitHub
Usage : install_emby_lastest.sh [-y] [--stable] [--no-ui]
  -y        : pas de confirmation (cron / Proxmox hook)
  --stable  : ignorer les versions bêta (requiert jq)
  --no-ui   : forcer le mode texte (pas de whiptail)
One-liner :
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/nitrup/emby_for_proxmox/main/install_emby_lastest.sh)" emby-update [options]
EOF
      exit 0 ;;
    *) echo "Option inconnue : $arg"; exit 2 ;;
  esac
done

# ---------- Couleurs (désactivées si pas de terminal) ----------
if [[ -t 1 ]] && command -v tput >/dev/null; then
  BOLD=$(tput bold); DIM=$(tput dim); RESET=$(tput sgr0)
  RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3)
  BLUE=$(tput setaf 4); CYAN=$(tput setaf 6)
else
  BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""
fi

# whiptail uniquement si dispo, terminal interactif et pas en mode -y
if ! command -v whiptail >/dev/null || [[ ! -t 0 ]] || (( AUTO_YES )); then
  USE_UI=0
fi

LOG_FILE="/var/log/emby-update.log"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------- Helpers d'affichage ----------
log()     { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE" 2>/dev/null || true; }
info()    { printf '%s▸%s %s\n' "$BLUE" "$RESET" "$*"; log "INFO  $*"; }
ok()      { printf '%s✔%s %s\n' "$GREEN" "$RESET" "$*"; log "OK    $*"; }
warn()    { printf '%s⚠%s %s\n' "$YELLOW" "$RESET" "$*"; log "WARN  $*"; }
die()     { printf '%s✖ %s%s\n' "$RED" "$*" "$RESET" >&2; log "ERROR $*"
            (( USE_UI )) && whiptail --title "Erreur" --msgbox "$*" 10 60; exit 1; }

banner() {
  printf '%s%s' "$CYAN" "$BOLD"
  cat <<'EOF'
  ┌──────────────────────────────────────────┐
  │        Emby Server – Mise à jour         │
  └──────────────────────────────────────────┘
EOF
  printf '%s' "$RESET"
}

# Spinner autour d'une commande longue : spin "message" cmd args...
spin() {
  local msg=$1; shift
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
  "$@" & local pid=$!
  if [[ -t 1 ]]; then
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r%s%s%s %s' "$CYAN" "${frames:i++%${#frames}:1}" "$RESET" "$msg"
      sleep 0.1
    done
    printf '\r\033[K'
  fi
  wait "$pid"
}

# Tableau clé/valeur aligné
kv() { printf '  %s%-26s%s %s\n' "$DIM" "$1" "$RESET" "$2"; }

# ---------- Pré-requis ----------
[[ $EUID -eq 0 ]] || die "Ce script doit être lancé en root (ou via sudo)."
for bin in curl wget dpkg apt-get; do
  command -v "$bin" >/dev/null || die "Commande manquante : $bin"
done
HAS_JQ=0; command -v jq >/dev/null && HAS_JQ=1

ARCH=$(dpkg --print-architecture)      # amd64 / arm64 / armhf
case "$ARCH" in
  amd64|arm64|armhf) ;;
  *) die "Architecture non supportée : $ARCH" ;;
esac

# ---------- Versions ----------
clear 2>/dev/null || true
banner

get_installed_version() {
  dpkg-query -W -f='${Version}' emby-server 2>/dev/null || echo "none"
}

fetch_latest() {
  local api="https://api.github.com/repos/MediaBrowser/Emby.Releases/releases"
  local json
  json=$(curl -fsSL --max-time 20 -H 'Accept: application/vnd.github+json' "$api") || return 1
  if (( HAS_JQ )); then
    if (( STABLE_ONLY )); then
      jq -r '[.[] | select(.prerelease == false)][0].tag_name' <<<"$json"
    else
      jq -r '.[0].tag_name' <<<"$json"
    fi
  else
    # Repli sans jq (ne filtre pas les bêtas)
    grep -m1 '"tag_name"' <<<"$json" | cut -d'"' -f4
  fi
}

installed_version=$(get_installed_version)
latest_version=$(spin "Interrogation de GitHub…" fetch_latest) \
  || die "Impossible de joindre l'API GitHub."
[[ -n "$latest_version" && "$latest_version" != "null" ]] \
  || die "Version introuvable dans la réponse GitHub."

filename="emby-server-deb_${latest_version}_${ARCH}.deb"
download_url="https://github.com/MediaBrowser/Emby.Releases/releases/download/${latest_version}/${filename}"

echo
kv "Hôte"                 "$(hostname)"
kv "Architecture"         "$ARCH"
kv "Version installée"    "${BOLD}${installed_version}${RESET}"
kv "Dernière version"     "${BOLD}${latest_version}${RESET}$( (( STABLE_ONLY )) && echo " (stable)" || echo " (bêta incluse)")"
echo

# ---------- Comparaison ----------
if [[ "$installed_version" != "none" ]] \
   && dpkg --compare-versions "$installed_version" ge "$latest_version"; then
  ok "Emby est déjà à jour."
  (( USE_UI )) && whiptail --title "Emby Server" \
      --msgbox "Déjà à jour : $installed_version" 8 50
  exit 0
fi

# ---------- Confirmation ----------
if (( ! AUTO_YES )); then
  if (( USE_UI )); then
    whiptail --title "Mise à jour disponible" --yesno \
      "Installée : $installed_version\nDisponible : $latest_version\n\nMettre à jour maintenant ?" \
      11 50 || { warn "Mise à jour annulée."; exit 0; }
  else
    read -rp "$(printf '%s?%s Mettre à jour vers %s ? [o/N] ' "$YELLOW" "$RESET" "$latest_version")" answer
    [[ "$answer" =~ ^[oOyY]$ ]] || { warn "Mise à jour annulée."; exit 0; }
  fi
fi

# ---------- Téléchargement ----------
info "Téléchargement de $filename"
wget -q --show-progress --progress=bar:force:noscroll \
     -O "$TMP_DIR/$filename" "$download_url" \
  || die "Échec du téléchargement : $download_url"
ok "Téléchargé ($(du -h "$TMP_DIR/$filename" | cut -f1))"

# ---------- Installation ----------
info "Installation (apt gère les dépendances)…"
export DEBIAN_FRONTEND=noninteractive
if (( USE_UI )); then
  # Sortie apt redirigée dans le log, jauge whiptail pendant l'install
  { apt-get install -y "$TMP_DIR/$filename" >>"$LOG_FILE" 2>&1 & pid=$!
    p=0; while kill -0 "$pid" 2>/dev/null; do
      echo $(( p < 95 ? p+=5 : p )); sleep 1
    done; wait "$pid" && echo 100 || echo "ERR"
  } | whiptail --title "Installation" --gauge "Installation de Emby $latest_version…" 7 60 0
  dpkg -s emby-server >/dev/null 2>&1 || die "Échec de l'installation (voir $LOG_FILE)."
else
  apt-get install -y "$TMP_DIR/$filename" | tee -a "$LOG_FILE" \
    || die "Échec de l'installation."
fi

# ---------- Vérification du service ----------
info "Vérification du service…"
systemctl restart emby-server 2>/dev/null || true
sleep 3
if systemctl is-active --quiet emby-server; then
  ok "emby-server actif"
else
  warn "emby-server ne semble pas démarré : systemctl status emby-server"
fi

new_version=$(get_installed_version)
echo
printf '%s%s' "$GREEN" "$BOLD"
echo "  ┌──────────────────────────────────────────┐"
printf "  │  ✔ Mise à jour terminée : %-15s│\n" "$new_version"
echo "  └──────────────────────────────────────────┘"
printf '%s' "$RESET"
kv "Journal" "$LOG_FILE"
log "Mise à jour $installed_version -> $new_version terminée"

(( USE_UI )) && whiptail --title "Terminé" \
   --msgbox "Emby Server mis à jour :\n$installed_version → $new_version\n\nService : $(systemctl is-active emby-server)" 11 50
exit 0
