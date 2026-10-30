# Airlink Station — instaladores

Solo los instaladores (`.pkg`) de **Airlink Station**, la estación de Wipe & Load de
iPhones de Airlink Distribution DR. Sin código fuente: se publican automáticamente desde
el repo privado en cada versión.

## Instalar (Mac Apple Silicon, macOS 13+)

Última versión estable:

```bash
curl -fL -o /tmp/AirlinkStation.pkg https://github.com/Virgax/airlink-station-releases/releases/latest/download/AirlinkStation-arm64.pkg
sudo installer -pkg /tmp/AirlinkStation.pkg -target /
```

Una versión puntual (también candidatas `-rcN`): cambiar `latest/download` por
`download/vX.Y.Z`. Cada release trae su `.sha256`.

Después de instalar, la estación necesita su configuración y secretos (login, SQL,
identidad de supervisión), que **no** están en el paquete:

```bash
sudo /usr/local/airlink/engine/current/support/provision_secrets.sh /Volumes/USB/airlink-secrets
```

Las actualizaciones siguientes llegan solas: la app muestra "Nueva versión disponible →
Actualizar".

Uso interno de Airlink Distribution.
