#!/bin/bash
# ============================================================
#  flatpak-backup.sh
#  Sichert alle installierten Flatpak-Apps und Runtimes
#  als einzelne .flatpak Bundle-Dateien
#
#  Verwendung:
#    ./flatpak-backup.sh              → Apps + Runtimes
#    ./flatpak-backup.sh --userdata   → Apps + Runtimes + Userdaten
# ============================================================

# Home-Verzeichnis (funktioniert auch unter sudo)
if [ -n "${SUDO_USER}" ]; then
    REAL_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
else
    REAL_HOME="${HOME}"
fi

BACKUP_DIR="${REAL_HOME}/Downloads/flatpak-backup"
REPO_DIR="/var/lib/flatpak/repo"
USER_REPO_DIR="${REAL_HOME}/.local/share/flatpak/repo"
DATE=$(date +"%Y-%m-%d")
LOG_FILE="${BACKUP_DIR}/backup-${DATE}.log"

# Parameter auswerten
BACKUP_USERDATA=false
for arg in "$@"; do
    case $arg in
        --userdata) BACKUP_USERDATA=true ;;
        *) echo "Unbekannter Parameter: $arg"; echo "Verwendung: $0 [--userdata]"; exit 1 ;;
    esac
done

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "$1" | tee -a "${LOG_FILE}"; }

mkdir -p "${BACKUP_DIR}/apps"
mkdir -p "${BACKUP_DIR}/runtimes"

echo -e "${GREEN}==============================${NC}"
echo -e "${GREEN}  Flatpak Backup - ${DATE}${NC}"
echo -e "${GREEN}==============================${NC}"

log "\n📁 Backup-Ziel: ${BACKUP_DIR}"
log "👤 Nutzer:      ${SUDO_USER:-$USER}"
log "🕐 Gestartet:  $(date)\n"

# ---- Hilfsfunktion: Fortschritt anzeigen -------------------

show_progress() {
    local app_id="$1"
    local filename="$2"
    local expected_mb="$3"
    local pid="$4"

    while kill -0 "$pid" 2>/dev/null; do
        if [ -f "${filename}" ]; then
            local current_mb
            current_mb=$(du -sm "${filename}" 2>/dev/null | cut -f1)
            current_mb=${current_mb:-0}

            # Fortschrittsbalken berechnen
            local percent=0
            if [ "${expected_mb}" -gt 0 ]; then
                percent=$(( current_mb * 100 / expected_mb ))
                [ "${percent}" -gt 100 ] && percent=100
            fi
            local filled=$(( percent / 5 ))
            local empty=$(( 20 - filled ))
            local bar=""
            for ((i=0; i<filled; i++)); do bar+="█"; done
            for ((i=0; i<empty; i++)); do bar+="░"; done

            printf "\r   ${CYAN}[%s] %3d%% (%d MB / ~%d MB)${NC}  " \
                "${bar}" "${percent}" "${current_mb}" "${expected_mb}"
        else
            printf "\r   ${CYAN}⏳ Bundle wird vorbereitet...${NC}          "
        fi
        sleep 1
    done
    printf "\r%-60s\r" " "  # Zeile leeren
}

# ---- Bundle erstellen --------------------------------------

create_bundle() {
    local type="$1"
    local app_id="$2"
    local arch="$3"
    local branch="$4"
    local install="$5"
    local size_mb="$6"
    local filename="${BACKUP_DIR}/${type}/${app_id}__${arch}__${branch}.flatpak"

    if [ "${install}" = "user" ]; then
        repo="${USER_REPO_DIR}"
    else
        repo="${REPO_DIR}"
    fi

    if [ -f "${filename}" ]; then
        log "${YELLOW}⏭  Übersprungen (existiert bereits): ${app_id}${NC}"
        return 0
    fi

    log "📦 ${app_id} (${arch}, ${branch}) ~${size_mb} MB"

    # build-bundle im Hintergrund starten
    flatpak build-bundle "${repo}" "${filename}" \
        --arch="${arch}" \
        "${app_id}" "${branch}" >> "${LOG_FILE}" 2>&1 &
    local pid=$!

    # Fortschritt anzeigen
    show_progress "${app_id}" "${filename}" "${size_mb}" "${pid}"

    # Warten bis fertig
    wait "${pid}"
    local exit_code=$?

    if [ ${exit_code} -eq 0 ] && [ -f "${filename}" ]; then
        SIZE=$(du -sh "${filename}" | cut -f1)
        log "${GREEN}✅ Gesichert: ${app_id} → ${SIZE}${NC}"
        return 0
    else
        log "${RED}❌ Fehler bei: ${app_id}${NC}"
        rm -f "${filename}"
        return 1
    fi
}

# ---- Apps sichern ------------------------------------------

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "🖥  Sicherung: Apps"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

APP_COUNT=0
FAIL_COUNT=0
TOTAL_APPS=$(flatpak list --app --columns=application 2>/dev/null | wc -l)
CURRENT=0

while IFS=$'\t' read -r app_id arch branch install size_str; do
    ((CURRENT++))
    # Größe in MB umrechnen (flatpak gibt z.B. "711,6 MB" oder "1,2 MB")
    size_mb=$(echo "${size_str}" | sed 's/,/./g' | grep -oP '[0-9.]+' | head -1 | cut -d. -f1)
    size_mb=${size_mb:-50}

    log "\n[${CURRENT}/${TOTAL_APPS}] ${app_id}"

    if create_bundle "apps" "${app_id}" "${arch}" "${branch}" "${install}" "${size_mb}"; then
        ((APP_COUNT++))
    else
        ((FAIL_COUNT++))
    fi

done < <(flatpak list --app --columns=application,arch,branch,installation,size 2>/dev/null)

log "\n📊 Apps gesichert: ${APP_COUNT} | Fehler: ${FAIL_COUNT}"

# ---- Runtimes sichern --------------------------------------

log "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "⚙️   Sicherung: Runtimes"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RUNTIME_COUNT=0
TOTAL_RUNTIMES=$(flatpak list --runtime --columns=application 2>/dev/null | wc -l)
CURRENT=0

while IFS=$'\t' read -r runtime_id arch branch install size_str; do
    ((CURRENT++))
    size_mb=$(echo "${size_str}" | sed 's/,/./g' | grep -oP '[0-9.]+' | head -1 | cut -d. -f1)
    size_mb=${size_mb:-50}

    log "\n[${CURRENT}/${TOTAL_RUNTIMES}] ${runtime_id}"

    if create_bundle "runtimes" "${runtime_id}" "${arch}" "${branch}" "${install}" "${size_mb}"; then
        ((RUNTIME_COUNT++))
    fi

done < <(flatpak list --runtime --columns=application,arch,branch,installation,size 2>/dev/null)

log "\n📊 Runtimes gesichert: ${RUNTIME_COUNT}"

# ---- Userdaten sichern (optional) --------------------------

USERDATA_COUNT=0

if [ "${BACKUP_USERDATA}" = true ]; then
    log "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "👤  Sicherung: Userdaten (~/.var/app/)"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    mkdir -p "${BACKUP_DIR}/userdata"

    while IFS=$'\t' read -r app_id; do
        USERDATA_PATH="${REAL_HOME}/.var/app/${app_id}"

        if [ ! -d "${USERDATA_PATH}" ]; then
            log "${YELLOW}⏭  Keine Userdaten: ${app_id}${NC}"
            continue
        fi

        ARCHIVE="${BACKUP_DIR}/userdata/${app_id}.tar.gz"

        if [ -f "${ARCHIVE}" ]; then
            log "${YELLOW}⏭  Bereits gesichert: ${app_id}${NC}"
            continue
        fi

        log "👤 Sichere Userdaten: ${app_id}..."

        if tar -czf "${ARCHIVE}" -C "${REAL_HOME}/.var/app" "${app_id}" 2>>"${LOG_FILE}"; then
            SIZE=$(du -sh "${ARCHIVE}" | cut -f1)
            log "${GREEN}✅ Gesichert: ${app_id} → ${SIZE}${NC}"
            ((USERDATA_COUNT++))
        else
            log "${RED}❌ Fehler bei Userdaten: ${app_id}${NC}"
            rm -f "${ARCHIVE}"
        fi

    done < <(flatpak list --app --columns=application 2>/dev/null)

    log "\n📊 Userdaten gesichert: ${USERDATA_COUNT}"
fi

# ---- Zusammenfassung ---------------------------------------

TOTAL_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)

log "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "✅ Backup abgeschlossen: $(date)"
log "📦 Apps:      ${APP_COUNT} / ${TOTAL_APPS}"
log "⚙️  Runtimes:  ${RUNTIME_COUNT}"
log "❌ Fehler:    ${FAIL_COUNT}"
if [ "${BACKUP_USERDATA}" = true ]; then
log "👤 Userdaten: ${USERDATA_COUNT}"
fi
log "💾 Gesamt:    ${TOTAL_SIZE}"
log "📄 Log:       ${LOG_FILE}"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log "\n💡 Offline installieren:"
log "   flatpak install --bundle ~/Downloads/flatpak-backup/apps/<datei>.flatpak"
if [ "${BACKUP_USERDATA}" = true ]; then
log "\n💡 Userdaten wiederherstellen:"
log "   tar -xzf ${BACKUP_DIR}/userdata/<app-id>.tar.gz -C ~/.var/app/"
fi
