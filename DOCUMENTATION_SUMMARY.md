# osTicket Documentation Package

**Complete Setup and Integration Guide for Government of Grenada EA Portal**

## 📚 Documentation Overview

This package contains comprehensive documentation for installing and integrating osTicket with the EA Portal feedback system.

### Files Included

| Document | Purpose | Size | Content |
|----------|---------|------|---------|
| **README.md** | Main guide | 11 KB | Quick start, configuration, troubleshooting |
| **INSTALLATION_REFERENCE.md** | Detailed installation | 16 KB | Step-by-step setup, post-install, verification |
| **INTEGRATION_REFERENCE.md** | API integration | 29 KB | Complete integration code, testing, deployment |

---

## 🚀 Quick Navigation

### For Installation

1. Start with **README.md** - Section: "Quick Start"
2. Reference **INSTALLATION_REFERENCE.md** for detailed steps
3. Follow post-installation checklist

### For Integration

1. Review **README.md** - Section: "API Integration"
2. Implement code from **INTEGRATION_REFERENCE.md**
3. Run test scripts to verify

### For Troubleshooting

1. Check **README.md** - Section: "Troubleshooting"
2. Review common issues in **INSTALLATION_REFERENCE.md**
3. Debug integration using **INTEGRATION_REFERENCE.md**

---

## 📋 What's Covered

### README.md

**Main Topics:**
- System architecture overview
- Quick start installation (15 minutes)
- Configuration files (.env, installer script)
- Post-installation setup
- API integration basics
- Email-based ticketing setup
- SMTP email notifications configuration
- VM requirements and sizing
- Security best practices
- Troubleshooting common issues

**Key Sections:**
- ⚙️ .env Configuration
- 🔗 API Integration
- 📧 Email-Based Ticketing
- 📨 SMTP Email Notifications
- 💻 Minimal VM Requirements
- 🔒 Security Best Practices
- 🔧 Troubleshooting

### INSTALLATION_REFERENCE.md

**Main Topics:**
- Pre-installation requirements (Azure VM, DNS, SSH)
- Complete installation script with explanations
- Configuration options and defaults
- Detailed post-installation steps
- Web installer walkthrough
- Security hardening procedures
- Verification and testing procedures
- Common installation issues and solutions
- Maintenance procedures (backups, updates, monitoring)

**Key Sections:**
- Pre-Installation Requirements
- Installation Script (complete bash script)
- Configuration Options
- Post-Installation Setup
- Verification & Testing
- Common Installation Issues
- Maintenance

### INTEGRATION_REFERENCE.md

**Main Topics:**
- Integration architecture and flow
- Prerequisites (osTicket config, EA Portal config)
- Complete API specification
- Full TypeScript implementation (integration library)
- Complete API route handler implementation
- Testing procedures (Node.js and curl scripts)
- Deployment instructions
- Monitoring and logging
- Troubleshooting integration issues
- Performance optimization tips

**Key Sections:**
- Integration Flow Diagram
- API Specification
- Integration Implementation (complete code)
- Testing the Integration
- Deployment Steps
- Monitoring
- Troubleshooting
- Performance Optimization

---

## 🎯 Key Information at a Glance

### Installation Details

```
VM: Azure Standard_B2s (2 vCPU, 4 GB RAM, 30 GB SSD)
OS: Ubuntu 24.04 LTS
Stack: Apache 2.4 + PHP 8.2 + MariaDB
SSL: Let's Encrypt (auto-renews)
Domain: helpdesk.gea.abhirup.app
Time: ~15 minutes installation
```

### Integration Details

```
Endpoint: https://helpdesk.gea.abhirup.app/api/tickets.json
Method: POST
Auth: X-API-Key header
Format: JSON with HTML message
Response: Ticket number (plain text)
Triggers:
  • Grievance flag = true → URGENT ticket
  • Average rating < 3.0 → NORMAL ticket
```

### Additional Fields Required

From your tested integration:

```javascript
{
  // Standard osTicket fields
  "alert": true,
  "autorespond": true,
  "source": "API",
  "name": "EA Portal Feedback System",
  "email": "mailabhirupbanerjee@gmail.com",
  "subject": "[GRIEVANCE] Service Feedback - Service Name",
  "message": "data:text/html,<html content>",
  "ip": "172.178.28.16",
  "topicId": 1,
  "priority": 4,  // 1=Low, 2=Normal, 3=High, 4=Urgent
  
  // REQUIRED custom fields
  "entity": "Entity Name",      // Government entity (required)
  "system_name": "EA Portal"    // System identifier (optional)
}
```

**Important Notes:**
- Use field **variable names** directly (`entity`, `system_name`)
- Do NOT use `field_XX` format
- `entity` field is REQUIRED
- Email must be whitelisted in osTicket

---

## 📧 Email Configuration

### Email-Based Ticketing

**IMAP/POP3 Setup:**
```
Admin Panel → Emails → Add Email
Protocol: IMAP
Server: mail.yourdomain.com
Port: 993
Encryption: SSL
```

### SMTP Notifications

**Gmail:**
```
Hostname: smtp.gmail.com
Port: 587
Auth: Enabled
Username: mailabhirupbanerjee@gmail.com
Password: [App-specific password]
TLS: Yes
```

**Get Gmail App Password:**
1. Google Account → Security
2. 2-Step Verification → App passwords
3. Generate password for Mail/Other
4. Use in osTicket SMTP settings

---

## 💻 VM Requirements Summary

### Production Tiers

| Tier | vCPU | RAM | Storage | Azure Size | Cost/Month |
|------|------|-----|---------|------------|------------|
| Dev/Test | 2 | 4 GB | 30 GB | Standard_B2s | ~$30 |
| Small Prod | 2 | 8 GB | 60 GB | Standard_D2s_v3 | ~$70 |
| Medium Prod | 4 | 16 GB | 60 GB | Standard_D4s_v3 | ~$140 |

### Network Requirements

**Azure NSG Inbound Rules:**
- Port 22: SSH (Admin IP only)
- Port 80: HTTP (Any - redirects to HTTPS)
- Port 443: HTTPS (Any)

**Bandwidth:** 1-5 GB/month for 100 tickets/day

---

## 🔧 Common Scenarios

### Scenario 1: Fresh Installation

1. Read **README.md** → "Quick Start"
2. Follow **INSTALLATION_REFERENCE.md** → Complete guide
3. Verify with checklist in **INSTALLATION_REFERENCE.md**

### Scenario 2: Integration Only (osTicket Already Installed)

1. Skip to **README.md** → "API Integration"
2. Implement code from **INTEGRATION_REFERENCE.md**
3. Test using scripts in **INTEGRATION_REFERENCE.md**

### Scenario 3: Email Notifications Setup

1. Read **README.md** → "SMTP Email Notifications"
2. Choose provider (Gmail/SendGrid/Azure)
3. Configure in osTicket admin panel

### Scenario 4: Troubleshooting

1. Check **README.md** → "Troubleshooting"
2. Review logs locations
3. Use debug commands provided

---

## 🧪 Testing Checklist

### Installation Tests

```bash
# 1. Check services running
sudo systemctl status apache2
sudo systemctl status mariadb

# 2. Test HTTPS
curl -I https://helpdesk.gea.abhirup.app

# 3. Test database
mysql -u ostuser -p osticketdb

# 4. Check SSL auto-renewal
sudo certbot renew --dry-run
```

### Integration Tests

```bash
# 1. Test API connectivity
curl -X POST https://helpdesk.gea.abhirup.app/api/tickets.json \
  -H "X-API-Key: YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"alert":true,"subject":"Test","message":"data:text/html,<p>Test</p>","name":"Test","email":"mailabhirupbanerjee@gmail.com","entity":"Test","system_name":"EA Portal"}'

# 2. Run test scripts
node test-osticket-integration.js
./test-osticket-curl.sh

# 3. Check logs
docker-compose logs -f frontend | grep -i ticket
```

---

## 📞 Support Resources

### Official Documentation

- **osTicket Docs:** https://docs.osticket.com/
- **osTicket Forum:** https://forum.osticket.com/
- **osTicket API:** https://docs.osticket.com/en/latest/Developer/API.html

### Project Support

- **Email:** mailabhirupbanerjee@gmail.com
- **Helpdesk:** https://helpdesk.gea.abhirup.app
- **Project:** Government of Grenada Digital Transformation

### Log Locations

```
Apache:    /var/log/apache2/osticket_error.log
MariaDB:   /var/log/mysql/error.log
osTicket:  /var/www/osticket/data/logs/
Certbot:   /var/log/letsencrypt/letsencrypt.log
Frontend:  docker-compose logs frontend
```

---

## ✅ Success Criteria

### Installation Complete When:

- ✓ osTicket accessible via HTTPS
- ✓ SSL certificate valid and auto-renewing
- ✓ Admin login works
- ✓ Database connected
- ✓ Setup directory removed
- ✓ Config file locked (644 permissions)

### Integration Complete When:

- ✓ API key created and active
- ✓ Email whitelisted
- ✓ Custom fields configured
- ✓ Test ticket created successfully
- ✓ Integration code deployed
- ✓ Feedback submission creates tickets
- ✓ Tickets visible in osTicket dashboard

---

## 🎯 Next Steps

After reviewing documentation:

1. **Plan Installation**
   - Provision Azure VM
   - Configure DNS
   - Prepare .env file

2. **Execute Installation**
   - Run installer script
   - Complete web setup
   - Verify installation

3. **Configure osTicket**
   - Create API key
   - Add custom fields
   - Whitelist emails

4. **Deploy Integration**
   - Copy integration code
   - Update environment
   - Test end-to-end

5. **Production Readiness**
   - Configure backups
   - Set up monitoring
   - Document procedures

---

## 📝 Version Information

**Documentation Version:** 1.0  
**Created:** November 9, 2025  
**Author:** AB, Government of Grenada Digital Transformation Team  
**osTicket Version:** v1.18.2  
**PHP Version:** 8.2  
**OS:** Ubuntu 24.04 LTS  

**Based on:**
- Successful installation on Azure VM2
- Tested API integration with EA Portal
- Production-verified configuration

---

## 🔄 Updates and Maintenance

This documentation reflects the current tested and working configuration. For updates:

1. Check osTicket releases: https://github.com/osTicket/osTicket/releases
2. Review changelog for breaking changes
3. Test updates in development environment first
4. Update documentation as needed

**Backup before upgrades!**

---

**Ready to begin?** Start with **README.md** for overview, then proceed to detailed guides as needed.

---

**End of Documentation Package Summary**
