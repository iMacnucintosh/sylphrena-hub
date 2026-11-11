# VPN FortiClient

Extensión de Sylphrena: conexiones VPN FortiClient (`openfortivpn`) en **Nexus → Red**, conectables desde el icono VPN de la barra.

## Qué ofrece

- Un **tipo de proveedor** nuevo en «Añadir proveedor»: cada conexión guarda servidor, puerto, realm, usuario y contraseña, y además:
  - **OTP** opcional (diálogo en el icono VPN de la barra),
  - TLS antiguo (`seclevel-1`) y rutas de medio Internet,
  - certificado y clave de cliente, y `trusted-cert`,
  - **host de comprobación** (si deja de responder, p. ej. tras suspender, se cierra el túnel),
  - servidores y dominios DNS (con systemd-resolved) y entradas de `/etc/hosts` mientras hay conexión.
- Varias conexiones, una conectada a la vez.
- **Copia de seguridad:** Exportar e Importar las conexiones (tarjeta de la extensión, o la primera fila de «Añadir proveedor»). El fichero va sin contraseñas ni claves privadas salvo que lo pidas; entonces se cifra con una frase de paso (openssl AES-256, PBKDF2).

## Dónde se guarda

- Lo no secreto, en el `shell.json` de cada usuario (`utilities.vpn.provider`).
- La contraseña, solo en `~/.config/sylphrena/vpn/<id>.conf` (permisos 600), nunca en `shell.json`.

## Instalación y permisos

`openfortivpn` necesita root. Al instalar el zip se pide la contraseña una vez y se instalan, con la extensión: `openfortivpn` (si falta), el ayudante `/usr/local/sbin/sylphrena-fortivpn` y una regla de sudoers limitada a ese ayudante. El ayudante lee la configuración **como tu usuario**, solo acepta opciones conocidas de openfortivpn (nada de `pppd-*`) y la copia a `/run` (solo root). Al eliminar la extensión se quita todo.

Se instala desde zip: ver el README de la raíz.
