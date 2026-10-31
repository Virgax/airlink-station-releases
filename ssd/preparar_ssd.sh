#!/bin/bash
# =============================================================================
#  AIRLINK STATION — preparar el SSD portátil de instalación
#
#  Se corre UNA vez en una estación que ya funciona (con sus IPSW):
#     curl -fsSL https://raw.githubusercontent.com/Virgax/airlink-station-releases/main/ssd/preparar_ssd.sh | bash
#     (o:  … | bash -s "/Volumes/MiSSD")
#
#  Deja en la raíz del SSD:
#     Instalar Airlink.command   ← doble clic en cada Mac nueva
#     IPSW/*_Restore.ipsw        ← copia de los IPSW de esta estación
#  Sin secretos: el kit se baja cifrado y la frase se pide al instalar.
# =============================================================================
RAW="https://raw.githubusercontent.com/Virgax/airlink-station-releases/main"
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
ok()   { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
bad()  { printf '  \033[31mFALLA\033[0m %s\n' "$*"; }
get_kv() { sed -n "s/^$2=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$1" 2>/dev/null | tail -1; }

SSD="${1:-}"
if [ -z "$SSD" ]; then
    echo "Discos conectados:"
    i=0
    for v in /Volumes/*; do
        [ -d "$v" ] || continue
        case "$(basename "$v")" in "Macintosh HD"|"Macintosh HD - Data"|com.apple*|.timemachine) continue ;; esac
        [ "$(df "$v" | awk 'NR==2{print $1}')" = "$(df / | awk 'NR==2{print $1}')" ] && continue
        i=$((i + 1)); eval "V$i=\"\$v\""
        printf '   %s) %s  (%s libres)\n' "$i" "$v" "$(df -h "$v" | awk 'NR==2{print $4}')"
    done
    [ $i -gt 0 ] || { bad "No veo ningún SSD externo conectado"; exit 1; }
    read -r -p "Número del SSD portátil: " n < /dev/tty
    eval "SSD=\"\${V$n:-}\""
    [ -n "$SSD" ] || { bad "Opción inválida"; exit 1; }
fi
[ -d "$SSD" ] && touch "$SSD/.airlink_test" 2>/dev/null && rm -f "$SSD/.airlink_test" \
    || { bad "No puedo escribir en ${SSD} (¿formato NTFS? usá APFS o exFAT)"; exit 1; }
[ "$SSD" = "/Volumes/AirlinkSSD" ] && echo "  (ojo: este es el SSD fijo de la estación; normalmente se usa otro)"

SRC="$(get_kv /usr/local/airlink/station.conf IPSW_DIR)"; SRC="${SRC:-/usr/local/airlink/IPSW}"
echo "== IPSW: ${SRC} → ${SSD}/IPSW"
mkdir -p "$SSD/IPSW" || { bad "No pude crear ${SSD}/IPSW"; exit 1; }
NEED=0
for f in "$SRC"/*_Restore.ipsw; do
    [ -f "$f" ] || continue; d="$SSD/IPSW/$(basename "$f")"
    [ -f "$d" ] && [ "$(stat -f %z "$d")" = "$(stat -f %z "$f")" ] || NEED=$((NEED + $(stat -f %z "$f")))
done
FREE=$(( $(df -k "$SSD" | awk 'NR==2{print $4}') * 1024 ))
[ $NEED -le $FREE ] || { bad "Falta espacio en el SSD: $((NEED / 1073741824)) GB necesarios, $((FREE / 1073741824)) GB libres"; exit 1; }
FAILED=0
for f in "$SRC"/*_Restore.ipsw; do
    [ -f "$f" ] || continue; b=$(basename "$f"); d="$SSD/IPSW/$b"
    if [ -f "$d" ] && [ "$(stat -f %z "$d")" = "$(stat -f %z "$f")" ]; then ok "${b} (ya estaba)"; continue; fi
    printf '  …    %s (%s)\n' "$b" "$(du -h "$f" | cut -f1)"
    if cp "$f" "$SSD/IPSW/.${b}.part" && mv -f "$SSD/IPSW/.${b}.part" "$d"; then ok "$b"
    else rm -f "$SSD/IPSW/.${b}.part"; bad "$b"; FAILED=1; fi
done

echo "== Instalador"
if curl -fsSL --retry 3 -o "$SSD/Instalar Airlink.command" "$RAW/ssd/Instalar_Airlink.command?t=$(date +%s)"; then
    chmod +x "$SSD/Instalar Airlink.command"; xattr -c "$SSD/Instalar Airlink.command" 2>/dev/null
    ok "${SSD}/Instalar Airlink.command"
else bad "No pude bajar Instalar Airlink.command"; FAILED=1; fi

echo
if [ $FAILED -eq 0 ]; then
    echo "  ✅ SSD listo: $(ls "$SSD"/IPSW/*_Restore.ipsw 2>/dev/null | wc -l | tr -d ' ') IPSW + Instalar Airlink.command"
    echo "     En cada Mac nueva: conectá el SSD y hacé doble clic en «Instalar Airlink.command»."
else bad "Hubo errores (ver arriba); volvé a correrlo, lo que ya está no se repite."; exit 1; fi
