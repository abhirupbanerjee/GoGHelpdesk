# osTicket Installation & Integration Guide

**Enterprise Service Desk System for Government of Grenada**

## 📋 Overview

Complete setup guide for osTicket (v1.18.2) on Ubuntu 24.04 with HTTPS and EA Portal integration for automatic ticket creation.

### System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Azure VM (VM2)                        │
│                 helpdesk.gea.abhirup.app                 │
├─────────────────────────────────────────────────────────┤
│  Apache 2.4 + PHP 8.2 + MariaDB                         │
│  ├─ osTicket v1.18.2                                    │
│  ├─ Let's Encrypt SSL (Certbot)                         │
│  └─ UFW Firewall (80, 443, 22)                          │
└─────────────────────────────────────────────────────────┘
                          ↑
                          │ API Integration
                          ↓
┌─────────────────────────────────────────────────────────┐
│              EA Portal (GoGEAPortalv3)                   │
│              gea.abhirup.app                             │
├─────────────────────────────────────────────────────────┤
│  Next.js 14 Frontend                                     │
│  ├─ Feedback Collection System                          │
│  ├─ osTicket Integration                                │
│  └─ Automatic Ticket Creation:                          │
│     • Grievance flagged → URGENT ticket                 │
│     • Rating < 3.0 → NORMAL ticket                      │
└─────────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start (15 minutes)

```bash
# 1. Create setup directory
mkdir ~/osTicket-setup && cd ~/osTicket-setup

# 2. Create .env configuration
nano .env
# Add configuration (see below)

# 3. Create installer script
nano install-osticket-https.sh
# Add script content

# 4. Run installation
chmod +x install-osticket-https.sh
sudo ./install-osticket-https.sh

# 5. Complete web installer at printed URL
# 6. Run post-install hardening
```

---

## ⚙️ Configuration Files

### .env File

```bash
# --- REQUIRED ---
DOMAINS="helpdesk.gea.abhirup.app"
EMAIL="mailabhirupbanerjee@gmail.com"

# --- OPTIONAL ---
CERTBOT_STAGING=0          # 1=test, 0=production
DB_NAME="osticketdb"
DB_USER="ostuser"
# DB_PASS auto-generated if omitted
PHP_VERSION="8.2"
OST_VER="v1.18.2"
```

### Installation Script

See `install-osticket-https.sh` in installation reference

---

## 📝 Post-Installation

### 1. Complete Web Installer

Navigate to: `https://helpdesk.gea.abhirup.app/setup/`

**System Settings:**
- Helpdesk Name: `Government of Grenada EA Portal Support`
- Default Email: `mailabhirupbanerjee@gmail.com`

**Database Configuration:**
- Host: `localhost`
- Name/User/Password: (from installation output)

### 2. Security Hardening

```bash
# Remove setup directory
sudo rm -rf /var/www/osticket/setup

# Lock configuration
sudo chmod 644 /var/www/osticket/include/ost-config.php
```

### 3. Configure osTicket

Login: `https://helpdesk.gea.abhirup.app/scp`

**Settings → Tickets:**
- ☑ Accept Email from Unknown Users
- ☐ Authorized Users Only (uncheck)

**Emails → Add Email:**
- `feedback@gea.abhirup.app`
- `mailabhirupbanerjee@gmail.com`

**Manage → API Keys:**
- Create new key with "Can Create Tickets" permission

**Manage → Forms → Ticket:**

Add custom fields:

| Field Label | Variable | Type | Required |
|------------|----------|------|----------|
| Entity Name | `entity` | Text | Yes |
| System name | `system_name` | Text | No |

---

## 🔗 API Integration

### Endpoint

```
POST https://helpdesk.gea.abhirup.app/api/tickets.json
```

### Headers

```
X-API-Key: YOUR_API_KEY
Content-Type: application/json
```

### Required Payload

```json
{
  "alert": true,
  "autorespond": true,
  "source": "API",
  "name": "User Name",
  "email": "mailabhirupbanerjee@gmail.com",
  "subject": "Ticket Subject",
  "message": "data:text/html,<p>HTML message</p>",
  "ip": "172.178.28.16",
  "topicId": 1,
  "entity": "Entity Name",
  "system_name": "EA Portal"
}
```

### Additional Fields for Integration

**Custom Fields:**
- `entity` - Government entity name (required)
- `system_name` - System identifier (optional)

**Note:** Use field variable names directly (not `field_XX` format)

### Test API

```bash
curl -X POST https://helpdesk.gea.abhirup.app/api/tickets.json \
  -H "X-API-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "alert": true,
    "autorespond": true,
    "source": "API",
    "name": "Test",
    "email": "mailabhirupbanerjee@gmail.com",
    "subject": "API Test",
    "message": "data:text/html,<p>Test</p>",
    "ip": "172.178.28.16",
    "topicId": 1,
    "entity": "Test Entity",
    "system_name": "EA Portal"
  }'
```

**Expected:** Ticket number returned (e.g., `000001`)

---

## 📧 Email-Based Ticketing

### IMAP/POP3 Configuration

**Admin Panel → Emails → Add Email**

```
Email Address: support@domain.com
Protocol: IMAP
Server: mail.domain.com
Port: 993
Encryption: SSL
Fetch Frequency: Every 5 minutes
```

### Email Piping (Alternative)

```bash
# Add to mail server alias
support@domain.com: "| /var/www/osticket/api/pipe.php"
```

---

## 📨 SMTP Email Notifications

### Configure SMTP

**Admin Panel → Emails → SMTP Settings**

#### Gmail SMTP

```
Hostname: smtp.gmail.com
Port: 587
Authentication: Enabled
Username: mailabhirupbanerjee@gmail.com
Password: [App-specific password]
Use TLS: Yes
```

**Generate App Password:**
1. Google Account → Security → 2-Step Verification
2. App passwords → Generate
3. Use in osTicket

#### SendGrid

```
Hostname: smtp.sendgrid.net
Port: 587
Username: apikey
Password: [SendGrid API key]
Use TLS: Yes
```

### Notification Settings

**Admin Panel → Settings → Emails**

Enable notifications for:
- ☑ New Ticket Created
- ☑ New Message from User
- ☑ New Message from Agent
- ☑ Ticket Assignment
- ☑ Overdue Ticket Alert

---

## 💻 Minimal VM Requirements

### Production Environment

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **CPU** | 2 vCPU | 4 vCPU |
| **RAM** | 4 GB | 8 GB |
| **Storage** | 30 GB SSD | 60 GB SSD |
| **OS** | Ubuntu 24.04 LTS | Ubuntu 24.04 LTS |
| **Network** | 100 Mbps | 1 Gbps |

### Storage Breakdown

```
Application:      ~500 MB
Database:         ~1 GB (grows with tickets)
Attachments:      ~5-10 GB
Logs:             ~1 GB
System:           ~10 GB
Swap:             4 GB
Reserve:          ~10 GB
Total:            ~30 GB minimum
```

### Azure VM Tiers

**Development/Testing:**
- Size: Standard_B2s
- Specs: 2 vCPU, 4 GB RAM
- Cost: ~$30/month

**Production (Small):**
- Size: Standard_D2s_v3
- Specs: 2 vCPU, 8 GB RAM
- Cost: ~$70/month

**Production (Medium):**
- Size: Standard_D4s_v3
- Specs: 4 vCPU, 16 GB RAM
- Cost: ~$140/month

### Network Requirements

**Azure NSG Inbound Rules:**
```
Port 22 (SSH):   Admin IP only
Port 80 (HTTP):  Any (redirects to 443)
Port 443 (HTTPS): Any
```

**Bandwidth:** 1-5 GB/month for 100 tickets/day

---

## 🔒 Security Best Practices

### Firewall

```bash
sudo ufw allow OpenSSH
sudo ufw allow "Apache Full"
sudo ufw limit 22/tcp
sudo ufw enable
```

### SSL Auto-Renewal

```bash
# Test renewal
sudo certbot renew --dry-run
```

### Database Security

```bash
sudo mysql_secure_installation
# Set root password
# Remove anonymous users
# Disallow root remote login
```

### File Permissions

```bash
sudo chown -R www-data:www-data /var/www/osticket
sudo find /var/www/osticket -type d -exec chmod 755 {} \;
sudo find /var/www/osticket -type f -exec chmod 644 {} \;
sudo chmod 644 /var/www/osticket/include/ost-config.php
```

---

## 🔧 Troubleshooting

### Cannot Access osTicket

```bash
# Check Apache
sudo systemctl status apache2
sudo apache2ctl configtest

# Check logs
sudo tail -f /var/log/apache2/osticket_error.log
```

### SSL Certificate Issues

```bash
# Verify DNS
dig helpdesk.gea.abhirup.app

# Check Certbot logs
sudo tail -f /var/log/letsencrypt/letsencrypt.log

# Force renewal
sudo certbot --apache -d helpdesk.gea.abhirup.app --force-renewal
```

### Database Connection Errors

```bash
# Check MariaDB
sudo systemctl status mariadb

# Test connection
mysql -u ostuser -p osticketdb
```

### API Ticket Creation Fails

```bash
# Verify API key active in Admin Panel
# Test API endpoint
curl -v -X POST https://helpdesk.gea.abhirup.app/api/tickets.json \
  -H "X-API-Key: YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"alert":true,"subject":"Test","message":"data:text/html,<p>Test</p>","name":"Test","email":"test@test.com"}'
```

### Log Locations

```
Apache:    /var/log/apache2/osticket_error.log
PHP:       /var/log/apache2/error.log
MariaDB:   /var/log/mysql/error.log
osTicket:  /var/www/osticket/data/logs/
Certbot:   /var/log/letsencrypt/letsencrypt.log
```

---

## 📚 Additional Documentation

- `INSTALLATION_REFERENCE.md` - Detailed installation steps
- `INTEGRATION_REFERENCE.md` - Complete API integration guide
- See conversation history for tested integration scripts

---

## 📞 Support

**osTicket Resources:**
- Documentation: https://docs.osticket.com/
- Forum: https://forum.osticket.com/

**GoG EA Portal:**
- Email: mailabhirupbanerjee@gmail.com
- Helpdesk: https://helpdesk.gea.abhirup.app

---

**Last Updated:** November 9, 2025  
**Version:** 1.0  
**osTicket Version:** v1.18.2  
**Author:** AB, Government of Grenada Digital Transformation Team
