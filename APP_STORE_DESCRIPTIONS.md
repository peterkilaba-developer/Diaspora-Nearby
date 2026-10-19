# Diaspora Nearby — App Store & Google Play Store Master Guide

Comprehensive store listing metadata, release notes, app descriptions, data safety declarations, and build instructions for both **Google Play Store (Android)** and **Apple App Store (iOS)**.

---

# PART 1: Google Play Store Console Listing (Android)

## 1. App Details
* **App Name:** `Diaspora Nearby` *(15 / 30 characters)*
* **Package Name (Application ID):** `com.diasporanearby.diasporanearby`
* **Version Name:** `1.2.5`
* **Version Code:** `9`
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

Diaspora Nearby is the sovereign social network engineered for anyone living between two worlds: their home country and their host country. Whether your presence abroad is temporary (as a corporate expat, international diplomat, business professional, traveler, or student) or permanent (as a naturalized citizen, permanent resident, or settled diaspora member), Diaspora Nearby connects you to nested hierarchical communities (Global → Continent → Country → State/Province → City/Town), local compatriots, peer hosting, and verifiable trust.

Key Features:

🌍 Discover Community Nearby
Using privacy-first location technology, discover compatriots from your diaspora residing in your local area. Make friends who share your native language, culture, traditions, and lived diaspora journey.

📍 "Also Lived In" Multi-City Profile
Showcase your global journey! List all the countries and cities you've lived in on your profile, enabling instant connections with members who share common cultural corridors and experiences.

🤝 Proof of Community Trust (PoCT) & Merit-Based Economy
Every verified connection, peer vouch, event check-in, and marketplace transaction earns Diaspora Social Points (DSP) and builds your Proof of Community Trust (PCT) score. Your trust score determines your Token Distribution Event (TDE) efficiency on Base Blockchain by Coinbase.

⚡ Anytime Token Claims & Self-Custody
Claim your earned $DIASPORA tokens on Base L2 directly to your smart wallet anytime via Merkle pull-claims. Unclaimed earned tokens never expire; only unearned tokens forfeited through the efficiency gate are burned to the dead address.

🛡️ 6 Base Proof of Humanity (PoH) Milestones
Unlock the Genesis 7,000 $DIASPORA distribution upon completing 6 foundational identity milestones (Live Location Transparency, Complete Profile, 10 In-Person QR Exchanges, Family Circle, Friend Circle, and 10 Peer Verifications). Ubuntu Emergency Fund contribution is deferred post-genesis.

📅 Discover & Host Community Events
Find cultural festivals, holiday celebrations, and professional networking meetups near you. Host your own gatherings and verify attendees instantly with QR check-ins.

🏡 Peer Hosting & Traveler Stays
Connect with verified high-trust members (91+ PCT) for peer accommodation and trusted stays when traveling between home and host destinations.

💬 Real-Time Messaging & Group Chats
Communicate effortlessly with direct messages, voice notes, photos, and group chats organized by nested geography or interest groups.

🏢 Verified Organizations & Chambers of Commerce
Join diaspora chambers, professional associations, and student unions. Stay informed with official announcements and participate in community governance.

🆘 Ubuntu Emergency Relief
Mutual aid protocols and collective catastrophe protection pools ensuring no diaspora member faces a crisis alone abroad.

Why Diaspora Nearby?
Moving or living abroad should never mean starting from scratch. No matter how far you travel, Diaspora Nearby ensures you are always connected to the warmth, trust, and mutual strength of home.

Download Diaspora Nearby today and find your diaspora wherever you are!
```

---

## 4. Release Notes / What's New *(v1.2.5 — en-US)*
```text
What's New in Version 1.2.5:
• Pull Token Claims: Claim earned $DIASPORA tokens anytime on Base L2 directly to your smart wallet.
• Streamlined Genesis Gate: 6 Base Proof of Humanity milestones unlock your Genesis 7,000 $DIASPORA distribution (Ubuntu Emergency Fund contribution deferred post-genesis).
• Fair Trust Tiers: PCT score below 91 updates access to high-trust privileges without freezing TDE token distributions.
• Enhanced Privacy: Involuntary network or OS-level location pauses no longer trigger transparency penalties.
• Native Base L2 Smart Wallet: Gasless relay and self-custodial key management for seamless on-chain claims.
• UI & Performance: Faster chat syncing, smoother in-person QR handshakes, and reduced battery usage.
```

---

## 5. Google Play Data Safety Answers (Cheat Sheet)
* **Does your app collect or share user data?** -> Yes.
* **Is data encrypted in transit?** -> Yes (HTTPS / TLS 1.3).
* **Do you provide account deletion?** -> Yes (in-app under Settings > Account Deletion or via `support@diasporanearby.com`).
* **Data Types Collected:**
  - *Location (Approximate & Precise):* App functionality (nearby community discovery). Ephemeral; users can adjust range or privacy anytime.
  - *Personal Info (Name, Phone Number):* Account creation and phone verification (Firebase Auth).
  - *Messages:* In-app communication (user-to-user and community group chats).
  - *Photos & Audio:* Optional uploads for profile photos, event images, and voice notes.
  - *Device IDs:* Push notifications via Firebase Cloud Messaging.
* **Data Sharing:** No third-party data sharing or data brokers.

---

## 6. Google Play App Access Credentials (For Reviewers)
When declaring App Access in Google Play Console (Policy > App access):
* **Access Type:** "All or some functionality is restricted"
* **Instructions Name:** `Tester / Reviewer Access`
* **Phone Number:** `+16505551234`
* **OTP / SMS Verification Code:** `123456`
* **Notes:** `Enter +16505551234 on the phone authentication screen, then enter 123456 when prompted for SMS verification code.`

---

## 7. Android Build Command (Production AAB)
```bash
flutter build appbundle --flavor production --build-name=1.2.5 --build-number=9
```
*Output File:* `build/app/outputs/bundle/productionRelease/app-production-release.aab`

---

# PART 2: Apple App Store Connect Listing (iOS)

## 1. App Store Details
* **App Name:** `Diaspora Nearby` *(15 / 30 characters)*
* **Subtitle:** `Connect With Your Diaspora` *(26 / 30 characters)*
* **Bundle ID:** `com.diasporanearby.diasporanearby`
* **Version:** `1.2.5`
* **Build:** `9`
* **Primary Category:** Social Networking
* **Secondary Category:** Travel
* **Age Rating:** 12+ (Infrequent/Mild Social Interactions, User-Generated Content with Report/Block controls)
* **Copyright:** `© 2026 Diaspora Nearby Inc.`

---

## 2. Promotional Text *(145 / 170 characters)*
```text
Find your diaspora community nearby. Connect with local compatriots, discover cultural events, join verified groups, and access peer hospitality.
```

---

## 3. Keywords *(98 / 100 characters)*
```text
diaspora,expat,compatriots,community,events,travel,nearby,african,latino,caribbean,asian,social,chat
```

---

## 4. Full Description *(Apple App Store Optimized — Max 4000 characters)*
```text
Distance doesn't have to mean disconnection.

Diaspora Nearby is the dedicated social network built for anyone living with a dual geographic identity: positioned between their home country and a host country. Whether you are living abroad temporarily (as a professional expat, diplomat, student, business traveler) or permanently (as a settled resident or naturalized citizen), Diaspora Nearby bridges the gap with nested geographical communities, local compatriots, and shared mutual trust.

KEY FEATURES:

• FIND COMMUNITY NEARBY
Discover verified diaspora members in your city or neighborhood. Connect with individuals who share your home country, mother tongue, traditions, and diaspora journey.

• "ALSO LIVED IN" JOURNEY PROFILES
Add the cities and countries where you’ve previously resided to your profile. Instantly find people who share your specific migration routes and international experiences.

• LOCAL EVENTS & CULTURAL GATHERINGS
Find cultural festivals, holiday celebrations, and networking meetups near you. Organize your own gatherings and verify attendance with instant in-person QR check-ins.

• PEER HOSPITALITY & STAYS
Traveling between cities or heading home? Connect with trusted community members for peer recommendations, hosting, and verified stays.

• REAL-TIME CHAT & GROUPS
Stay in touch with direct messages, voice notes, and photos. Participate in nested community chats from your local town up to continental and global channels.

• VERIFIED ORGANIZATIONS
Join diaspora chambers of commerce, cultural associations, and professional networks with verified leadership and governance.

• PROOF OF COMMUNITY TRUST (PoCT)
Build a portable reputation score based on positive real-world interactions, peer verifications, and community engagement.

• BUILT-IN SMART WALLET & UBUNTU AID
Access non-custodial smart wallet utilities on Base Blockchain by Coinbase. Participate in the Ubuntu Emergency mutual aid fund designed to support community members during unforeseen hardships.

PRIVACY & SAFETY:
• Precision location controls: choose your visibility radius or pause location anytime.
• Zero data selling: we never sell personal information to third parties.
• Built-in blocking and reporting tools for safe community interactions.

Download Diaspora Nearby today and stay connected to home, wherever life takes you!
```

---

## 5. What's New in Version 1.2.5 *(App Store Release Notes)*
```text
• Pull Token Claims: Claim earned $DIASPORA tokens on Base L2 directly to your smart wallet anytime.
• 6 Base Proof of Humanity Milestones: Streamlined identity verification unlocking Genesis token distributions (Ubuntu Emergency Fund deferred post-genesis).
• Merit-Based Trust: Dynamic trust scoring ensures fair participation in all distribution events.
• Location Privacy Enhancements: Smarter background location handling that preserves battery life and protects your privacy.
• Performance improvements across chat messaging, media loading, and event QR scanning.
```

---

## 6. URLs for App Store Connect
* **Support URL:** `https://diasporanearby.com`
* **Marketing URL:** `https://diasporanearby.com`
* **Privacy Policy URL:** `https://diasporanearby.com/privacy-policy`
* **Terms of Use (EULA):** `https://diasporanearby.com/terms-of-service`

---

## 7. App Review Information (Notes for Apple Review Team)
```text
App Review Team Notes:

1. DEMO CREDENTIALS:
Phone Number: +16505551234 (or +1 650-555-1234)
Verification Code (SMS / OTP): 123456

2. PURPOSE OF CRYPTO & SMART WALLET (Guideline 3.1.5 Compliance):
- The app integrates a non-custodial smart wallet deployed on the Ethereum Base L2 network (by Coinbase).
- Tokens ($DIASPORA) are strictly utility rewards earned exclusively through authentic social engagement (event check-in, profile completion, peer vouching).
- No tokens, cryptocurrencies, or digital assets can be purchased via in-app purchases or fiat in the app. There are no ICOs, IEOs, or token sales offered within the app.
- Token claims are executed gaslessly or via user-initiated non-custodial pull claims to the user's deterministic smart wallet address.

3. LOCATION USAGE:
- Precise location is used strictly to display approximate distance to other diaspora members who have also enabled location.
- Users can toggle location off inside the app settings at any time without losing access to non-location features (messaging, events, profiles).

4. USER SAFETY & MODERATION (Guideline 1.2 Compliance):
- Users can block any user directly from their profile or message menu.
- Users can report offensive messages, profiles, or events. Reported content is automatically flagged for moderator review.
- Terms of Service explicitly prohibit objectionable content or abusive behavior.
```

---

## 8. iOS Build Command (Production Archive / IPA)
```bash
flutter build ipa --flavor production --build-name=1.2.5 --build-number=9
```
*Output File:* `build/ios/archive/Runner.xcarchive` / `build/ios/ipa/DiasporaNearby.ipa`

---

# PART 3: Public Web & Testing Links

* **Official Website & Landing:** `https://diasporanearby.com`
* **Official Whitepaper:** `https://diasporanearby.com/whitepaper`
* **Web App (PWA):** `https://app.diasporanearby.com`
* **Liquidity Treasury:** `https://diasporanearby.com/liquidity_treasury`
* **Google Play Internal / Closed Testing Link:**
  `https://play.google.com/apps/testing/com.diasporanearby.diasporanearby`
* **Google Play Public Store Link:**
  `https://play.google.com/store/apps/details?id=com.diasporanearby.diasporanearby`
* **Direct Android APK Download:**
  `https://diasporanearby.com/downloads/diaspora-nearby.apk`
