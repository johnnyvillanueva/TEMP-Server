#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

### =========================
### VARIABLES
### =========================
PORT=8888
PREFIX_DIR="${PREFIX}"
WWW_DIR="$PREFIX/share/nginx/html"
PHPMYADMIN_DIR="$WWW_DIR/phpmyadmin"

### =========================
### HELPERS
### =========================
log() { echo "[+] $1"; }
warn() { echo "[!] $1"; }
fail() { echo "[✗] $1" && exit 1; }

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

pkg_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

check_php_extension() {
    php -m | grep -qi "$1"
}

check_port_free() {
    ! lsof -i :"$PORT" >/dev/null 2>&1
}

### =========================
### ENVIRONMENT CHECK
### =========================
[[ -d /data/data/com.termux ]] || fail "This script is for Termux only"

### =========================
### UPDATE SYSTEM
### =========================
log "Updating packages"
pkg update -y && pkg upgrade -y

### =========================
### INSTALL PACKAGES
### =========================
PACKAGES=(
    nginx
    php
    php-fpm
    mariadb
    wget
    unzip
    lsof
)

for p in "${PACKAGES[@]}"; do
    if pkg_installed "$p"; then
        log "$p already installed"
    else
        log "Installing $p"
        pkg install -y "$p"
    fi
done

### =========================
### PHP CHECKS
### =========================
command_exists php || fail "PHP not installed"

check_php_extension mysqli || fail "PHP mysqli extension missing"
check_php_extension pdo_mysql || fail "PHP pdo_mysql extension missing"

log "PHP MySQL extensions OK"

### =========================
### PORT CHECK
### =========================
check_port_free || fail "Port $PORT is already in use"

### =========================
### MARIADB INIT
### =========================
DB_DIR="$PREFIX/var/lib/mysql/mysql"

if [[ ! -d "$DB_DIR" ]]; then
    log "Initializing MariaDB"
    mariadb-install-db \
        --basedir="$PREFIX" \
        --datadir="$PREFIX/var/lib/mysql" >/dev/null
else
    log "MariaDB already initialized"
fi

### =========================
### PHP-FPM CONFIG
### =========================
PHPFPM_CONF="$PREFIX/etc/php-fpm.d/www.conf"

sed -i 's|^;listen =.*|listen = 127.0.0.1:9000|' "$PHPFPM_CONF"

### =========================
### NGINX CONFIG
### =========================
log "Configuring Nginx"

cat > "$PREFIX/etc/nginx/nginx.conf" <<EOF
worker_processes 1;

events { worker_connections 1024; }

http {
    include mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;

    server {
        listen ${PORT};
        server_name 0.0.0.0;

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

### =========================
### PHP TEST FILE
### =========================
mkdir -p "$WWW_DIR"
echo "<?php phpinfo();" > "$WWW_DIR/index.php"

### =========================
### PHPMYADMIN INSTALL
### =========================
if [[ ! -d "$PHPMYADMIN_DIR" ]]; then
    log "Installing phpMyAdmin"
    cd "$WWW_DIR"
    wget -q https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip
    unzip -q phpMyAdmin-latest-all-languages.zip
    rm phpMyAdmin-latest-all-languages.zip
    mv phpMyAdmin-*-all-languages phpmyadmin
    cp phpmyadmin/config.sample.inc.php phpmyadmin/config.inc.php
else
    log "phpMyAdmin already installed"
fi

### =========================
### HELPER COMMAND
### =========================
cat > "$PREFIX/bin/lemp" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

case "$1" in
start)
    mariadbd-safe --datadir=$PREFIX/var/lib/mysql &
    php-fpm
    nginx
    ;;
stop)
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
    pgrep nginx >/dev/null && echo "nginx running" || echo "nginx stopped"
    pgrep php-fpm >/dev/null && echo "php-fpm running" || echo "php-fpm stopped"
    pgrep mariadbd >/dev/null && echo "mariadb running" || echo "mariadb stopped"
    ;;
*)
    echo "Usage: lemp {start|stop|restart|status}"
    ;;
esac
EOF

chmod +x "$PREFIX/bin/lemp"

### =========================
### DONE
### =========================
log "INSTALLATION COMPLETE"
echo "URL: http://127.0.0.1:${PORT}"
echo "phpMyAdmin: http://127.0.0.1:${PORT}/phpmyadmin"