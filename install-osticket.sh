#!/usr/bin/env bash
# osTicket + HTTPS (Certbot) on Ubuntu — Apache + PHP + MariaDB
# Diagnostic build: full logging, error traps, idempotent.
set -Eeuo pipefail

# Pretty errors with line number
trap 'echo "ERROR: Command failed on line $LINENO"; exit 1' ERR

# Normalize CRLF if pasted from Windows editors
sed -i "s/\r$//" "${BASH_SOURCE[0]}" 2>/dev/null || true

# Log everything to file + stdout
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="${SCRIPT_DIR}/install.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "=== $(date -Is) | osTicket installer starting ==="

# ----- Load .env -----
ENV_FILE="${SCRIPT_DIR}/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env not found at ${ENV_FILE}. Create it and re-run."
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

# ----- Defaults -----
DOMAINS="${DOMAINS:-}"
EMAIL="${EMAIL:-}"
CERTBOT_STAGING="${CERTBOT_STAGING:-0}"
DB_NAME="${DB_NAME:-osticketdb}"
DB_USER="${DB_USER:-ostuser}"
DB_PASS="${DB_PASS:-$(tr -dc 'A-Za-z0-9!@#%^&*' </dev/urandom | head -c 22)}"
PHP_VERSION="${PHP_VERSION:-8.2}"
OST_VER="${OST_VER:-v1.18.2}"

echo "Using:"
echo "  DOMAINS=$DOMAINS"
echo "  EMAIL=$EMAIL"
echo "  PHP_VERSION=$PHP_VERSION  OST_VER=$OST_VER"
echo "  DB_NAME=$DB_NAME  DB_USER=$DB_USER"

# ----- Validate -----
if [[ -z "$DOMAINS" ]]; then echo "ERROR: DOMAINS missing in .env"; exit 1; fi
if [[ -z "$EMAIL" ]]; then echo "ERROR: EMAIL missing in .env"; exit 1; fi

DOMAINS_CLEAN="$(echo "$DOMAINS" | tr ',' ' ')"
read -r -a DOMAIN_ARR <<< "$DOMAINS_CLEAN"
PRIMARY_DOMAIN="${DOMAIN_ARR[0]}"
CERTBOT_DOMAIN_FLAGS=()
for d in "${DOMAIN_ARR[@]}"; do CERTBOT_DOMAIN_FLAGS+=( -d "$d" ); done

# ----- Apt prep -----
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# ----- Install stack -----
apt-get install -y apache2 mariadb-server unzip curl ca-certificates rsync \
  "php${PHP_VERSION}" "php${PHP_VERSION}-cli" "php${PHP_VERSION}-common" \
  "php${PHP_VERSION}-mysql" "php${PHP_VERSION}-gd" "php${PHP_VERSION}-imap" \
  "php${PHP_VERSION}-mbstring" "php${PHP_VERSION}-xml" "php${PHP_VERSION}-curl" \
  "php${PHP_VERSION}-intl" "php${PHP_VERSION}-apcu" "php${PHP_VERSION}-zip"

a2enmod rewrite headers
systemctl enable --now apache2
systemctl enable --now mariadb

# ----- UFW -----
if command -v ufw >/dev/null 2>&1; then
  ufw allow OpenSSH || true
  ufw allow "Apache Full" || true   # 80 + 443
  ufw --force enable || true
fi

# ----- Database -----
mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# ----- PHP tune -----
PHPINI="/etc/php/${PHP_VERSION}/apache2/php.ini"
sed -i 's/^memory_limit = .*/memory_limit = 256M/' "$PHPINI"
sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 20M/' "$PHPINI"
sed -i 's/^post_max_size = .*/post_max_size = 32M/' "$PHPINI"
grep -q '^date.timezone = ' "$PHPINI" && \
  sed -i 's/^date.timezone = .*/date.timezone = UTC/' "$PHPINI" || \
  sed -i 's~;date.timezone =.*~date.timezone = UTC~' "$PHPINI"
systemctl restart apache2

# ----- osTicket files -----
cd /tmp
if [ ! -f "osTicket-${OST_VER}.zip" ]; then
  curl -L -o "osTicket-${OST_VER}.zip" "https://github.com/osTicket/osTicket/releases/download/${OST_VER}/osTicket-${OST_VER}.zip"
fi
unzip -q -o "osTicket-${OST_VER}.zip"
install -d -m 755 /var/www/osticket
rsync -a --delete /tmp/upload/ /var/www/osticket/

cd /var/www/osticket
if [ -f include/ost-sampleconfig.php ] && [ ! -f include/ost-config.php ]; then
  cp include/ost-sampleconfig.php include/ost-config.php
fi
chown -R www-data:www-data /var/www/osticket
find /var/www/osticket -type d -exec chmod 755 {} \;
find /var/www/osticket -type f -exec chmod 644 {} \;
chmod 666 include/ost-config.php || true

# ----- Apache vhost (HTTP; Certbot adds HTTPS + redirect) -----
cat >/etc/apache2/sites-available/osticket.conf <<APACHE
<VirtualHost *:80>
    ServerName ${PRIMARY_DOMAIN}
$(for d in "${DOMAIN_ARR[@]:1}"; do echo "    ServerAlias ${d}"; done)
    DocumentRoot /var/www/osticket
    <Directory /var/www/osticket>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/osticket_error.log
    CustomLog \${APACHE_LOG_DIR}/osticket_access.log combined
</VirtualHost>
APACHE

a2dissite 000-default.conf >/dev/null 2>&1 || true
a2ensite osticket.conf
systemctl reload apache2

# ----- Certbot -----
apt-get install -y certbot python3-certbot-apache
STAGING_FLAG=""
if [[ "${CERTBOT_STAGING}" == "1" ]]; then
  echo ">>> Using Let's Encrypt STAGING"
  STAGING_FLAG="--staging"
fi
certbot --apache ${STAGING_FLAG} --non-interactive --agree-tos --no-eff-email \
  -m "${EMAIL}" "${CERTBOT_DOMAIN_FLAGS[@]}" --redirect

IP_OR_HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo "============================================================"
echo " osTicket files:      /var/www/osticket"
echo " vhost:               /etc/apache2/sites-available/osticket.conf"
echo " DB name/user/pass:   ${DB_NAME} / ${DB_USER} / ${DB_PASS}"
echo " Install URL (HTTPS): https://${PRIMARY_DOMAIN}/setup/"
echo " Log file:            ${LOGFILE}"
echo "============================================================"

echo "=== $(date -Is) | osTicket installer completed ==="
