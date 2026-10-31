# kit/

Acá va **`airlink-kit.enc`**: los secretos de la flota (login, SQL, WiFi, identidad de
supervisión) **cifrados** con AES-256 (clave por PBKDF2-SHA256, 600.000 iteraciones).
Sin la frase clave es ilegible. La frase clave NO está en ningún repo.

Se crea en una estación que ya funciona (Airlink12):

```bash
curl -fsSL https://raw.githubusercontent.com/Virgax/airlink-station-releases/main/crear_kit.sh | sudo bash
```

y se sube a esta carpeta (Add file → Upload files).
