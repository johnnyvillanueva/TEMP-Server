#!/data/data/com.termux/files/usr/bin/bash

set -e

PORT=8080
PREFIX_DIR=$PREFIX
WWW_DIR=$PREFIX/share/nginx/html
PHPMYADMIN_DIR=$WWW_DIR/phpmyadmin

echo "🚀 Termux LEMP Installer Started..."

# ---------------------------
# Helper: check package
# ---------------------------
pkg_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

# ---------------------------
# Update packages
# ---------------------------
echo "🔄 Updating packages..."
pkg update -y && pkg upgrade -y

# ---------------------------
# Install required packages
# ---------------------------
PACKAGES=(
    nginx
    php-fpm
    mariadb
    wget
    unzip
)

for pkg in "${PACKAGES[@]}"; do
    if pkg_installed "$pkg"; then
        echo "✅ $pkg already installed"
    else
        echo "📦 Installing $pkg..."
        pkg install -y "$pkg"
    fi
done

# ---------------------------
# MariaDB init
# ---------------------------
if [ ! -d "$PREFIX/var/lib/mysql/mysql" ]; then
    echo "🗄️ Initializing MariaDB..."
    mysql_install_db --basedir=$PREFIX --datadir=$PREFIX/var/lib/mysql
fi

# ---------------------------
# phpMyAdmin install
# ---------------------------
if [ ! -d "$PHPMYADMIN_DIR" ]; then
    echo "📦 Installing phpMyAdmin..."
    mkdir -p "$WWW_DIR"
    cd "$WWW_DIR"

    wget https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip
    unzip phpMyAdmin-latest-all-languages.zip
    rm phpMyAdmin-latest-all-languages.zip

    mv phpMyAdmin-*-all-languages phpmyadmin
    cp phpmyadmin/config.sample.inc.php phpmyadmin/config.inc.php
    
    # Generar una clave secreta aleatoria para phpMyAdmin
    BLOWFISH=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
    sed -i "s/\$cfg\['blowfish_secret'\] = '';/\$cfg\['blowfish_secret'\] = '$BLOWFISH';/" phpmyadmin/config.inc.php
fi

# ---------------------------
# PHP-FPM config
# ---------------------------
echo "⚙️ Configuring PHP-FPM..."
# En Termux, es mejor usar sockets Unix o asegurar que el puerto esté libre
sed -i 's|^listen =.*|listen = 127.0.0.1:9000|' $PREFIX/etc/php-fpm.d/www.conf

# ---------------------------
# Nginx config
# ---------------------------
echo "⚙️ Configuring Nginx..."

cat > $PREFIX/etc/nginx/nginx.conf <<EOF
worker_processes  1;

# Importante en Termux: no definir 'user'
error_log  /data/data/com.termux/files/usr/var/log/nginx/error.log;

events {
    worker_connections 1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;

    # Directorios temporales necesarios para usuarios sin root
    client_body_temp_path /data/data/com.termux/files/usr/var/lib/nginx/client_body;
    proxy_temp_path /data/data/com.termux/files/usr/var/lib/nginx/proxy;
    fastcgi_temp_path /data/data/com.termux/files/usr/var/lib/nginx/fastcgi;

    server {
        listen ${PORT};
        server_name localhost;

        root ${WWW_DIR};
        index index.php index.html;

        location / {
            try_files \$uri \$uri/ /index.php;
        }

        location ~ \.php\$ {
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            fastcgi_pass 127.0.0.1:9000;
        }
    }
}
EOF

# Crear directorio de logs si no existe
mkdir -p $PREFIX/var/log/nginx
mkdir -p $PREFIX/var/lib/nginx

# ---------------------------
# PHP test file
# ---------------------------
echo "<?php phpinfo();" > $WWW_DIR/index.php

# ---------------------------
# Command shortcuts
# ---------------------------
echo "⚙️ Creating helper commands..."

cat > $PREFIX/bin/lemp <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

case "$1" in
start)
    echo "Starting MariaDB..."
    mariadbd-safe --datadir=$PREFIX/var/lib/mysql > /dev/null 2>&1 &
    echo "Starting PHP-FPM..."
    php-fpm
    echo "Starting Nginx..."
    nginx
    echo "🚀 LEMP stack is up!"
    ;;
stop)
    echo "Stopping LEMP stack..."
    pkill nginx || true
    pkill php-fpm || true
    pkill mariadbd || true
    ;;
restart)
    $0 stop
    sleep 2
    $0 start
    ;;
status)
    pgrep nginx > /dev/null && echo "✅ nginx is running" || echo "❌ nginx is stopped"
    pgrep php-fpm > /dev/null && echo "✅ php-fpm is running" || echo "❌ php-fpm is stopped"
    pgrep mariadbd > /dev/null && echo "✅ mariadb is running" || echo "❌ mariadb is stopped"
    ;;
*)
    echo "Usage: lemp {start|stop|restart|status}"
    ;;
esac
EOF

chmod +x $PREFIX/bin/lemp

echo "✅ INSTALLATION COMPLETE!"
echo "Type 'lemp start' to begin."
