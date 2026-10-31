#!/bin/bash
# =============================================================================
#  AIRLINK STATION — crear el KIT CIFRADO de la flota (correr UNA vez, en una
#  estación que ya funciona, ej. Airlink12)
#
#     curl -fsSL https://raw.githubusercontent.com/Virgax/airlink-station-releases/main/crear_kit.sh | sudo bash
#
#  Junta login (Power Automate), SQL, WiFi e identidad de supervisión de ESTA
#  Mac, los cifra con una frase clave (AES-256, PBKDF2) y deja
#  ~/Desktop/airlink-kit.enc. Ese archivo se puede publicar: sin la frase clave
#  es ilegible. La frase clave NO se guarda en ningún lado: anotala en el gestor
#  de contraseñas.
#
#  Este script no contiene secretos.
# =============================================================================
set -u
[ "$(id -u)" -eq 0 ] || { echo "Correr con sudo"; exit 1; }
A=/usr/local/airlink
TTY=/dev/tty
get() { { grep -E "^[[:space:]]*$2=" "$1" 2>/dev/null || true; } | tail -1 | cut -d= -f2- | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//'; }
ask() { local v; printf '%s' "$1" > $TTY; read -r v < $TTY; printf '%s' "$v"; }

W=$(mktemp -d /tmp/airlink-kit.XXXXXX); chmod 700 "$W"; trap 'rm -rf "$W"' EXIT
umask 077
mkdir -p "$W/kit"

echo "== Datos de esta Mac"
EP=$(get "$A/secrets.conf" EMPLOYEE_ENDPOINT)
SQLF="$A/sql.conf"; [ -f "$SQLF" ] || SQLF="$A/secrets.conf"
SS=$(get "$SQLF" SQL_SERVER); SP=$(get "$SQLF" SQL_PORT); SD=$(get "$SQLF" SQL_DATABASE)
SU=$(get "$SQLF" SQL_USER); SW=$(get "$SQLF" SQL_PASSWORD)
case "$EP" in http*) echo "  OK  login (Power Automate)" ;; *) EP=$(ask "  URL del login (EMPLOYEE_ENDPOINT): ") ;; esac
[ -n "$SS" ] && echo "  OK  SQL ($SD)" || { SS=$(ask "  SQL_SERVER: "); SP=$(ask "  SQL_PORT [1433]: "); SD=$(ask "  SQL_DATABASE: "); SU=$(ask "  SQL_USER [AlAppUser]: "); SW=$(ask "  SQL_PASSWORD: "); }
{ printf 'EMPLOYEE_ENDPOINT="%s"\n' "$EP"
  printf 'SQL_SERVER="%s"\nSQL_PORT="%s"\nSQL_DATABASE="%s"\nSQL_USER="%s"\n' "$SS" "${SP:-1433}" "$SD" "${SU:-AlAppUser}"
  printf '%s="%s"\n' SQL_PASSWORD "$SW"
  printf 'UPDATE_CHANNEL="%s"\n' "${UPDATE_CHANNEL:-rc}"
} > "$W/kit/kit.conf"

for f in supervision_cert.der supervision_key.der; do
    if [ -f "/usr/local/bin/$f" ]; then cp "/usr/local/bin/$f" "$W/kit/$f"; echo "  OK  $f"
    else echo "  FALTA /usr/local/bin/$f — el kit no tendría identidad de supervisión. Cortando."; exit 1; fi
done
CM=$(openssl x509 -inform der -in "$W/kit/supervision_cert.der" -noout -modulus 2>/dev/null | shasum)
KM=$(openssl rsa -inform der -in "$W/kit/supervision_key.der" -noout -modulus 2>/dev/null | shasum)
[ -n "$CM" ] && [ "$CM" = "$KM" ] && echo "  OK  la llave corresponde al certificado" || echo "  AVISO no pude verificar llave ↔ certificado"

if [ -f /usr/local/bin/airlink_wifi.mobileconfig ]; then
    cp /usr/local/bin/airlink_wifi.mobileconfig "$W/kit/"; echo "  OK  perfil WiFi de esta Mac"
else
    WS=$(ask "  Red WiFi para los iPhones (SSID, vacío = ninguna): ")
    if [ -n "$WS" ]; then WP=$(ask "  Contraseña de $WS: "); printf 'WIFI_SSID="%s"\n' "$WS" >> "$W/kit/kit.conf"; printf '%s="%s"\n' WIFI_PASSWORD "$WP" >> "$W/kit/kit.conf"; fi
fi

echo "== Frase clave"
if [ -n "${AIRLINK_KIT_PASS:-}" ]; then
    P1="$AIRLINK_KIT_PASS"   # automatización/pruebas
else
    printf '  Elegí una frase clave larga (16+ caracteres) o Enter para generar una: ' > $TTY
    stty -echo < $TTY 2>/dev/null; read -r P1 < $TTY; stty echo < $TTY 2>/dev/null; echo > $TTY
fi
if [ -n "${AIRLINK_KIT_PASS:-}" ]; then
    :
elif [ -z "$P1" ]; then
    P1=$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)
    printf '\n  Frase clave generada:  %s\n  ANOTALA AHORA en el gestor de contraseñas (no se vuelve a mostrar).\n\n' "$P1" > $TTY
else
    [ "${#P1}" -ge 16 ] || { echo "  Muy corta (mínimo 16). Cortando."; exit 1; }
    printf '  Repetila: ' > $TTY; stty -echo < $TTY 2>/dev/null; read -r P2 < $TTY; stty echo < $TTY 2>/dev/null; echo > $TTY
    [ "$P1" = "$P2" ] || { echo "  No coinciden. Cortando."; exit 1; }
fi

REAL_USER="${SUDO_USER:-$(stat -f %Su /dev/console)}"
OUT="/Users/$REAL_USER/Desktop/airlink-kit.enc"
# Formato: "AIRKIT1" + sal (16 bytes) + AES-256-CBC(tar.gz). Clave e IV con
# PBKDF2-SHA256 (600.000 iteraciones) del Python de Apple: no depende de la
# versión de openssl/LibreSSL de cada Mac.
SALT=$(openssl rand -hex 16)
DK=$(AIRLINK_KIT_PASS="$P1" /usr/bin/python3 -c 'import hashlib,os,sys; print(hashlib.pbkdf2_hmac("sha256", os.environ["AIRLINK_KIT_PASS"].encode(), bytes.fromhex(sys.argv[1]), 600000, 48).hex())' "$SALT")
[ "${#DK}" -eq 96 ] || { echo "  No pude derivar la clave (¿Command Line Tools?)"; exit 1; }
{ printf 'AIRKIT1'; /usr/bin/python3 -c 'import sys; sys.stdout.buffer.write(bytes.fromhex(sys.argv[1]))' "$SALT"; ( cd "$W" && tar -czf - kit ) | openssl enc -aes-256-cbc -K "${DK:0:64}" -iv "${DK:64:32}"; } > "$OUT" \
    || { echo "  No pude cifrar el kit"; exit 1; }
# verificación: se descifra con la misma frase
tail -c +24 "$OUT" | openssl enc -d -aes-256-cbc -K "${DK:0:64}" -iv "${DK:64:32}" | tar -tzf - >/dev/null 2>&1 \
    || { echo "  El kit no se pudo verificar"; rm -f "$OUT"; exit 1; }
chown "$REAL_USER" "$OUT"; chmod 644 "$OUT"
echo "== Listo: $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes, verificado)"
echo "   Subilo a https://github.com/Virgax/airlink-station-releases/upload/main/kit"
echo "   (arrastrar el archivo → Commit changes). Está cifrado: se puede publicar."
