#!/bin/bash
# =============================================================================
#  AIRLINK STATION — dejar esta Mac lista desde el SSD portátil (doble clic)
#
#  Va en la raíz del SSD como "Instalar Airlink.command", junto a la carpeta
#  IPSW/ con los *_Restore.ipsw (lo arma preparar_ssd.sh). Hace:
#    1. instalar.sh (requisitos, app, estación, kit cifrado, pruebas)
#    2. red: cable primero, WiFi de respaldo, SQL por WiFi (ruta fija)
#    3. copia los IPSW del SSD a la carpeta de IPSW de la estación
#  No contiene secretos: pide la contraseña de la Mac y la frase del kit.
# =============================================================================
RAW="https://raw.githubusercontent.com/Virgax/airlink-station-releases/main"
SRC="$(cd "$(dirname "$0")" && pwd)"
A="/usr/local/airlink"
CONF="$A/station.conf"
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ok()   { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
warn() { printf '  \033[33mAVISO\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31mFALLA\033[0m %s\n' "$*"; }
fin()  { echo; read -r -n1 -p "Tocá una tecla para cerrar…" _ < /dev/tty; echo; exit "${1:-0}"; }
get_kv() { sed -n "s/^$2=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$1" 2>/dev/null | tail -1; }

clear
echo "=================================================="
echo "  Airlink Station — instalación desde el SSD"
echo "  Origen: ${SRC}"
echo "=================================================="

# Volumen de origen (el SSD portátil): nunca usarlo como carpeta de IPSW de la estación
SRC_VOL=""
case "$SRC" in /Volumes/*) SRC_VOL="/Volumes/$(echo "${SRC#/Volumes/}" | cut -d/ -f1)" ;; esac

# Carpeta de IPSW destino: la ya configurada (si no está en el SSD portátil),
# si no AirlinkSSD (SSD fijo de la estación), si no el disco interno.
DEST="$(get_kv "$CONF" IPSW_DIR)"
case "$DEST" in
    "") ;;
    /Volumes/*) V="/Volumes/$(echo "${DEST#/Volumes/}" | cut -d/ -f1)"
                if [ "$V" = "$SRC_VOL" ] || [ ! -d "$V" ]; then DEST=""; fi ;;
esac
if [ -z "$DEST" ]; then
    if [ -d /Volumes/AirlinkSSD ] && [ "$SRC_VOL" != "/Volumes/AirlinkSSD" ]; then DEST="/Volumes/AirlinkSSD/IPSW"
    else DEST="$A/IPSW"; fi
fi
echo "  IPSW de la estación → ${DEST}"
echo

echo "== Contraseña de esta Mac (para instalar)"
sudo -v || { bad "Sin permisos de administrador"; fin 1; }
( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 $$ 2>/dev/null || exit; done ) &
KEEP=$!
trap 'kill $KEEP 2>/dev/null' EXIT

# ---------------------------------------------------------------- 1. instalar
T=$(mktemp /tmp/airlink-instalar.XXXXXX)
if ! curl -fsSL --retry 3 -o "$T" "$RAW/instalar.sh?t=$(date +%s)"; then
    bad "No pude bajar instalar.sh (¿hay internet?)"; rm -f "$T"; fin 1
fi
sudo /usr/bin/env IPSW_DIR="$DEST" /bin/bash "$T"
RC=$?
rm -f "$T"
echo
[ $RC -eq 0 ] || warn "instalar.sh terminó con errores (ver arriba). Igual copio los IPSW."

# ---------------------------------------------------------------- 2. Red
# Igual que la primera Mac Mini: cable (adaptador USB-C / Ethernet) primero para
# internet y descargas; WiFi de respaldo; el SQL por WiFi con una ruta fija.
echo "== Red: cable primero, WiFi de respaldo, SQL por WiFi"
sudo /usr/bin/python3 - <<'PY'
import re, subprocess
run = lambda *a: subprocess.run(a, capture_output=True, text=True).stdout
svcs = re.findall(r'^\((?:\d+|\*)\) (.+)$', run("networksetup", "-listnetworkserviceorder"), re.M)
wired = [s for s in svcs if re.search(r'LAN|Ethernet|AX88|USB|Adapter', s, re.I)
         and not re.search(r'iPhone|iPad|Thunderbolt|Bluetooth', s, re.I)]
wifi = [s for s in svcs if s == "Wi-Fi"]
order = wired + wifi + [s for s in svcs if s not in wired and s not in wifi]
if order and subprocess.run(["networksetup", "-ordernetworkservices"] + order).returncode == 0:
    print("  OK   Orden: " + " > ".join(order))
else:
    print("  AVISO No pude cambiar el orden de red")
PY
SQLH=$(sudo sed -n 's/^SQL_SERVER="\{0,1\}\([^",]*\).*/\1/p' "$A/sql.conf" 2>/dev/null | tail -1)
SQLP=$(sudo sed -n 's/^SQL_PORT="\{0,1\}\([0-9]*\).*/\1/p' "$A/sql.conf" 2>/dev/null | tail -1); SQLP="${SQLP:-1433}"
WIFIDEV=$(networksetup -listallhardwareports | awk '/Hardware Port: Wi-Fi/{getline; print $2}')
GW=""; for _ in 1 2 3 4 5 6 7 8 9 10; do GW=$(ipconfig getoption "$WIFIDEV" router 2>/dev/null); [ -n "$GW" ] && break; sleep 2; done
if ! echo "$SQLH" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    warn "No encontré la IP del SQL en sql.conf: sin ruta fija"
elif [ -z "$GW" ]; then
    warn "El WiFi no tiene conexión: el SQL va por el cable (conectá el WiFi y volvé a correr)"
else
    sudo networksetup -setadditionalroutes "Wi-Fi" "$SQLH" 255.255.255.255 "$GW" && sleep 2
    if nc -z -G 5 "$SQLH" "$SQLP" >/dev/null 2>&1; then ok "SQL por WiFi ($(route -n get "$SQLH" | awk '/interface/{print $2}'))"
    else warn "SQL no responde por WiFi: quito la ruta fija"; sudo networksetup -setadditionalroutes "Wi-Fi"; fi
fi
NETIF=$(route -n get api.ipsw.me 2>/dev/null | awk '/interface/{print $2}')
[ "$NETIF" = "$WIFIDEV" ] && warn "Internet sale por WiFi: el cable no tiene conexión" || ok "Internet por ${NETIF:-?}"
echo

# ---------------------------------------------------------------- 3. IPSW
echo "== Copiando IPSW del SSD"
sudo mkdir -p "$DEST" || { bad "No pude crear ${DEST}"; fin 1; }
N=0; TOTAL=0; COPIED=0; SKIPPED=0; FAILED=0
for f in "$SRC"/IPSW/*_Restore.ipsw; do [ -f "$f" ] && TOTAL=$((TOTAL + 1)); done
if [ $TOTAL -eq 0 ]; then
    warn "No hay *_Restore.ipsw en ${SRC}/IPSW — se bajan desde la app (pestaña IPSW → Descargar ahora)"
else
    NEED=0
    for f in "$SRC"/IPSW/*_Restore.ipsw; do
        d="$DEST/$(basename "$f")"; s=$(stat -f %z "$f")
        [ -f "$d" ] && [ "$(stat -f %z "$d")" = "$s" ] || NEED=$((NEED + s))
    done
    FREE=$(( $(df -k "$DEST" | awk 'NR==2{print $4}') * 1024 ))
    if [ $NEED -gt $FREE ]; then
        bad "Falta espacio en ${DEST}: hacen falta $((NEED / 1073741824)) GB y hay $((FREE / 1073741824)) GB libres"; fin 1
    fi
    for f in "$SRC"/IPSW/*_Restore.ipsw; do
        N=$((N + 1)); b=$(basename "$f"); d="$DEST/$b"
        if [ -f "$d" ] && [ "$(stat -f %z "$d")" = "$(stat -f %z "$f")" ]; then
            ok "[$N/$TOTAL] ${b} (ya estaba)"; SKIPPED=$((SKIPPED + 1)); continue
        fi
        printf '  …    [%s/%s] %s (%s)\n' "$N" "$TOTAL" "$b" "$(du -h "$f" | cut -f1)"
        # copia a un nombre temporal y renombra: el motor nunca ve un IPSW a medias
        if sudo cp "$f" "$DEST/.${b}.part" && sudo mv -f "$DEST/.${b}.part" "$d"; then
            ok "[$N/$TOTAL] ${b}"; COPIED=$((COPIED + 1))
        else
            sudo rm -f "$DEST/.${b}.part"; bad "[$N/$TOTAL] ${b}"; FAILED=$((FAILED + 1))
        fi
    done
    sudo chown root:wheel "$DEST"/*_Restore.ipsw 2>/dev/null
    sudo chmod 644 "$DEST"/*_Restore.ipsw 2>/dev/null
    sudo xattr -c "$DEST"/*_Restore.ipsw 2>/dev/null
    echo "  Copiados ${COPIED}, ya estaban ${SKIPPED}, fallaron ${FAILED}"
fi

# ---------------------------------------------------------------- resumen
echo
echo "== Resultado"
[ -f "$A/VERSION" ] && ok "Airlink Station $(cat "$A/VERSION")"
ok "IPSW en ${DEST}: $(ls "$DEST"/*_Restore.ipsw 2>/dev/null | wc -l | tr -d ' ') archivos"
if [ $RC -eq 0 ] && [ $FAILED -eq 0 ]; then
    echo "  ✅ Lista. Abrí Airlink Station, iniciá sesión con tu DR#### y conectá un iPhone."
    echo "     Ya podés expulsar el SSD."
    fin 0
fi
bad "Hubo errores (ver arriba). Podés volver a hacer doble clic: lo que ya está no se repite."
fin 1
