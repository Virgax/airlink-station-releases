#!/bin/bash
# =============================================================================
#  AIRLINK STATION — limpiar una estación vieja e instalar desde cero
#
#     curl -fsSL https://raw.githubusercontent.com/Virgax/airlink-station-releases/main/limpiar_e_instalar.sh | sudo bash
#
#  Para estaciones con instalaciones anteriores (scripts sueltos en
#  /usr/local/bin, app parcheada a mano, daemons viejos). Hace:
#    1. Respaldo COMPLETO en ~/AirlinkBackups/<host>_<fecha>_antes-limpieza
#       (motor, config, secretos, daemons, app, CSV/Excel, log del motor).
#    2. Detiene y borra todo lo de Airlink: daemons, scripts, herramientas,
#       sudoers, app, flags, config y estado.
#    3. CONSERVA: el nombre de la estación (STATION_ID), la carpeta de IPSW con
#       sus archivos, el CSV/Excel (logs/) y los respaldos.
#    4. Corre instalar.sh (última versión + kit cifrado) con ese nombre y carpeta.
#  No contiene secretos. Se puede cancelar en la confirmación sin tocar nada.
# =============================================================================
set -u
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
RAW="https://raw.githubusercontent.com/Virgax/airlink-station-releases/main"
A=/usr/local/airlink
CONF="$A/station.conf"
TTY=/dev/tty

ok()   { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
warn() { printf '  \033[33mAVISO\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31mFALLA\033[0m %s\n' "$*"; }
get_kv() { { grep -E "^[[:space:]]*$2=" "$1" 2>/dev/null || true; } | tail -1 | cut -d= -f2- | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//'; }

[ "$(id -u)" -eq 0 ] || { echo "Correr con sudo:  curl -fsSL $RAW/limpiar_e_instalar.sh | sudo bash"; exit 1; }
[ -r "$TTY" ] || { bad "Necesito una Terminal para confirmar"; exit 1; }

SUSER=$(stat -f %Su /dev/console 2>/dev/null || true)
case "$SUSER" in ""|root|loginwindow|_mbsetupuser) SUSER="${SUDO_USER:-}" ;; esac
UHOME=$(dscl . -read "/Users/$SUSER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
[ -n "$SUSER" ] && [ -d "$UHOME" ] || { bad "Iniciá sesión con el usuario de la estación y volvé a correr"; exit 1; }

# ------------------------------------------------------------ qué se conserva
STATION_ID=$(get_kv "$CONF" STATION_ID)
[ "$STATION_ID" = "AIRLINK-M4-01" ] && STATION_ID=""
[ -n "$STATION_ID" ] || STATION_ID=$(scutil --get LocalHostName 2>/dev/null || hostname -s)
SHOME=$(get_kv "$CONF" STATION_HOME); SHOME="${SHOME:-$UHOME}"
IPSW_DIR=$(get_kv "$CONF" IPSW_DIR)
case "$IPSW_DIR" in "~"*) IPSW_DIR="${SHOME}${IPSW_DIR#\~}" ;; esac
[ -n "$IPSW_DIR" ] || { [ -d "$SHOME/AirlinkIPSW" ] && IPSW_DIR="$SHOME/AirlinkIPSW"; }
DOC_DIR=$(get_kv "$CONF" DOC_DIR); DOC_DIR="${DOC_DIR:-$A/logs}"
NIPSW=$(ls "$IPSW_DIR"/*_Restore.ipsw 2>/dev/null | wc -l | tr -d ' ')
NCSV=$( [ -f "$DOC_DIR/wipe_load_log.csv" ] && wc -l < "$DOC_DIR/wipe_load_log.csv" | tr -d ' ' || echo 0)
# Locks de las últimas 2 h = equipos en proceso (los más viejos son restos)
ACTIVE=$(find /tmp -maxdepth 1 -name 'airlink_wipe_*.lock' -mmin -120 2>/dev/null | wc -l | tr -d ' ')

clear 2>/dev/null
echo "=================================================================="
echo "  Airlink Station — LIMPIAR e instalar desde cero"
echo "=================================================================="
echo "  Mac:            $(scutil --get ComputerName 2>/dev/null) (usuario ${SUSER})"
echo "  Se conserva:"
echo "    Estación      ${STATION_ID}"
echo "    IPSW          ${IPSW_DIR:-(ninguna)}  (${NIPSW} archivos)"
echo "    CSV / Excel   ${DOC_DIR}  (${NCSV} líneas)"
echo "  Se borra:       daemons, scripts del motor, herramientas, app, sudoers,"
echo "                  configuración, secretos (vuelven del kit) y estado."
echo "  Respaldo:       ${UHOME}/AirlinkBackups/"
echo
if [ "$ACTIVE" -gt 0 ]; then
    bad "Hay ${ACTIVE} equipo(s) en proceso. Esperá a que terminen y desconectalos."
    exit 1
fi
read -r -p "  Escribí LIMPIAR para seguir (otra cosa cancela): " ans < "$TTY" 2> "$TTY"
[ "$ans" = "LIMPIAR" ] || { echo "  Cancelado: no se tocó nada."; exit 1; }
echo

# ------------------------------------------------------------ 1. respaldo
echo "== 1. Respaldo"
BK="$UHOME/AirlinkBackups/$(scutil --get LocalHostName 2>/dev/null || hostname -s)_$(date +%Y%m%d_%H%M%S)_antes-limpieza"
mkdir -p "$BK/bin" "$BK/airlink" "$BK/launchdaemons" "$BK/launchagents" || { bad "No pude crear ${BK}"; exit 1; }
chmod 700 "$UHOME/AirlinkBackups" "$BK"
cp -p /usr/local/bin/wipe_*.sh /usr/local/bin/airlink_* /usr/local/bin/supervision_*.der \
      /usr/local/bin/*.mobileconfig "$BK/bin/" 2>/dev/null
for t in idevicerestore idevice_id ideviceinfo idevicediagnostics websockets; do
    [ -e "/usr/local/bin/$t" ] && cp -pP "/usr/local/bin/$t" "$BK/bin/"
done
[ -d "$A" ] && rsync -a --exclude 'IPSW/' --exclude '*.ipsw' --exclude 'backups/' \
    --exclude 'engine/' --exclude 'lib/' --exclude 'logs/restore/' "$A/" "$BK/airlink/"
cp -p /Library/LaunchDaemons/com.airlink.*.plist "$BK/launchdaemons/" 2>/dev/null
cp -p /Library/LaunchAgents/com.airlink.*.plist "$UHOME"/Library/LaunchAgents/com.airlink.*.plist "$BK/launchagents/" 2>/dev/null
cp -p /etc/sudoers.d/airlink* "$BK/" 2>/dev/null
[ -d "/Applications/Airlink Station.app" ] && ditto -c -k --keepParent "/Applications/Airlink Station.app" "$BK/AirlinkStation.app.zip"
for l in /var/log/airlink_*.log; do [ -f "$l" ] && gzip -c "$l" > "$BK/$(basename "$l").gz"; done
( cd "$BK" && find . -type f ! -name MANIFEST.txt -exec shasum -a 256 {} \; ) > "$BK/MANIFEST.txt" 2>/dev/null
chown -R "$SUSER" "$UHOME/AirlinkBackups"
if [ -f "$BK/MANIFEST.txt" ] && [ -s "$BK/MANIFEST.txt" ]; then ok "Respaldo: ${BK} ($(du -sh "$BK" | cut -f1))"
else bad "El respaldo quedó vacío: no sigo"; exit 1; fi

# ------------------------------------------------------------ 2. detener
echo "== 2. Deteniendo"
for p in /Library/LaunchDaemons/com.airlink.*.plist; do
    [ -f "$p" ] || continue
    l=$(basename "$p" .plist)
    launchctl bootout "system/$l" >/dev/null 2>&1; rm -f "$p"; ok "daemon ${l}"
done
UID_S=$(id -u "$SUSER")
for p in /Library/LaunchAgents/com.airlink.*.plist "$UHOME"/Library/LaunchAgents/com.airlink.*.plist; do
    [ -f "$p" ] || continue
    l=$(basename "$p" .plist)
    launchctl bootout "gui/$UID_S/$l" >/dev/null 2>&1; rm -f "$p"; ok "agente ${l}"
done
osascript -e 'tell application "Airlink Station" to quit' >/dev/null 2>&1
sleep 2
pkill -f "Airlink Station.app" 2>/dev/null
for pat in airlink_dashboard.py airlink_finder_suppress.sh airlink_gui_monitor.sh airlink_gui_restore.sh \
           airlink_ipsw_updater.py airlink_ipsw_mirror.py wipe_and_restore.sh wipe_launcher.sh; do
    pkill -f "$pat" 2>/dev/null
done
ok "procesos detenidos"

# ------------------------------------------------------------ 3. borrar
echo "== 3. Borrando la instalación vieja"
for f in /usr/local/bin/wipe_*.sh /usr/local/bin/airlink_* \
         /usr/local/bin/idevicerestore /usr/local/bin/idevice_id /usr/local/bin/ideviceinfo /usr/local/bin/idevicediagnostics; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    rm -f "$f"
done
ok "scripts y herramientas de /usr/local/bin (cfgutil y la identidad quedan; el kit la reinstala)"
rm -f /etc/sudoers.d/airlink*;            ok "sudoers"
rm -rf "/Applications/Airlink Station.app"; ok "app"
rm -f /tmp/airlink_* 2>/dev/null;         ok "flags de /tmp"
if [ -d "$A" ]; then
    for e in "$A"/* "$A"/.[!.]*; do
        [ -e "$e" ] || continue
        case "$(basename "$e")" in logs|backups|IPSW) continue ;; esac
        [ "$e" = "${IPSW_DIR%/}" ] && continue
        rm -rf "$e"
    done
    rm -rf "$A/logs/restore"
    ok "${A} (quedan logs/, IPSW/ y backups/)"
fi
pkgutil --forget com.airlink.station.pkg >/dev/null 2>&1
for l in /var/log/airlink_*.log; do [ -f "$l" ] && : > "$l"; done
ok "logs del motor vaciados (copia en el respaldo)"
echo

# ------------------------------------------------------------ 4. instalar
echo "== 4. Instalando desde cero"
T=$(mktemp /tmp/airlink-instalar.XXXXXX)
if ! curl -fsSL --retry 3 -o "$T" "$RAW/instalar.sh?t=$(date +%s)"; then
    bad "No pude bajar instalar.sh (¿internet?). Lo borrado está en ${BK}"; rm -f "$T"; exit 1
fi
if [ -n "$IPSW_DIR" ]; then
    /usr/bin/env STATION_ID="$STATION_ID" IPSW_DIR="$IPSW_DIR" /bin/bash "$T"
else
    /usr/bin/env STATION_ID="$STATION_ID" /bin/bash "$T"
fi
RC=$?
rm -f "$T"
echo
if [ $RC -eq 0 ]; then
    echo "  ✅ ${STATION_ID} reinstalada desde cero. Respaldo de lo anterior: ${BK}"
else
    bad "instalar.sh terminó con errores (ver arriba). Se puede volver a correr solo instalar.sh:"
    echo "     curl -fsSL $RAW/instalar.sh | sudo STATION_ID=\"${STATION_ID}\" bash"
    echo "     Lo anterior está en ${BK}"
fi
exit $RC
