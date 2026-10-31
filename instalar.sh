#!/bin/bash
# =============================================================================
#  AIRLINK STATION — dejar una Mac lista con UN comando
#
#     curl -fsSL https://raw.githubusercontent.com/Virgax/airlink-station-releases/main/instalar.sh | sudo bash
#
#  Pide la frase clave del kit de la flota y hace todo: Command Line Tools,
#  cfgutil, instala la última versión de Airlink Station, repara la firma,
#  configura la estación (STATION_ID = nombre de la Mac), instala login, SQL,
#  identidad de supervisión y WiFi desde el KIT CIFRADO (kit/airlink-kit.enc,
#  creado con crear_kit.sh), y prueba login y SQL. Se puede repetir.
#
#  Este script no contiene secretos. Opciones (variables de entorno):
#    STATION_ID=…   UPDATE_CHANNEL=rc|stable   IPSW_DIR=…   PKG_VERSION=vX.Y.Z
#    KIT_FILE=/ruta/airlink-kit.enc (en vez de bajarlo)
#    curl … | sudo STATION_ID=AIRLINK-M4-02 bash
# =============================================================================
STATION_ID="${STATION_ID:-}"
UPDATE_CHANNEL_OVERRIDE="${UPDATE_CHANNEL:-}"
IPSW_DIR="${IPSW_DIR:-}"
PKG_VERSION="${PKG_VERSION:-}"
KIT_URL="${KIT_URL:-https://raw.githubusercontent.com/Virgax/airlink-station-releases/main/kit/airlink-kit.enc}"
PUBLIC_REPO="Virgax/airlink-station-releases"
EMPLOYEE_ENDPOINT=""; SQL_SERVER=""; SQL_PORT=""; SQL_DATABASE=""; SQL_USER=""; SQL_PASSWORD=""
WIFI_SSID=""; WIFI_PASSWORD=""; UPDATE_CHANNEL="rc"

set -u
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
KIT=""
W=$(mktemp -d /tmp/airlink-install.XXXXXX); chmod 700 "$W"; trap 'rm -rf "$W"' EXIT
A=/usr/local/airlink
CONF="$A/station.conf"
RELEASES="https://github.com/Virgax/airlink-station-releases/releases/download"
STAMP=$(date +%Y%m%d_%H%M%S)
FAILS=0; WARNS=0
ok()   { printf '  \033[32mOK  \033[0m %s\n' "$*"; }
warn() { printf '  \033[33mAVISO\033[0m %s\n' "$*"; WARNS=$((WARNS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAILS=$((FAILS+1)); }
hdr()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
set_kv() {   # set_kv <archivo> <KEY> <valor>: reemplaza o agrega KEY="valor"
    local tmp="$1.tmp.$$"
    awk -v k="$2" -v v="$3" 'BEGIN{d=0} $0 ~ "^[[:space:]]*"k"=" {print k"=\""v"\""; d=1; next} {print} END{if(!d) print k"=\""v"\""}' "$1" > "$tmp" && mv "$tmp" "$1"
}
get_kv() { { grep -E "^[[:space:]]*$2=" "$1" 2>/dev/null || true; } | tail -1 | cut -d= -f2- | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//'; }

[ "$(id -u)" -eq 0 ] || { echo "Correr con sudo:  curl -fsSL …/instalar.sh | sudo bash"; exit 1; }
[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ] || { echo "Solo Mac Apple Silicon"; exit 1; }

# Estación vieja de producción (motor instalado a mano, sin el .pkg): no tocar
if [ ! -f "$A/VERSION" ] && [ -f /usr/local/bin/wipe_and_restore.sh ] && [ "${1:-}" != "--forzar" ]; then
    echo "Esta Mac ya tiene el motor viejo instalado a mano (¿Airlink12?)."
    echo "No la configuro para no pisar producción. Si es a propósito: curl … | sudo bash -s -- --forzar"
    exit 1
fi

# ---- 0. Requisitos de la Mac (se instalan solos si se puede) ----
hdr "0. Requisitos"
# Command Line Tools: /usr/bin/python3 (motor, dashboard, SQL, login). Sin ellas
# python3 es un "esqueleto" que solo abre un diálogo.
if xcode-select -p >/dev/null 2>&1 && /usr/bin/python3 -c 'import hashlib' >/dev/null 2>&1; then
    ok "Command Line Tools"
else
    echo "  Instalando Command Line Tools de Apple (sin diálogo, 5–15 min)…"
    FLAG=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    touch "$FLAG"
    CLT=$(softwareupdate -l 2>/dev/null | grep -E '\* Label: Command Line Tools' | sed 's/^.*Label: //' | tail -1)
    if [ -n "$CLT" ] && softwareupdate -i "$CLT" >/dev/null 2>&1 \
        && xcode-select -p >/dev/null 2>&1 && /usr/bin/python3 -c 'import hashlib' >/dev/null 2>&1; then
        rm -f "$FLAG"; ok "Command Line Tools instaladas ($CLT)"
    else
        rm -f "$FLAG"
        bad "No pude instalar las Command Line Tools solo. Corré:  xcode-select --install  (aceptá el diálogo) y volvé a correr el comando"
        exit 1
    fi
fi

# cfgutil: viene dentro de Apple Configurator; "Install Automation Tools" solo lo
# enlaza en /usr/local/bin. Si la app está, lo enlazamos acá.
if [ ! -x /usr/local/bin/cfgutil ]; then
    for app in "/Applications/Apple Configurator.app" "/Applications/Apple Configurator 2.app"; do
        if [ -x "$app/Contents/MacOS/cfgutil" ]; then
            mkdir -p /usr/local/bin && ln -sf "$app/Contents/MacOS/cfgutil" /usr/local/bin/cfgutil
            break
        fi
    done
fi
if [ -x /usr/local/bin/cfgutil ]; then
    ok "cfgutil ($(/usr/local/bin/cfgutil version 2>/dev/null | head -1))"
    # el daemon on-attach no arranca sin cfgutil: recargarlo ahora que está
    launchctl kickstart -k system/com.airlink.wipeandrestore >/dev/null 2>&1
else
    bad "Falta Apple Configurator: se abre el App Store; instalalo, abrilo una vez y volvé a correr el comando"
    open "macappstore://apps.apple.com/app/apple-configurator/id1037126344" 2>/dev/null
fi

# Python del motor
if /usr/bin/python3 -c 'import openpyxl, pymssql' >/dev/null 2>&1; then
    ok "Python: openpyxl y pymssql"
elif /usr/bin/python3 -m pip install -q --disable-pip-version-check openpyxl pymssql >/dev/null 2>&1 \
    && /usr/bin/python3 -c 'import openpyxl, pymssql' >/dev/null 2>&1; then
    ok "Python: openpyxl y pymssql instalados"
else
    bad "No pude instalar openpyxl/pymssql:  sudo /usr/bin/python3 -m pip install openpyxl pymssql"
fi

# ---- Kit cifrado: login, SQL, WiFi e identidad ----
hdr "Kit de la flota"
KF="$W/airlink-kit.enc"
if [ -n "${KIT_FILE:-}" ] && [ -f "$KIT_FILE" ]; then cp "$KIT_FILE" "$KF"
else curl -fsSL --retry 3 -o "$KF" "$KIT_URL" || { bad "No pude bajar el kit ($KIT_URL)"; exit 1; }; fi
[ "$(head -c 7 "$KF")" = "AIRKIT1" ] || { bad "El archivo no es un kit de Airlink"; exit 1; }
SALT=$(dd if="$KF" bs=1 skip=7 count=16 2>/dev/null | od -An -tx1 | tr -d ' \n')
TRY=0
while :; do
    TRY=$((TRY + 1))
    if [ -n "${AIRLINK_KIT_PASS:-}" ] && [ "$TRY" -eq 1 ]; then
        PASS="$AIRLINK_KIT_PASS"   # automatización/pruebas
    else
        printf '  Frase clave del kit: ' > /dev/tty
        stty -echo < /dev/tty 2>/dev/null; read -r PASS < /dev/tty; stty echo < /dev/tty 2>/dev/null; echo > /dev/tty
    fi
    DK=$(AIRLINK_KIT_PASS="$PASS" /usr/bin/python3 -c 'import hashlib,os,sys; print(hashlib.pbkdf2_hmac("sha256", os.environ["AIRLINK_KIT_PASS"].encode(), bytes.fromhex(sys.argv[1]), 600000, 48).hex())' "$SALT" 2>"$W/py.err")
    if [ "${#DK}" -ne 96 ] || [ "${#SALT}" -ne 32 ]; then
        bad "No pude calcular la clave (no es la frase): Python de Apple no responde. $(head -1 "$W/py.err" 2>/dev/null | cut -c1-120)"
        echo "     Corré:  xcode-select --install   (aceptá el diálogo), esperá que termine y repetí el comando."
        exit 1
    fi
    if ! tail -c +24 "$KF" | openssl enc -d -aes-256-cbc -K "${DK:0:64}" -iv "${DK:64:32}" > "$W/kit.tgz" 2>"$W/ssl.err"; then
        :   # "bad decrypt" = frase incorrecta
    elif tar -xzf "$W/kit.tgz" -C "$W" 2>/dev/null && [ -f "$W/kit/kit.conf" ]; then
        rm -f "$W/kit.tgz"
        break
    else
        bad "El kit se descifró pero está dañado (volvé a crearlo con crear_kit.sh y subilo de nuevo)"
        exit 1
    fi
    [ "$TRY" -ge 3 ] || [ -n "${AIRLINK_KIT_PASS:-}" ] && { bad "Frase clave incorrecta"; exit 1; }
    echo "  Frase clave incorrecta ($(head -1 "$W/ssl.err" | cut -c1-60)), probá de nuevo. Mayúsculas/minúsculas importan."
done
unset PASS DK
KIT="$W/kit"
kv() { { grep -E "^$1=" "$KIT/kit.conf" || true; } | tail -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }
EMPLOYEE_ENDPOINT=$(kv EMPLOYEE_ENDPOINT); SQL_SERVER=$(kv SQL_SERVER); SQL_PORT=$(kv SQL_PORT)
SQL_DATABASE=$(kv SQL_DATABASE); SQL_USER=$(kv SQL_USER); SQL_PASSWORD=$(kv SQL_PASSWORD)
WIFI_SSID=$(kv WIFI_SSID); WIFI_PASSWORD=$(kv WIFI_PASSWORD)
UPDATE_CHANNEL="${UPDATE_CHANNEL_OVERRIDE:-$(kv UPDATE_CHANNEL)}"; UPDATE_CHANNEL="${UPDATE_CHANNEL:-rc}"
case "$EMPLOYEE_ENDPOINT" in http*) ok "Kit descifrado (login, SQL $SQL_DATABASE$( [ -f "$KIT/supervision_key.der" ] && echo ', identidad')$( [ -f "$KIT/airlink_wifi.mobileconfig" ] || [ -n "$WIFI_SSID" ] && echo ', WiFi'))" ;;
    *) bad "El kit no tiene la URL del login"; exit 1 ;; esac

# Última versión publicada (incluye rc si el canal es rc)
if [ -z "$PKG_VERSION" ]; then
    PKG_VERSION=$(curl -fsSL "https://api.github.com/repos/$PUBLIC_REPO/releases?per_page=20" 2>/dev/null | /usr/bin/python3 -c '
import json, sys
ch = sys.argv[1]
for r in json.load(sys.stdin):
    if r.get("draft") or (r.get("prerelease") and ch != "rc"):
        continue
    print(r["tag_name"]); break' "$UPDATE_CHANNEL" 2>/dev/null)
fi
[ -n "$PKG_VERSION" ] || { bad "No pude saber cuál es la última versión publicada"; exit 1; }

# ---- 1. Airlink Station instalada ----
hdr "1. Airlink Station"
INSTALLED=$(sed -n 's/^version=//p' "$A/VERSION" 2>/dev/null)
if [ -n "$INSTALLED" ] && [ "v$INSTALLED" = "$PKG_VERSION" ] && [ -d "/Applications/Airlink Station.app" ]; then
    ok "Ya instalada: $INSTALLED (la última)"
else
    [ -n "$INSTALLED" ] && echo "  Instalada $INSTALLED → actualizando a $PKG_VERSION"
    # shellcheck disable=SC2012
    [ "$(ls /tmp/airlink_wipe_*.lock 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ] || { bad "Hay equipos en proceso: desconectalos y volvé a correr"; exit 1; }
    D=$(mktemp -d /tmp/airlink-pkg.XXXXXX)
    echo "  Descargando $PKG_VERSION…"
    if curl -fsSL --retry 3 -o "$D/AirlinkStation-arm64.pkg" "$RELEASES/$PKG_VERSION/AirlinkStation-arm64.pkg" \
        && curl -fsSL --retry 3 -o "$D/AirlinkStation-arm64.pkg.sha256" "$RELEASES/$PKG_VERSION/AirlinkStation-arm64.pkg.sha256" \
        && (cd "$D" && shasum -a 256 -c AirlinkStation-arm64.pkg.sha256 >/dev/null); then
        if installer -pkg "$D/AirlinkStation-arm64.pkg" -target / >/dev/null; then ok "Instalada $PKG_VERSION"
        else bad "Falló la instalación (ver /var/log/airlink_install.log)"; exit 1; fi
    else
        bad "No pude bajar o verificar el .pkg ($PKG_VERSION)"; exit 1
    fi
    rm -rf "$D"
fi

# ---- 2. Firma de la app (2.3.0-rc1 venía sin firma válida → "contains malware") ----
APP="/Applications/Airlink Station.app"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null
if codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
    ok "Firma de la app válida"
else
    xattr -cr "$APP"
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1
    # Copia nueva: macOS recuerda la firma vieja de esos archivos y mataría la app
    ditto "$APP" "/tmp/AirlinkStation.$$.app" && rm -rf "$APP" && ditto "/tmp/AirlinkStation.$$.app" "$APP" && rm -rf "/tmp/AirlinkStation.$$.app"
    if codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then ok "Firma de la app reparada (ad-hoc)"
    else bad "La firma de la app sigue inválida"; fi
fi

# ---- 3. Estación (station.conf) ----
hdr "2. Estación"
[ -f "$CONF" ] || cp "$A/engine/current/config/station.conf.example" "$CONF"
cp -p "$CONF" "$CONF.prev-$STAMP"
[ -n "$STATION_ID" ] || STATION_ID=$(scutil --get LocalHostName 2>/dev/null || hostname -s)
SUSER=$(stat -f %Su /dev/console 2>/dev/null || true)
case "$SUSER" in ""|root|loginwindow|_mbsetupuser) SUSER=$(get_kv "$CONF" STATION_USER) ;; esac
id -u "$SUSER" >/dev/null 2>&1 || { bad "No sé qué usuario usa la estación: iniciá sesión con él y volvé a correr"; exit 1; }
if [ -z "$IPSW_DIR" ]; then
    if mount | grep -q " on /Volumes/AirlinkSSD ("; then IPSW_DIR="/Volumes/AirlinkSSD/IPSW"
    else IPSW_DIR="$A/IPSW"; warn "SSD AirlinkSSD no conectado: IPSW en el disco interno ($IPSW_DIR)"; fi
fi
mkdir -p "$IPSW_DIR"
set_kv "$CONF" STATION_ID "$STATION_ID"
set_kv "$CONF" STATION_USER "$SUSER"
set_kv "$CONF" IPSW_DIR "$IPSW_DIR"
set_kv "$CONF" UPDATE_CHANNEL "$UPDATE_CHANNEL"
chmod 644 "$CONF"
mkdir -p "$A/logs" && chown "$SUSER" "$A/logs"
ok "STATION_ID=$STATION_ID · usuario=$SUSER · IPSW=$IPSW_DIR · canal=$UPDATE_CHANNEL"

# sudoers del botón × / Actualizar para este usuario
TPL="$A/engine/current/sudoers/airlink-station.template"
if [ -f "$TPL" ]; then
    T=$(mktemp /tmp/airlink-sudoers.XXXXXX)
    sed "s/__STATION_USER__/$SUSER/g" "$TPL" > "$T"
    if visudo -cf "$T" >/dev/null 2>&1; then install -o root -g wheel -m 440 "$T" /etc/sudoers.d/airlink-station && ok "sudoers para $SUSER"
    else bad "sudoers inválido"; fi
    rm -f "$T"
fi

# ---- 4. Secretos ----
hdr "3. Login, SQL e identidad"
umask 077
backup() { [ -f "$1" ] && cp -p "$1" "$1.prev-$STAMP" && chmod 600 "$1.prev-$STAMP"; }
backup "$A/secrets.conf"
printf 'EMPLOYEE_ENDPOINT="%s"\n' "$EMPLOYEE_ENDPOINT" > "$A/secrets.conf"
# Grupo principal del usuario (en macOS suele ser "staff"; no existe un grupo con su nombre)
chown "root:$(id -gn "$SUSER")" "$A/secrets.conf"; chmod 640 "$A/secrets.conf"
# La app (corre como el usuario) tiene que poder leerlo
if sudo -u "$SUSER" test -r "$A/secrets.conf"; then ok "secrets.conf (login) → root:$(id -gn "$SUSER") 640"
else chmod 644 "$A/secrets.conf"; warn "secrets.conf quedó 644 (el grupo del usuario no permitía leerlo)"; fi

backup "$A/sql.conf"
{ printf 'SQL_SERVER="%s"\n' "$SQL_SERVER"; printf 'SQL_PORT="%s"\n' "$SQL_PORT"
  printf 'SQL_DATABASE="%s"\n' "$SQL_DATABASE"; printf 'SQL_USER="%s"\n' "$SQL_USER"
  printf '%s="%s"\n' SQL_PASSWORD "$SQL_PASSWORD"; } > "$A/sql.conf"
chown root:wheel "$A/sql.conf"; chmod 600 "$A/sql.conf"
ok "sql.conf (SQL Server) → root:wheel 600"

# Identidad de supervisión: del kit (o, si no viene, Escritorio / USB airlink-kit)
find_der() {
    local d
    for d in "$KIT" "/Users/$SUSER/Desktop" /Volumes/*/airlink-kit; do
        [ -f "$d/$1" ] && { echo "$d/$1"; return 0; }
    done
    return 1
}
for f in supervision_cert.der supervision_key.der; do
    SRCF=$(find_der "$f" || true)
    if [ -n "$SRCF" ]; then
        backup "/usr/local/bin/$f"
        if [ "$f" = supervision_key.der ]; then install -o root -g wheel -m 600 "$SRCF" "/usr/local/bin/$f"
        else install -o root -g wheel -m 644 "$SRCF" "/usr/local/bin/$f"; fi
        ok "$f (de $(dirname "$SRCF"))"
    elif [ -f "/usr/local/bin/$f" ]; then
        ok "$f (ya estaba)"
    else
        warn "Sin $f (el kit no la trae): los equipos van a quedar sin supervisar"
    fi
done
if [ -f /usr/local/bin/supervision_cert.der ] && [ -f /usr/local/bin/supervision_key.der ]; then
    CM=$(openssl x509 -inform der -in /usr/local/bin/supervision_cert.der -noout -modulus 2>/dev/null | shasum)
    KM=$(openssl rsa -inform der -in /usr/local/bin/supervision_key.der -noout -modulus 2>/dev/null | shasum)
    [ -n "$CM" ] && [ "$CM" = "$KM" ] && ok "La llave corresponde al certificado" || warn "No pude verificar que la llave corresponda al certificado"
fi

# WiFi para los iPhones
if [ -f "$KIT/airlink_wifi.mobileconfig" ]; then
    install -o root -g wheel -m 644 "$KIT/airlink_wifi.mobileconfig" /usr/local/bin/airlink_wifi.mobileconfig
    ok "Perfil WiFi (del kit)"
elif [ -n "$WIFI_SSID" ]; then
    xml_esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
    U1=$(uuidgen); U2=$(uuidgen)
    if [ -n "$WIFI_PASSWORD" ]; then
        ENC="<key>EncryptionType</key><string>WPA</string>
      <key>Password</key><string>$(xml_esc "$WIFI_PASSWORD")</string>"
    else
        ENC="<key>EncryptionType</key><string>None</string>"
    fi
    umask 022
    cat > /usr/local/bin/airlink_wifi.mobileconfig <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadType</key><string>Configuration</string>
  <key>PayloadVersion</key><integer>1</integer>
  <key>PayloadIdentifier</key><string>com.airlink.wifi</string>
  <key>PayloadUUID</key><string>$U1</string>
  <key>PayloadDisplayName</key><string>Airlink WiFi</string>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadType</key><string>com.apple.wifi.managed</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>PayloadIdentifier</key><string>com.airlink.wifi.1</string>
      <key>PayloadUUID</key><string>$U2</string>
      <key>PayloadDisplayName</key><string>WiFi $(xml_esc "$WIFI_SSID")</string>
      <key>SSID_STR</key><string>$(xml_esc "$WIFI_SSID")</string>
      <key>AutoJoin</key><true/>
      $ENC
    </dict>
  </array>
</dict>
</plist>
XML
    chown root:wheel /usr/local/bin/airlink_wifi.mobileconfig; chmod 644 /usr/local/bin/airlink_wifi.mobileconfig
    plutil -lint /usr/local/bin/airlink_wifi.mobileconfig >/dev/null 2>&1 && ok "Perfil WiFi ($WIFI_SSID)" || bad "Perfil WiFi inválido"
else
    warn "WIFI_SSID vacío: sin perfil WiFi (se puede agregar desde la app: Configuración → Redes WiFi)"
fi
umask 022

# Que el dashboard tome el STATION_ID nuevo
launchctl kickstart -k system/com.airlink.dashboard >/dev/null 2>&1

# ---- 5. Pruebas ----
hdr "4. Pruebas"
LOGIN=$(/usr/bin/python3 - <<'PY' 2>&1
import sys
sys.path.insert(0, "/usr/local/bin")
import airlink_auth as a
try:
    a.validate_employee("DR0000", "0000"); print("RESPONDE")
except a.AuthError as e:
    print("RESPONDE" if ("incorrecto" in str(e) or "inactivo" in str(e)) else "ERROR: %s" % e)
PY
)
[ "$LOGIN" = "RESPONDE" ] && ok "El login de operadores responde (Power Automate)" || bad "Login: $LOGIN"

SQLT="$A/engine/current/support/test_sql_connection.py"
if [ -f "$SQLT" ]; then
    if OUT=$(/usr/bin/python3 "$SQLT" "$A/sql.conf" 2>&1); then ok "SQL Server conecta y ejecuta el SP"
    else bad "SQL no conecta: $(echo "$OUT" | grep '✗' | head -1 | cut -c1-160 | sed -E -e 's/server=[^ ]*/server=<oculto>/' -e 's/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/<oculto>/g')"; fi
else
    warn "No encontré test_sql_connection.py (SQL sin probar)"
fi


hdr "Resultado"
if [ "$FAILS" -eq 0 ]; then
    printf '  \033[32m✅ %s lista\033[0m (%s avisos). Abrí Airlink Station e iniciá sesión con tu DR####.\n' "$STATION_ID" "$WARNS"
else
    printf '  \033[31m❌ %s problema(s)\033[0m — corregí lo marcado FAIL y volvé a correr el comando.\n' "$FAILS"
fi
echo "  Diagnóstico completo: sudo /usr/local/airlink/engine/current/support/doctor.sh"
[ "$FAILS" -eq 0 ]
