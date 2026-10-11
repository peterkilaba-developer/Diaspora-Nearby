# Google Play Store Console Master Guide & Store Listing

## 1. App Details & Store Listing
* **App Name:** `Diaspora Nearby` *(15 / 30 characters)*
* **Package Name (Application ID):** `com.diasporanearby.diasporanearby`
* **Category:** Social
* **Tags:** Social networking, Community, Travel & Local, Events
* **Support Email:** `support@diasporanearby.com`
* **Website:** `https://diasporanearby.com`
* **Privacy Policy URL:** `https://diasporanearby.com/privacy-policy`
* **Terms of Service URL:** `https://diasporanearby.com/terms-of-service`

---

## 2. Short Description *(78 / 80 characters)*
```text
Connect with your diaspora community nearby. Find friends, events, and groups.
```

---

## 3. Full Description *(Max 4000 characters)*
```text
Distance doesn't have to mean disconnection.

Diaspora Nearby is the social sovereign platform designed for anyone with a dual geographic identity positioned between their home country and another country (host country). Whether your host status is temporary (as a corporate expat, international diplomat, business professional, traveler, or student) or permanent (as a naturalized citizen, permanent resident, or settled diaspora member), Diaspora Nearby helps you navigate nested hierarchical communities (Global → Continent → Country → State/Province → City/Town), discover local compatriots, access peer hosting and stays, and build portable trust.

Key Features:

🌍 Find Community Nearby
Using precise location technology, see who from your diaspora is living around you. Make new friends who share your background, language, and culture.

📍 "Also Lived In"
Showcase your journey! Display the countries and cities you’ve lived in on your profile, making it easier to connect with others who have shared similar experiences.

🤝 Proof of Community Trust & Sovereign Social Economy
Every connection, vouch, and community participation mints portable trust points that translate into shared value for you and your community treasuries.

📅 Discover & Host Events
Never miss out on a cultural gathering again. Find community meetups, festivals, and networking events happening near you. Organizing something? Create and promote your own events to the local community.

💬 Connect & Chat
Start conversations instantly. Send text messages, voice notes, photos, and videos. Create group chats for your local community or interest groups.

🏢 Organizations & Groups
Join verified organizations and community groups. Stay updated with announcements and engage with members in dedicated group chats.

🛡️ Ubuntu Emergency Relief & Peer Hosting
Emergency mutual aid protocols and peer hospitality networks designed for community resilience wherever you are in the world.

📸 Share Your World
Update your profile and share moments with your community across borders.

Why Diaspora Nearby?
Moving to a new place is hard, but finding your community shouldn't be. We believe that no matter how far you travel, you should always be able to find a sense of home.

Download Diaspora Nearby today and start building your local community!
```

---

## 4. Release Notes / What's New *(en-US)*
*(Copy & paste into the Release Notes box when creating a new release in Google Play Console)*
```text
Welcome to Diaspora Nearby!
- Discover compatriots and diaspora community members nearby with privacy-first distance controls.
- "Also Lived In" profile feature to connect across all the cities and countries you've called home.
- Community and peer hosting networks, events, and localized group messaging.
- Proof of Community Trust (PoCT) and Proof of Humanity (PoH) milestones.
- Ubuntu Emergency mutual aid support and community treasuries.
- Performance optimizations, low-latency encrypted messaging, and battery efficiency.
```

---

## 5. Testing & Download URLs
* **Google Play Testing Track Opt-In Link (Closed / Open Testing):**
  `https://play.google.com/apps/testing/com.diasporanearby.diasporanearby`
  *(Testers must open this URL to accept the test before downloading if using a Closed testing track)*
* **Direct Google Play Store Listing Link:**
  `https://play.google.com/store/apps/details?id=com.diasporanearby.diasporanearby`
* **Google Testers Group:**
  `https://groups.google.com/g/diaspora-nearby-testers`
* **Web App (Direct In-Browser Access):**
  `https://app.diasporanearby.com`
* **Direct Android APK Download:**
  `https://diasporanearby.com/downloads/diaspora-nearby.apk`

---

## 6. Google Play Data Safety Answers (Cheat Sheet)
When completing the **Data Safety** questionnaire in Google Play Console:
1. **Does your app collect or share any of the required user data types?** -> **Yes**
2. **Is all of the user data collected by your app encrypted in transit?** -> **Yes** (all communication uses HTTPS / TLS)
3. **Do you provide a way for users to request that their data be deleted?** -> **Yes** (via in-app account deletion under Settings or email request to `support@diasporanearby.com`)
4. **Data Types Collected:**
   * **Location:**
     - *Approximate location:* Collected (App functionality, nearby community discovery)
     - *Precise location:* Collected (App functionality, nearby community discovery)
     - *Is it ephemeral?* Optional / toggleable in profile.
   * **Personal info:**
     - *Name:* Collected (App functionality, account management)
     - *Email address:* Collected (Account management)
     - *Phone number:* Collected (Authentication via Firebase / SMS / WhatsApp)
   * **Photos and videos:**
     - *Photos:* Collected (App functionality, profile picture, post/chat sharing - optional)
     - *Videos:* Collected (Optional, user media sharing)
   * **Audio:**
     - *Voice recordings:* Collected (Voice notes in chat - optional)
   * **Messages:**
     - *In-app messages:* Collected (Core chat functionality)
   * **Device or other IDs:**
     - *Device or other IDs:* Collected (App functionality, Firebase Cloud Messaging push notifications)
5. **Data Sharing:**
   * **Does your app share user data with other companies or organizations?** -> **No** (we do not sell or share data with third parties outside essential service infrastructure like Firebase/Google Cloud).

---

## 7. App Content Declarations Checklist
* **Privacy Policy:** `https://diasporanearby.com/privacy-policy`
* **App Access:** All functionality is available without special restrictions (or provide test credentials if required by Google reviewers).
* **Ads:** "No, my app does not contain ads".
* **Content Rating:** Standard social networking questionnaire (moderate user-generated content, report/block feature available).
* **Target Audience:** 18+ (or 13+ with parental consent).
* **News App:** No.
* **COVID-19 Contact Tracing:** No.
* **Government Apps:** No.
* **Financial Features:** Utility tokens / Community points (DSP) on Base network.

---

## 8. Command to Build Production App Bundle (AAB)
When ready to upload a new build to Google Play Console:
```bash
flutter build appbundle --flavor production
```
The output `.aab` file will be generated at:
`build/app/outputs/bundle/productionRelease/app-production-release.aab`
*(or `build/app/outputs/bundle/release/app-release.aab`)*
