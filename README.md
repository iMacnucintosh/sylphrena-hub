# Sylphrena Hub

Extensiones (y, con el tiempo, widgets y más) para la shell [Sylphrena](https://github.com/iMacnucintosh/sylphrena-shell),
y el catálogo que lee **Things**.

## Qué hay

| Extensión | Qué hace |
| --- | --- |
| [`vpn-forticlient`](extensions/vpn-forticlient) | Añade conexiones VPN FortiClient (openfortivpn) a Nexus → Red, con códigos OTP y certificados de cliente |

El catálogo completo, con versiones, enlaces de descarga y `sha256`, está en [`index.json`](index.json).

## Instalar una extensión

1. Descarga el zip de la última *release* de la extensión (pestaña **Releases**).
2. En Sylphrena: **Nexus → Extensiones → Instalar desde zip → Examinar** y elige el zip.
   Si la extensión necesita permisos de administrador, te pide la contraseña en ese momento.
3. Queda activada al terminar.

Eliminarla (papelera en su tarjeta) quita también lo que instaló como administrador y sus conexiones o datos de sistema.

## La ficha de cada extensión (`store/`)

Lo que Things enseña al abrir una extensión (descripción larga, puntos destacados, novedades por versión, enlaces y capturas)
vive en `extensions/<id>/store/` y **no va dentro del zip**:

- `details.json`: `about`, `highlights` (hasta 6), `author`, `license`, `links` (`source`, `issues`, `web`; solo https), `changelog`
  (`version`, `date`, `changes`) y `screenshots` (`file` + `caption`).
- `screenshots/`: imágenes png, jpg o webp de hasta 1,5 MB (máximo 6). Sin datos personales: usa datos de ejemplo.
- `i18n/<idioma>.json`: texto en inglés → traducción, para todo lo anterior.

`scripts/build.py` valida todo y genera `store/<id>.json` (lo que descarga Things); el índice lo enlaza. **Los requisitos** (`requires`),
lo que **toca en el equipo** (`system`, `data`) salen del manifiesto, sin escribirlos dos veces.

## Para quien publique aquí

Cada extensión es una carpeta `extensions/<id>/` con su `manifest.json` (ver `AGENTS.md` de Sylphrena, sección «Extensiones»).
Las reglas del proyecto valen también aquí:

- **i18n siempre:** todo texto visible va por `Tr.*` y se traduce; el catálogo de la extensión vive en `i18n/es.json`.
- **Nada privado:** ni credenciales, ni hosts, ni datos de tu red. La configuración de cada persona vive en su `shell.json` y en sus propios ficheros.

```bash
scripts/build.py            # genera dist/<id>-<versión>.zip y reescribe index.json
scripts/build.py --check    # comprueba que index.json está al día (para CI)
scripts/publish.sh <id>     # publica el zip como release <id>-<versión>
```

Para sacar una versión nueva: sube `version` en el manifiesto, `scripts/build.py`, commit, `scripts/publish.sh <id>`.
Los zips son deterministas: las mismas fuentes dan los mismos bytes.

## Licencia

GPL-3.0, como Sylphrena (ver [`LICENSE`](LICENSE)).
