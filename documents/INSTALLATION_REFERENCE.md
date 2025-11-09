# osTicket Installation Reference Guide

**Detailed Step-by-Step Installation Instructions**

## 📋 Table of Contents

1. [Pre-Installation Requirements](#pre-installation-requirements)
2. [Installation Script](#installation-script)
3. [Configuration Options](#configuration-options)
4. [Post-Installation Setup](#post-installation-setup)
5. [Verification & Testing](#verification--testing)

---

## Pre-Installation Requirements

### Azure VM Setup

**Create VM in Azure Portal:**
- Image: Ubuntu 24.04 LTS
- Size: Standard_B2s minimum (2 vCPU, 4 GB RAM)
- Disk: 30 GB Premium SSD
- Region: Closest to target users

**Network Security Group (NSG):**

| Port | Protocol | Source | Description |
|------|----------|--------|-------------|
| 22 | TCP | Your IP | SSH access |
| 80 | TCP | Any | HTTP (auto-redirects to HTTPS) |
| 443 | TCP | Any | HTTPS |

### DNS Configuration

Configure A record before installation:

```
Type: A
Name: helpdesk
Value: [VM Public IP]
TTL: 300
```

Verify DNS propagation:
```bash
dig helpdesk.gea.abhirup.app
nslookup helpdesk.gea.abhirup.app
```

### SSH Access

```bash
# From local machine
ssh azureuser@[VM-IP]

# Or use configured SSH alias
ssh goghelpdesk
```

---

## Installation Script

### Complete install-osticket-https.sh

```bash
#!/usr/bin/env bash
# osTicket + HTTPS (Certbot) on Ubuntu — Apache + PHP + MariaDB
# Reads configuration from a .env file placed beside this script.

set -euo pipefail

# ----- Load .env -----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env not found at ${ENV_FILE}. Create it first." >&2
  exit 1
fi
source "$ENV_FILE"

# ----- Defaults if not provided in .env -----
DOMAINS="${DOMAINS:-}"
EMAIL="${EMAIL:-}"
CERTBOT_STAGING="${CERTBOT_STAGING:-0}"
DB_NAME="${DB_NAME:-osticketdb}"
DB_USER="${DB_USER:-ostuser}"
DB_PASS="${DB_PASS:-$(tr -dc 'A-Za-z0-9!@#%^&*' </dev/urandom | head -c 22)}"
PHP_VERSION="${PHP_VERSION:-8.2}"
OST_VER="${OST_VER:-v1.18.2}"

# ----- Validate required vars -----
if [[ -z "$DOMAINS" ]]; then
  echo "ERROR: DOMAINS is empty in .env" >&2
  exit 1
fi
if [[ -z "$EMAIL" ]]; then
  echo "ERROR: EMAIL is empty in .env" >&2
  exit 1
fi

# Normalize domains to an array
DOMAINS_CLEAN="$(echo "$DOMAINS" | tr ',' ' ')"
read -r -a DOMAIN_ARR <<< "$DOMAINS_CLEAN"
PRIMARY_DOMAIN="${DOMAIN_ARR[0]}"

CERTBOT_DOMAIN_FLAGS=()
for d in "${DOMAIN_ARR[@]}"; do CERTBOT_DOMAIN_FLAGS+=( -d "$d" ); done

echo "=== Using settings ==="
echo "Primary domain: ${PRIMARY_DOMAIN}"
echo "All domains:    ${DOMAINS_CLEAN}"
echo "Admin email:    ${EMAIL}"
echo "PHP version:    ${PHP_VERSION}"
echo "osTicket ver:   ${OST_VER}"
echo "DB name:        ${DB_NAME}"
echo "DB user:        ${DB_USER}"
echo "DB pass:        ${DB_PASS}"

# ----- System update -----
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# ----- Install stack -----
apt-get install -y apache2 mariadb-server unzip curl ca-certificates rsync \
  "php${PHP_VERSION}" "php${PHP_VERSION}-cli" "php${PHP_VERSION}-common" \
  "php${PHP_VERSION}-mysql" "php${PHP_VERSION}-gd" "php${PHP_VERSION}-imap" \
  "php${PHP_VERSION}-mbstring" "php${PHP_VERSION}-xml" "php${PHP_VERSION}-curl" \
  "php${PHP_VERSION}-intl" "php${PHP_VERSION}-apcu" "php${PHP_VERSION}-zip"

a2enmod rewrite headers
systemctl enable --now apache2
systemctl enable --now mariadb

# ----- Firewall (UFW) -----
if command -v ufw >/dev/null 2>&1; then
  ufw allow OpenSSH || true
  ufw allow "Apache Full" || true
  ufw --force enable || true
fi

# ----- Database -----
mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# ----- PHP tuning -----
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

# ----- Apache vhost -----
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

# ----- Certbot (HTTPS + redirect) -----
apt-get install -y certbot python3-certbot-apache
STAGING_FLAG=""
if [[ "$CERTBOT_STAGING" == "1" ]]; then
  echo ">>> Using Let's Encrypt STAGING environment"
  STAGING_FLAG="--staging"
fi

certbot --apache ${STAGING_FLAG} --non-interactive --agree-tos --no-eff-email \
  -m "${EMAIL}" "${CERTBOT_DOMAIN_FLAGS[@]}" --redirect

# ----- Output -----
IP_OR_HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo "============================================================"
echo " osTicket files:      /var/www/osticket"
echo " Apache vhost:        /etc/apache2/sites-available/osticket.conf"
echo " Database name:       ${DB_NAME}"
echo " Database user:       ${DB_USER}"
echo " Database password:   ${DB_PASS}"
echo " Install URL (HTTPS): https://${PRIMARY_DOMAIN}/setup/"
echo " Alt (HTTP by IP):    http://${IP_OR_HOST}/setup/"
echo "============================================================"

cat <<'NEXT'
Finish up:
1) Open the HTTPS Install URL and complete the web installer:
   - MySQL Host:      localhost
   - Database Name:   (above)
   - MySQL Username:  (above)
   - MySQL Password:  (above)
2) After installer finishes:
   sudo rm -rf /var/www/osticket/setup
   sudo chmod 644 /var/www/osticket/include/ost-config.php
3) Test renewals:
   sudo certbot renew --dry-run
NEXT

echo "=== Done. ==="
```

---

## Configuration Options

### .env File Parameters

```bash
# === REQUIRED PARAMETERS ===

# Domain(s) for osTicket installation
# Single domain:
DOMAINS="helpdesk.gea.abhirup.app"
# Multiple domains (comma-separated):
DOMAINS="helpdesk.gea.abhirup.app,support.gea.abhirup.app"

# Email address for Let's Encrypt notifications
EMAIL="mailabhirupbanerjee@gmail.com"

# === OPTIONAL PARAMETERS ===

# Let's Encrypt staging mode
# Set to 1 for testing (no rate limits)
# Set to 0 for production certificates
CERTBOT_STAGING=0

# Database configuration
DB_NAME="osticketdb"           # Database name
DB_USER="ostuser"               # Database username
DB_PASS=""                      # Leave empty for auto-generation

# Software versions
PHP_VERSION="8.2"               # PHP version to install
OST_VER="v1.18.2"              # osTicket version
```

### PHP Configuration

Automatically configured by installer:

```ini
# /etc/php/8.2/apache2/php.ini
memory_limit = 256M
upload_max_filesize = 20M
post_max_size = 32M
max_execution_time = 60
date.timezone = UTC
```

### Apache Configuration

Automatically configured by installer:

```apache
# /etc/apache2/sites-available/osticket.conf
<VirtualHost *:80>
    ServerName helpdesk.gea.abhirup.app
    DocumentRoot /var/www/osticket
    
    <Directory /var/www/osticket>
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog ${APACHE_LOG_DIR}/osticket_error.log
    CustomLog ${APACHE_LOG_DIR}/osticket_access.log combined
</VirtualHost>
```

Certbot automatically adds HTTPS configuration and HTTP→HTTPS redirect.

---

## Post-Installation Setup

### 1. Web Installer Configuration

Navigate to: `https://helpdesk.gea.abhirup.app/setup/`

#### System Settings Page

**Help Desk Information:**
```
Helpdesk Name: Government of Grenada EA Portal Support
Helpdesk URL: https://helpdesk.gea.abhirup.app
```

**Default Email:**
```
Email Address: mailabhirupbanerjee@gmail.com
Email Name: GoG EA Portal Support
```

#### Database Configuration Page

Use values from installation output:

```
MySQL Host: localhost
MySQL Database: osticketdb
MySQL Username: ostuser
MySQL Password: [generated password from output]
```

**Note:** Copy the database password from the installation script output.

#### Admin User Creation

```
Username: admin
Password: [Create a strong password]
Confirm Password: [Repeat password]
First Name: Administrator
Last Name: Admin
Email: mailabhirupbanerjee@gmail.com
```

**Password Requirements:**
- Minimum 8 characters
- Include uppercase, lowercase, numbers
- Include special characters

### 2. Post-Install Hardening

```bash
# 1. Remove setup directory
sudo rm -rf /var/www/osticket/setup

# 2. Lock configuration file
sudo chmod 644 /var/www/osticket/include/ost-config.php

# 3. Verify permissions
ls -la /var/www/osticket/include/ost-config.php
# Should show: -rw-r--r-- www-data www-data

# 4. Test SSL renewal
sudo certbot renew --dry-run
```

### 3. Initial osTicket Configuration

Login to admin panel: `https://helpdesk.gea.abhirup.app/scp`

#### Settings → Tickets

```
☑ Accept Email from Unknown Users
☐ Authorized Users Only (UNCHECK THIS)
☑ Enable Email Piping
☐ Require Registration and Login
```

**Why uncheck "Authorized Users Only":**
- Allows API ticket creation
- Enables external system integrations

#### Settings → Users

```
Registration Method: Disabled
☑ Require email verification
☐ Allow password resets
```

#### Emails → Add Email

Add whitelisted emails for API:

```
Email: feedback@gea.abhirup.app
Name: EA Portal Feedback System
Status: Active
```

```
Email: mailabhirupbanerjee@gmail.com
Name: GoG Administrator
Status: Active
```

#### Manage → API Keys

Create API key:

```
API Key: [Auto-generated]
Status: Active
IP Address: [Leave empty for any]
Notes: EA Portal Integration
Permissions:
  ☑ Can Create Tickets
  ☐ Can Execute Cron
```

**Save the API key immediately** - it won't be shown again.

#### Manage → Forms → Ticket

Add custom fields for integration:

**Field 1: Entity Name**
```
Type: Text Input
Label: Entity Name
Variable: entity
Visibility: Visible
Configuration:
  ☑ Required
  Max Length: 100
```

**Field 2: System name**
```
Type: Text Input
Label: System name
Variable: system_name
Visibility: Visible
Configuration:
  ☐ Required
  Max Length: 50
```

---

## Verification & Testing

### 1. Check Installation

```bash
# Check Apache status
sudo systemctl status apache2

# Check MariaDB status
sudo systemctl status mariadb

# Check osTicket files
ls -la /var/www/osticket/

# Check SSL certificate
sudo certbot certificates
```

### 2. Test Web Access

```bash
# Test HTTPS access
curl -I https://helpdesk.gea.abhirup.app

# Expected: 200 OK response
```

Open in browser:
- `https://helpdesk.gea.abhirup.app` → Should show osTicket home
- `https://helpdesk.gea.abhirup.app/scp` → Should show login

### 3. Test Database Connection

```bash
# Connect to database
mysql -u ostuser -p osticketdb

# List tables
SHOW TABLES;

# Check API keys table
SELECT * FROM ost_api_key\G

# Exit
exit
```

### 4. Test API Endpoint

```bash
# Basic API test
curl -X POST https://helpdesk.gea.abhirup.app/api/tickets.json \
  -H "X-API-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "alert": true,
    "autorespond": true,
    "source": "API",
    "name": "Test User",
    "email": "mailabhirupbanerjee@gmail.com",
    "subject": "Installation Test",
    "message": "data:text/html,<p>Testing osTicket API after installation</p>",
    "ip": "172.178.28.16",
    "topicId": 1,
    "entity": "Test Entity",
    "system_name": "Installation Test"
  }'
```

**Expected Response:**
```
000001
```
(Or ticket number like `000001`, `000002`, etc.)

### 5. Verify Ticket Created

1. Login to: `https://helpdesk.gea.abhirup.app/scp`
2. Check Open Tickets
3. Verify test ticket appears with:
   - Subject: "Installation Test"
   - Entity Name: "Test Entity"
   - System name: "Installation Test"

---

## Common Installation Issues

### Issue: DNS not resolving

```bash
# Check DNS
dig helpdesk.gea.abhirup.app

# Wait for propagation (up to 24 hours)
# Use DNS checker: https://dnschecker.org/
```

### Issue: Certbot fails with rate limit

```bash
# Use staging mode first
# In .env: CERTBOT_STAGING=1
# Run installer
# Once successful, switch to production:
# CERTBOT_STAGING=0
# Run: sudo certbot --apache -d helpdesk.gea.abhirup.app --force-renewal
```

### Issue: Cannot connect to database

```bash
# Check MariaDB running
sudo systemctl status mariadb

# Reset database user
sudo mysql
DROP USER 'ostuser'@'localhost';
CREATE USER 'ostuser'@'localhost' IDENTIFIED BY 'YourPassword';
GRANT ALL PRIVILEGES ON osticketdb.* TO 'ostuser'@'localhost';
FLUSH PRIVILEGES;
exit
```

### Issue: Permission denied errors

```bash
# Reset permissions
sudo chown -R www-data:www-data /var/www/osticket
sudo find /var/www/osticket -type d -exec chmod 755 {} \;
sudo find /var/www/osticket -type f -exec chmod 644 {} \;
```

### Issue: PHP modules not loaded

```bash
# Check loaded modules
php -m | grep -E '(gd|imap|mbstring|mysql)'

# Enable modules
sudo phpenmod gd imap mbstring mysqli
sudo systemctl restart apache2
```

---

## Maintenance

### Regular Updates

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Check for osTicket updates
# https://github.com/osTicket/osTicket/releases
```

### Backup Database

```bash
# Create backup
sudo mysqldump -u ostuser -p osticketdb > osticket_backup_$(date +%Y%m%d).sql

# Restore backup
sudo mysql -u ostuser -p osticketdb < osticket_backup_YYYYMMDD.sql
```

### Backup Files

```bash
# Backup osTicket files
sudo tar -czf osticket_files_$(date +%Y%m%d).tar.gz /var/www/osticket

# Restore files
sudo tar -xzf osticket_files_YYYYMMDD.tar.gz -C /
```

### Monitor Logs

```bash
# Watch Apache errors
sudo tail -f /var/log/apache2/osticket_error.log

# Watch PHP errors
sudo tail -f /var/log/apache2/error.log

# Watch SSL renewal
sudo tail -f /var/log/letsencrypt/letsencrypt.log
```

---

## Next Steps

After successful installation:

1. Configure SMTP for email notifications (see main README)
2. Set up email-based ticketing (see main README)
3. Integrate with EA Portal (see INTEGRATION_REFERENCE.md)
4. Configure backup schedule
5. Set up monitoring

---

**Last Updated:** November 9, 2025  
**Installer Version:** 1.0  
**Tested On:** Ubuntu 24.04 LTS, Azure Standard_B2s
