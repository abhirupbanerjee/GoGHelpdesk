# osTicket Integration Reference Guide

**EA Portal Feedback System → osTicket Automatic Ticket Creation**

## 📋 Overview

This guide covers the complete integration between the EA Portal feedback system and osTicket for automatic ticket creation based on service feedback criteria.

### Integration Flow

```
┌──────────────────────────────────────────────────────┐
│          User Submits Feedback                        │
│          (EA Portal or QR Code)                       │
└────────────────────┬─────────────────────────────────┘
                     │
                     ↓
┌──────────────────────────────────────────────────────┐
│     Feedback API Route                                │
│     /api/feedback/submit                              │
│     • Validates input                                 │
│     • Saves to PostgreSQL                             │
│     • Checks ticket criteria                          │
└────────────────────┬─────────────────────────────────┘
                     │
                     ↓
┌──────────────────────────────────────────────────────┐
│     Ticket Criteria Check                             │
│     • Grievance flag = true? → CREATE TICKET          │
│     • Average rating < 3.0? → CREATE TICKET           │
│     • Otherwise → NO TICKET                           │
└────────────────────┬─────────────────────────────────┘
                     │
                     ↓ (if criteria met)
┌──────────────────────────────────────────────────────┐
│     osTicket Integration Library                      │
│     • Formats HTML ticket content                     │
│     • Calls osTicket API                              │
│     • Handles response                                │
└────────────────────┬─────────────────────────────────┘
                     │
                     ↓
┌──────────────────────────────────────────────────────┐
│     osTicket API                                      │
│     POST /api/tickets.json                            │
│     • Creates ticket                                  │
│     • Returns ticket number                           │
└──────────────────────────────────────────────────────┘
```

---

## 🔧 Prerequisites

### osTicket Configuration

**Required Settings:**

1. **API Key Created**
   - Admin Panel → Manage → API Keys
   - Permission: "Can Create Tickets"
   - Status: Active

2. **Email Whitelist**
   - Admin Panel → Emails
   - Add: `mailabhirupbanerjee@gmail.com`
   - Status: Active

3. **Ticket Settings**
   - Admin Panel → Settings → Tickets
   - ☑ Accept Email from Unknown Users
   - ☐ Authorized Users Only (UNCHECKED)

4. **Custom Fields Created**
   - Admin Panel → Manage → Forms → Ticket
   - Field: Entity Name (variable: `entity`, required)
   - Field: System name (variable: `system_name`, optional)

### EA Portal Configuration

**Environment Variables:**

```bash
# .env.dev or .env.production
OSTICKET_API_URL=https://helpdesk.gea.abhirup.app/api/tickets.json
OSTICKET_API_KEY=F2B1D20DBA39B231FCD18B864F4A9EA0
OSTICKET_SYSTEM_EMAIL=mailabhirupbanerjee@gmail.com
```

---

## 📝 API Specification

### osTicket API Endpoint

```
POST https://helpdesk.gea.abhirup.app/api/tickets.json
```

### Required Headers

```
X-API-Key: F2B1D20DBA39B231FCD18B864F4A9EA0
Content-Type: application/json
```

### Request Payload Structure

```typescript
interface OsTicketPayload {
  // Required core fields
  alert: boolean;           // Send email alert
  autorespond: boolean;     // Send auto-response
  source: string;           // "API"
  name: string;             // Ticket submitter name
  email: string;            // Submitter email (must be whitelisted)
  subject: string;          // Ticket subject line
  message: string;          // HTML message (data:text/html,<html>)
  ip: string;               // Client IP address
  
  // Optional fields
  topicId?: number;         // Help topic ID (default: 1)
  priority?: number;        // 1=Low, 2=Normal, 3=High, 4=Urgent
  
  // Custom fields
  entity: string;           // Required: Entity name
  system_name?: string;     // Optional: System identifier
}
```

### Example Payload

```json
{
  "alert": true,
  "autorespond": true,
  "source": "API",
  "name": "EA Portal Feedback System",
  "email": "mailabhirupbanerjee@gmail.com",
  "subject": "[GRIEVANCE] Service Feedback - Passport Application",
  "message": "data:text/html,<h2 style='color:#d32f2f'>⚠️ GRIEVANCE REPORTED</h2><p><strong>Service:</strong> Passport Application</p>",
  "ip": "172.178.28.16",
  "topicId": 1,
  "priority": 4,
  "entity": "Immigration Department",
  "system_name": "EA Portal"
}
```

### Response Format

**Success (HTTP 201):**
```
000007
```
Returns ticket number as plain text (not JSON).

**Error (HTTP 4xx/5xx):**
```json
{
  "error": "Error message description"
}
```

Or plain text error message.

---

## 💻 Integration Implementation

### 1. osTicket Integration Library

**File:** `frontend/src/lib/osticket-integration.ts`

```typescript
// osTicket Integration Library
// Handles automatic ticket creation for EA Portal feedback

interface FeedbackData {
  id: number;
  service_name: string;
  entity_name: string;
  channel_type: string;
  grievance_flag: boolean;
  rating_ease: number;
  rating_efficiency: number;
  rating_responsiveness: number;
  rating_quality: number;
  rating_satisfaction: number;
  comments?: string;
  ip_address?: string;
}

interface OsTicketConfig {
  apiUrl: string;
  apiKey: string;
  systemEmail: string;
}

interface OsTicketPayload {
  alert: boolean;
  autorespond: boolean;
  source: string;
  name: string;
  email: string;
  subject: string;
  message: string;
  ip: string;
  topicId: number;
  priority: number;
  entity: string;
  system_name: string;
}

export class OsTicketIntegration {
  private config: OsTicketConfig;

  constructor(config: OsTicketConfig) {
    this.config = config;
  }

  /**
   * Determines if feedback requires a ticket
   */
  requiresTicket(feedback: FeedbackData): boolean {
    // Create ticket if grievance is flagged
    if (feedback.grievance_flag) {
      return true;
    }

    // Create ticket if average rating is below threshold (3.0)
    const avgRating = this.calculateAverageRating(feedback);
    return avgRating < 3.0;
  }

  /**
   * Calculate average rating from all rating fields
   */
  private calculateAverageRating(feedback: FeedbackData): number {
    const ratings = [
      feedback.rating_ease,
      feedback.rating_efficiency,
      feedback.rating_responsiveness,
      feedback.rating_quality,
      feedback.rating_satisfaction
    ];

    const sum = ratings.reduce((acc, rating) => acc + rating, 0);
    return sum / ratings.length;
  }

  /**
   * Create osTicket ticket for feedback
   */
  async createTicket(feedback: FeedbackData): Promise<{ success: boolean; ticketId?: string; error?: string }> {
    try {
      const avgRating = this.calculateAverageRating(feedback);
      const payload = this.buildPayload(feedback, avgRating);

      const response = await fetch(this.config.apiUrl, {
        method: 'POST',
        headers: {
          'X-API-Key': this.config.apiKey,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload)
      });

      // osTicket returns 201 Created on success
      if (response.status === 201) {
        const ticketId = await response.text(); // Returns ticket number as plain text
        console.log(`✓ osTicket created: ${ticketId} for feedback #${feedback.id}`);
        
        return {
          success: true,
          ticketId: ticketId.trim()
        };
      }

      // Handle errors
      const errorText = await response.text();
      console.error(`✗ osTicket creation failed: ${errorText}`);
      
      return {
        success: false,
        error: errorText
      };

    } catch (error) {
      console.error('✗ osTicket integration error:', error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      };
    }
  }

  /**
   * Build osTicket API payload
   */
  private buildPayload(feedback: FeedbackData, avgRating: number): OsTicketPayload {
    const subject = this.buildSubject(feedback, avgRating);
    const message = this.buildHtmlMessage(feedback, avgRating);

    return {
      alert: true,
      autorespond: true,
      source: 'API',
      name: 'EA Portal Feedback System',
      email: this.config.systemEmail,
      subject: subject,
      message: `data:text/html,${message}`,
      ip: feedback.ip_address || '172.178.28.16',
      topicId: 1,
      priority: feedback.grievance_flag ? 4 : 2, // Urgent for grievance, Normal otherwise
      entity: feedback.entity_name,
      system_name: 'EA Portal'
    };
  }

  /**
   * Build ticket subject line
   */
  private buildSubject(feedback: FeedbackData, avgRating: number): string {
    if (feedback.grievance_flag) {
      return `[GRIEVANCE] Service Feedback - ${feedback.service_name}`;
    }
    return `[LOW RATING ${avgRating.toFixed(1)}/5] Service Feedback - ${feedback.service_name}`;
  }

  /**
   * Build HTML formatted message
   */
  private buildHtmlMessage(feedback: FeedbackData, avgRating: number): string {
    let html = '';

    // Grievance alert banner
    if (feedback.grievance_flag) {
      html += `
        <div style="background-color:#ffebee; border-left:4px solid #d32f2f; padding:12px; margin-bottom:16px;">
          <h2 style="color:#d32f2f; margin:0 0 8px 0;">⚠️ GRIEVANCE REPORTED</h2>
          <p style="margin:0; color:#666;">This feedback has been flagged as containing a grievance.</p>
        </div>
      `;
    }

    // Feedback details
    html += `
      <h3 style="color:#1976d2; margin-top:0;">Feedback Details</h3>
      <table style="width:100%; border-collapse:collapse; margin-bottom:16px;">
        <tr style="background-color:#f5f5f5;">
          <td style="padding:8px; border:1px solid #ddd; font-weight:bold;">Feedback ID</td>
          <td style="padding:8px; border:1px solid #ddd;">#${feedback.id}</td>
        </tr>
        <tr>
          <td style="padding:8px; border:1px solid #ddd; font-weight:bold;">Service</td>
          <td style="padding:8px; border:1px solid #ddd;">${feedback.service_name}</td>
        </tr>
        <tr style="background-color:#f5f5f5;">
          <td style="padding:8px; border:1px solid #ddd; font-weight:bold;">Entity</td>
          <td style="padding:8px; border:1px solid #ddd;">${feedback.entity_name}</td>
        </tr>
        <tr>
          <td style="padding:8px; border:1px solid #ddd; font-weight:bold;">Channel</td>
          <td style="padding:8px; border:1px solid #ddd;">${feedback.channel_type}</td>
        </tr>
      </table>
    `;

    // Ratings table
    html += `
      <h3 style="color:#1976d2;">Service Ratings</h3>
      <table style="width:100%; border-collapse:collapse; margin-bottom:16px;">
        <tr style="background-color:#1976d2; color:white;">
          <th style="padding:8px; border:1px solid #ddd; text-align:left;">Criteria</th>
          <th style="padding:8px; border:1px solid #ddd; text-align:center;">Rating</th>
        </tr>
        ${this.buildRatingRow('Ease of Access', feedback.rating_ease)}
        ${this.buildRatingRow('Efficiency', feedback.rating_efficiency)}
        ${this.buildRatingRow('Responsiveness', feedback.rating_responsiveness)}
        ${this.buildRatingRow('Quality', feedback.rating_quality)}
        ${this.buildRatingRow('Overall Satisfaction', feedback.rating_satisfaction)}
        <tr style="background-color:#e3f2fd; font-weight:bold;">
          <td style="padding:8px; border:1px solid #ddd;">Average Rating</td>
          <td style="padding:8px; border:1px solid #ddd; text-align:center;">${avgRating.toFixed(2)} / 5.0</td>
        </tr>
      </table>
    `;

    // Comments section
    if (feedback.comments) {
      html += `
        <h3 style="color:#1976d2;">User Comments</h3>
        <div style="background-color:#f5f5f5; border:1px solid #ddd; padding:12px; border-radius:4px;">
          <p style="margin:0; white-space:pre-wrap;">${this.escapeHtml(feedback.comments)}</p>
        </div>
      `;
    }

    return html;
  }

  /**
   * Build rating table row with stars
   */
  private buildRatingRow(label: string, rating: number): string {
    const stars = '★'.repeat(rating) + '☆'.repeat(5 - rating);
    const color = rating < 3 ? '#d32f2f' : rating < 4 ? '#ff9800' : '#4caf50';
    
    return `
      <tr style="background-color:#f5f5f5;">
        <td style="padding:8px; border:1px solid #ddd;">${label}</td>
        <td style="padding:8px; border:1px solid #ddd; text-align:center; color:${color}; font-size:18px;">
          ${stars} (${rating})
        </td>
      </tr>
    `;
  }

  /**
   * Escape HTML for safe display
   */
  private escapeHtml(text: string): string {
    const map: { [key: string]: string } = {
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#039;'
    };
    return text.replace(/[&<>"']/g, m => map[m]);
  }
}

// Export singleton instance
export const osTicket = new OsTicketIntegration({
  apiUrl: process.env.OSTICKET_API_URL || 'https://helpdesk.gea.abhirup.app/api/tickets.json',
  apiKey: process.env.OSTICKET_API_KEY || '',
  systemEmail: process.env.OSTICKET_SYSTEM_EMAIL || 'mailabhirupbanerjee@gmail.com'
});
```

### 2. API Route Handler

**File:** `frontend/src/app/api/feedback/submit/route.ts`

```typescript
import { NextRequest, NextResponse } from 'next/server';
import { Pool } from 'pg';
import { osTicket } from '@/lib/osticket-integration';

// Database connection pool
const pool = new Pool({
  connectionString: process.env.DATABASE_URL
});

// Rate limiting (simple in-memory implementation)
const rateLimitMap = new Map<string, number[]>();
const RATE_LIMIT_WINDOW = 60 * 60 * 1000; // 1 hour
const MAX_SUBMISSIONS = 10;

/**
 * POST /api/feedback/submit
 * Submit service feedback and create osTicket if criteria met
 */
export async function POST(request: NextRequest) {
  try {
    // Get client IP for rate limiting
    const clientIp = request.ip || request.headers.get('x-forwarded-for') || 'unknown';
    
    // Check rate limit
    if (isRateLimited(clientIp)) {
      return NextResponse.json(
        { error: 'Rate limit exceeded. Maximum 10 submissions per hour.' },
        { status: 429 }
      );
    }

    // Parse request body
    const body = await request.json();
    
    // Validate required fields
    const validation = validateFeedback(body);
    if (!validation.valid) {
      return NextResponse.json(
        { error: validation.error },
        { status: 400 }
      );
    }

    // Save feedback to database
    const feedbackId = await saveFeedback(body, clientIp);

    // Check if ticket creation is required
    const feedbackData = { id: feedbackId, ...body, ip_address: clientIp };
    
    let ticketInfo = null;
    if (osTicket.requiresTicket(feedbackData)) {
      const ticketResult = await osTicket.createTicket(feedbackData);
      
      if (ticketResult.success) {
        ticketInfo = {
          created: true,
          ticketId: ticketResult.ticketId,
          reason: body.grievance_flag ? 'grievance' : 'low_rating'
        };
        
        console.log(`✓ Ticket ${ticketResult.ticketId} created for feedback #${feedbackId}`);
      } else {
        console.error(`✗ Failed to create ticket for feedback #${feedbackId}:`, ticketResult.error);
        // Continue - feedback is saved even if ticket creation fails
      }
    }

    // Update rate limit
    updateRateLimit(clientIp);

    return NextResponse.json({
      success: true,
      feedback_id: feedbackId,
      ticket: ticketInfo,
      message: 'Feedback submitted successfully'
    }, { status: 201 });

  } catch (error) {
    console.error('Feedback submission error:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}

/**
 * Validate feedback data
 */
function validateFeedback(data: any): { valid: boolean; error?: string } {
  const required = [
    'service_id',
    'entity_id',
    'channel_type',
    'rating_ease',
    'rating_efficiency',
    'rating_responsiveness',
    'rating_quality',
    'rating_satisfaction'
  ];

  for (const field of required) {
    if (data[field] === undefined || data[field] === null) {
      return { valid: false, error: `Missing required field: ${field}` };
    }
  }

  // Validate ratings are 1-5
  const ratings = [
    data.rating_ease,
    data.rating_efficiency,
    data.rating_responsiveness,
    data.rating_quality,
    data.rating_satisfaction
  ];

  for (const rating of ratings) {
    if (rating < 1 || rating > 5) {
      return { valid: false, error: 'Ratings must be between 1 and 5' };
    }
  }

  return { valid: true };
}

/**
 * Save feedback to database
 */
async function saveFeedback(data: any, ipAddress: string): Promise<number> {
  const query = `
    INSERT INTO service_feedback (
      service_id, entity_id, channel_type,
      rating_ease, rating_efficiency, rating_responsiveness,
      rating_quality, rating_satisfaction,
      comments, grievance_flag, ip_address
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
    RETURNING id
  `;

  const values = [
    data.service_id,
    data.entity_id,
    data.channel_type,
    data.rating_ease,
    data.rating_efficiency,
    data.rating_responsiveness,
    data.rating_quality,
    data.rating_satisfaction,
    data.comments || null,
    data.grievance_flag || false,
    ipAddress
  ];

  const result = await pool.query(query, values);
  return result.rows[0].id;
}

/**
 * Check if IP is rate limited
 */
function isRateLimited(ip: string): boolean {
  const now = Date.now();
  const timestamps = rateLimitMap.get(ip) || [];
  
  // Remove old timestamps
  const recentTimestamps = timestamps.filter(
    ts => now - ts < RATE_LIMIT_WINDOW
  );
  
  return recentTimestamps.length >= MAX_SUBMISSIONS;
}

/**
 * Update rate limit for IP
 */
function updateRateLimit(ip: string): void {
  const now = Date.now();
  const timestamps = rateLimitMap.get(ip) || [];
  
  // Remove old timestamps
  const recentTimestamps = timestamps.filter(
    ts => now - ts < RATE_LIMIT_WINDOW
  );
  
  // Add new timestamp
  recentTimestamps.push(now);
  rateLimitMap.set(ip, recentTimestamps);
}
```

---

## 🧪 Testing the Integration

### 1. Test Script

**File:** `test-osticket-integration.js`

```javascript
#!/usr/bin/env node
const OSTICKET_API_URL = 'https://helpdesk.gea.abhirup.app/api/tickets.json';
const API_KEY = 'F2B1D20DBA39B231FCD18B864F4A9EA0';

async function testGrievanceTicket() {
  console.log('Testing: Grievance Ticket Creation');
  
  const payload = {
    alert: true,
    autorespond: true,
    source: "API",
    name: "EA Portal Feedback System",
    email: "mailabhirupbanerjee@gmail.com",
    subject: "[GRIEVANCE] Service Feedback - Passport Application",
    message: "data:text/html,<h2>⚠️ GRIEVANCE</h2><p>Service: Passport Application</p>",
    ip: "172.178.28.16",
    topicId: 1,
    priority: 4,
    entity: "Immigration Department",
    system_name: "EA Portal"
  };

  try {
    const response = await fetch(OSTICKET_API_URL, {
      method: 'POST',
      headers: {
        'X-API-Key': API_KEY,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    });

    if (response.status === 201) {
      const ticketId = await response.text();
      console.log('✓ Ticket created:', ticketId);
      return true;
    } else {
      const error = await response.text();
      console.error('✗ Failed:', error);
      return false;
    }
  } catch (error) {
    console.error('✗ Error:', error);
    return false;
  }
}

async function testLowRatingTicket() {
  console.log('Testing: Low Rating Ticket Creation');
  
  const payload = {
    alert: true,
    autorespond: true,
    source: "API",
    name: "EA Portal Feedback System",
    email: "mailabhirupbanerjee@gmail.com",
    subject: "[LOW RATING 2.4/5] Service Feedback - Tax Filing",
    message: "data:text/html,<h2>Low Rating Alert</h2><p>Average rating: 2.4/5</p>",
    ip: "172.178.28.16",
    topicId: 1,
    priority: 2,
    entity: "Tax Department",
    system_name: "EA Portal"
  };

  try {
    const response = await fetch(OSTICKET_API_URL, {
      method: 'POST',
      headers: {
        'X-API-Key': API_KEY,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    });

    if (response.status === 201) {
      const ticketId = await response.text();
      console.log('✓ Ticket created:', ticketId);
      return true;
    } else {
      const error = await response.text();
      console.error('✗ Failed:', error);
      return false;
    }
  } catch (error) {
    console.error('✗ Error:', error);
    return false;
  }
}

async function runTests() {
  console.log('osTicket Integration Tests\n');
  
  const test1 = await testGrievanceTicket();
  console.log('');
  
  const test2 = await testLowRatingTicket();
  console.log('');
  
  console.log('Results:');
  console.log(`Grievance Ticket: ${test1 ? '✓ PASS' : '✗ FAIL'}`);
  console.log(`Low Rating Ticket: ${test2 ? '✓ PASS' : '✗ FAIL'}`);
  
  if (test1 && test2) {
    console.log('\n✓ All tests passed!');
    console.log('Check tickets at: https://helpdesk.gea.abhirup.app/scp');
  }
}

runTests();
```

Run tests:
```bash
chmod +x test-osticket-integration.js
node test-osticket-integration.js
```

### 2. curl Test Script

**File:** `test-osticket-curl.sh`

```bash
#!/bin/bash
API_URL="https://helpdesk.gea.abhirup.app/api/tickets.json"
API_KEY="F2B1D20DBA39B231FCD18B864F4A9EA0"

echo "=== Test 1: Grievance Ticket ==="
curl -X POST "$API_URL" \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "alert": true,
    "autorespond": true,
    "source": "API",
    "name": "Test User",
    "email": "mailabhirupbanerjee@gmail.com",
    "subject": "[GRIEVANCE] Test",
    "message": "data:text/html,<p>Test</p>",
    "ip": "172.178.28.16",
    "topicId": 1,
    "priority": 4,
    "entity": "Test Entity",
    "system_name": "EA Portal"
  }'
echo -e "\n"

echo "=== Test 2: Low Rating Ticket ==="
curl -X POST "$API_URL" \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "alert": true,
    "autorespond": true,
    "source": "API",
    "name": "Test User",
    "email": "mailabhirupbanerjee@gmail.com",
    "subject": "[LOW RATING 2.5/5] Test",
    "message": "data:text/html,<p>Test</p>",
    "ip": "172.178.28.16",
    "topicId": 1,
    "priority": 2,
    "entity": "Test Entity",
    "system_name": "EA Portal"
  }'
echo -e "\n"
```

---

## 🚀 Deployment

### 1. Copy Files

```bash
# On local machine
cd ~/Projects/GoGEAPortal

# Copy integration library
cp osticket-integration.ts frontend/src/lib/

# Copy API route
mkdir -p frontend/src/app/api/feedback/submit
cp feedback-submit-route.ts frontend/src/app/api/feedback/submit/route.ts
```

### 2. Update Environment

```bash
# Edit .env.dev
nano .env.dev

# Add osTicket configuration
OSTICKET_API_URL=https://helpdesk.gea.abhirup.app/api/tickets.json
OSTICKET_API_KEY=F2B1D20DBA39B231FCD18B864F4A9EA0
OSTICKET_SYSTEM_EMAIL=mailabhirupbanerjee@gmail.com
```

### 3. Rebuild and Deploy

```bash
# Rebuild frontend with integration
docker-compose up -d --build frontend

# Verify containers running
docker-compose ps

# Watch logs
docker-compose logs -f frontend
```

### 4. Verify Integration

```bash
# Check environment variables loaded
docker-compose exec frontend env | grep OSTICKET

# Test feedback submission
curl -X POST http://localhost:3000/api/feedback/submit \
  -H "Content-Type: application/json" \
  -d '{
    "service_id": 1,
    "entity_id": 1,
    "channel_type": "EA_PORTAL",
    "rating_ease": 2,
    "rating_efficiency": 2,
    "rating_responsiveness": 2,
    "rating_quality": 2,
    "rating_satisfaction": 2,
    "comments": "Test integration",
    "grievance_flag": false
  }'
```

---

## 📊 Monitoring

### Check Ticket Creation Logs

```bash
# Watch frontend logs for ticket creation
docker-compose logs -f frontend | grep -i ticket

# Look for:
# ✓ Ticket created for feedback #123: Grievance flagged
# ✓ Ticket created for feedback #124: Low rating: 2.40/5
# ✗ Failed to create ticket for feedback #125: [error]
```

### View Tickets in osTicket

Login: `https://helpdesk.gea.abhirup.app/scp`

**Check for:**
- [GRIEVANCE] tickets with Priority: Urgent
- [LOW RATING X.X/5] tickets with Priority: Normal
- Entity Name field populated
- HTML formatting preserved
- All ratings displayed correctly

### Database Queries

```sql
-- Count tickets created today
SELECT COUNT(*) FROM service_feedback 
WHERE created_at::date = CURRENT_DATE;

-- Count tickets that should have created osTickets
SELECT COUNT(*) FROM service_feedback 
WHERE grievance_flag = true 
   OR (rating_ease + rating_efficiency + rating_responsiveness + rating_quality + rating_satisfaction) / 5.0 < 3.0;

-- View recent feedback requiring tickets
SELECT id, service_name, grievance_flag,
       (rating_ease + rating_efficiency + rating_responsiveness + rating_quality + rating_satisfaction) / 5.0 AS avg_rating
FROM service_feedback 
WHERE grievance_flag = true 
   OR (rating_ease + rating_efficiency + rating_responsiveness + rating_quality + rating_satisfaction) / 5.0 < 3.0
ORDER BY created_at DESC LIMIT 20;
```

---

## 🔧 Troubleshooting

### Ticket Creation Fails

**Check API Key:**
```bash
# Verify in osTicket admin
# Admin Panel → Manage → API Keys
# Status must be: Active
# Permission must include: Can Create Tickets
```

**Check Email Whitelist:**
```bash
# Verify in osTicket admin
# Admin Panel → Emails
# mailabhirupbanerjee@gmail.com must be listed and active
```

**Test API Directly:**
```bash
curl -v -X POST https://helpdesk.gea.abhirup.app/api/tickets.json \
  -H "X-API-Key: F2B1D20DBA39B231FCD18B864F4A9EA0" \
  -H "Content-Type: application/json" \
  -d '{"alert":true,"subject":"Test","message":"data:text/html,<p>Test</p>","name":"Test","email":"mailabhirupbanerjee@gmail.com","entity":"Test","system_name":"EA Portal"}'
```

### Custom Fields Not Populated

**Verify field variable names:**
```sql
-- On osTicket server
mysql -u ostuser -p osticketdb
SELECT id, name, label FROM ost_form_field WHERE label LIKE '%Entity%';
```

**Ensure using variable names, not field IDs:**
```javascript
// Correct:
{
  "entity": "Immigration Department",
  "system_name": "EA Portal"
}

// Incorrect:
{
  "field_36": "Immigration Department",
  "field_37": "EA Portal"
}
```

### Rate Limiting Issues

```bash
# Check rate limit map
# Edit route.ts to adjust limits:
const MAX_SUBMISSIONS = 10;  // Increase if needed
const RATE_LIMIT_WINDOW = 60 * 60 * 1000;  // 1 hour
```

---

## 📈 Performance Optimization

### Async Ticket Creation

For high-volume scenarios, create tickets asynchronously:

```typescript
// Don't wait for ticket creation
osTicket.createTicket(feedbackData).catch(error => {
  console.error('Background ticket creation failed:', error);
});

// Return immediately
return NextResponse.json({ success: true, feedback_id: feedbackId });
```

### Batch Ticket Creation

For bulk processing:

```typescript
// Queue system (Redis, Bull, etc.)
await ticketQueue.add({
  feedbackId: feedbackId,
  data: feedbackData
});
```

---

## 📚 Additional Resources

- osTicket API Documentation: https://docs.osticket.com/en/latest/Developer/API.html
- EA Portal Feedback System: See main README
- Tested Integration Scripts: See conversation history

---

**Last Updated:** November 9, 2025  
**Version:** 1.0  
**Author:** AB, Government of Grenada Digital Transformation Team
