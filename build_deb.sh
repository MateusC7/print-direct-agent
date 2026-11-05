#!/bin/bash
set -e

ROOT="/mnt/d/Users/mateo/Documentos/SoftwareRestaurante Print App/PrintAppS/print_app"
OUT="$ROOT/dist_linux"
BUNDLE="$ROOT/build/linux/x64/release/bundle"

mkdir -p "$OUT"

TMP_DEB="/tmp/software_restaurante_deb_build"
rm -rf "$TMP_DEB"
mkdir -p "$TMP_DEB/opt/software-restaurante"
mkdir -p "$TMP_DEB/usr/bin"
mkdir -p "$TMP_DEB/usr/share/applications"
mkdir -p "$TMP_DEB/usr/share/pixmaps"
mkdir -p "$TMP_DEB/etc/xdg/autostart"
mkdir -p "$TMP_DEB/DEBIAN"

# Copiar bundle
cp -r "$BUNDLE/"* "$TMP_DEB/opt/software-restaurante/"
cp "$ROOT/assets/images/logo_restaurant.png" "$TMP_DEB/usr/share/pixmaps/software-restaurante.png"

# Binario ejecutable en /usr/bin/software-restaurante
cat << 'EOF' > "$TMP_DEB/usr/bin/software-restaurante"
#!/bin/bash
exec /opt/software-restaurante/print_app "$@"
EOF
chmod +x "$TMP_DEB/usr/bin/software-restaurante"

# Acceso directo para el menú de aplicaciones
cat << 'EOF' > "$TMP_DEB/usr/share/applications/software-restaurante.desktop"
[Desktop Entry]
Name=Software Restaurante
GenericName=Agente de Impresion
Comment=Agente de Impresion Local y Servicios IoT - SoftwareRestaurante
Exec=/opt/software-restaurante/print_app
Icon=software-restaurante
Terminal=false
Type=Application
Categories=Office;Utility;
StartupNotify=false
EOF

# Autoarranque del sistema (cuando se enciende/inicia sesion en segundo plano)
cat << 'EOF' > "$TMP_DEB/etc/xdg/autostart/software-restaurante.desktop"
[Desktop Entry]
Type=Application
Name=Software Restaurante
Comment=Agente de Impresion Local
Exec=/opt/software-restaurante/print_app --background
Icon=software-restaurante
Terminal=false
StartupNotify=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
EOF

# Control file Debian
cat << 'EOF' > "$TMP_DEB/DEBIAN/control"
Package: software-restaurante
Version: 2.0.0
Architecture: amd64
Maintainer: SoftwareRestaurante <soporte@softwarerestaurante.com>
Depends: libgtk-3-0, libayatana-appindicator3-1
Section: utils
Priority: optional
Description: Software Restaurante - Agente de Impresion Local
 Agente de impresion y conectividad IoT para restaurantes.
 Inicia automaticamente en segundo plano con el sistema operativo.
EOF

dpkg-deb --build "$TMP_DEB" "$OUT/SoftwareRestaurante.deb"
rm -rf "$TMP_DEB"

# Crear Tar.gz con el nombre SoftwareRestaurante
tar -czf "$OUT/SoftwareRestaurante-linux-x64.tar.gz" -C "$BUNDLE" .

echo "Build de SoftwareRestaurante.deb exitoso!"
