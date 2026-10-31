# Airlink Station — instaladores

Instaladores (`.pkg`) de **Airlink Station**, la estación de Wipe & Load de iPhones de
Airlink Distribution DR. Sin código fuente: se publican automáticamente desde el repo
privado en cada versión.

## Dejar una Mac lista — un solo comando

Mac Apple Silicon (macOS 13+), con la sesión del usuario de la estación iniciada y
**Apple Configurator** instalado desde el App Store:

```bash
curl -fsSL https://raw.githubusercontent.com/Virgax/airlink-station-releases/main/instalar.sh | sudo bash
```

Pide la **frase clave del kit** (está en el gestor de contraseñas) y hace todo: Command
Line Tools, `cfgutil`, la última versión de Airlink Station, la configuración de la
estación (nombre = el de la Mac), login, SQL, identidad de supervisión y WiFi, y prueba
que todo conecte. Se puede repetir las veces que haga falta.

Opciones: `curl … | sudo STATION_ID=AIRLINK-M4-02 UPDATE_CHANNEL=stable bash`

Después, las actualizaciones llegan solas: la app muestra "Nueva versión → Actualizar".

## Instalar desde un SSD portátil (con los IPSW)

En una estación que ya funciona, con el SSD portátil conectado (APFS o exFAT, ~100 GB libres):

```bash
curl -fsSL https://raw.githubusercontent.com/Virgax/airlink-station-releases/main/ssd/preparar_ssd.sh | bash
```

Copia los IPSW de esa estación a `IPSW/` en el SSD y deja **`Instalar Airlink.command`** en la raíz.
En cada Mac nueva: conectá el SSD y **doble clic** en `Instalar Airlink.command`. Pide la contraseña
de la Mac y la frase del kit, corre `instalar.sh`, deja la red como la primera Mac Mini (cable por adaptador primero para
internet, WiFi de respaldo y el SQL por WiFi con ruta fija) y copia los IPSW a la carpeta de la estación.

## Solo el instalador

```bash
curl -fL -o /tmp/AirlinkStation.pkg https://github.com/Virgax/airlink-station-releases/releases/latest/download/AirlinkStation-arm64.pkg
sudo installer -pkg /tmp/AirlinkStation.pkg -target /
```

(`latest` = última versión final; una puntual o una rc: `download/vX.Y.Z-rcN/…`)

## Kit de secretos

Ver [`kit/`](kit/). Está cifrado; los scripts `instalar.sh` y `crear_kit.sh` no contienen
secretos.

Uso interno de Airlink Distribution.
