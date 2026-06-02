/* ═══════════════════════════════════════════════════════
   DIASPORA NEARBY — LANDING PAGE SCRIPTS
   Lucide, platform detection, nav, animations.

   Email-capture flow REMOVED 2026-06-01. Install is now a direct
   Google Play link (Android) or in-page Safari "Add to Home Screen"
   instructions (iOS). The public Closed Testing Google Group
   `diaspora-nearby-testers@googlegroups.com` is set to "Anyone on
   the web can join", so Play Store handles the rest.
   ═══════════════════════════════════════════════════════ */

// ── Route Handling (/invite, /profile) ──
(function handleRoutes() {
    const path = window.location.pathname;
    const params = new URLSearchParams(window.location.search);

    // /invite?code=XXX — capture referral code, scroll to get-app
    if (path === '/invite') {
        const code = params.get('code');
        if (code) {
            localStorage.setItem('dn_referral_code', code);
        }
        document.addEventListener('DOMContentLoaded', () => {
            const getAppSection = document.getElementById('get-app');
            if (getAppSection) {
                setTimeout(() => {
                    const offset = 64;
                    const y = getAppSection.getBoundingClientRect().top + window.pageYOffset - offset;
                    window.scrollTo({ top: y, behavior: 'smooth' });
                }, 300);
            }
        });
    }

    // /profile/{uid} — redirect to web app for profile viewing
    if (path.startsWith('/profile/')) {
        const profilePath = path + window.location.search;
        window.location.replace('https://app.diasporanearby.com' + profilePath);
        return;
    }
})();

// ── Lucide Icons ──
document.addEventListener('DOMContentLoaded', () => {
    if (typeof lucide !== 'undefined') {
        lucide.createIcons();
    }
});

// ── Download URLs ──
const APK_DOWNLOAD_URL = '/downloads/diaspora-nearby.apk';
const PLAY_STORE_LISTING_URL = 'https://play.google.com/store/apps/details?id=com.diasporanearby.diasporanearby';

// ── Platform Detection ──
function detectPlatform() {
    const ua = navigator.userAgent;
    if (/android/i.test(ua)) return 'android';
    if (/iPad|iPhone|iPod/.test(ua) && !window.MSStream) return 'ios';
    if (/Mac/.test(ua)) return 'macos';
    if (/Win/.test(ua)) return 'windows';
    if (/Linux/.test(ua)) return 'linux';
    return 'unknown';
}

const detectedPlatform = detectPlatform();

// ── Update UI based on platform ──
// Only the hero badge and APK-fallback visibility depend on platform now.
function initPlatformUI() {
    const isAndroid = detectedPlatform === 'android';
    const isIOS = detectedPlatform === 'ios';

    const heroPlatformText = document.getElementById('hero-platform-text');
    const heroBadge = document.getElementById('hero-platform-badge');

    if (heroPlatformText) {
        if (isAndroid) {
            heroPlatformText.textContent = 'Android detected — install from Google Play';
            if (heroBadge) heroBadge.classList.add('android');
        } else if (isIOS) {
            heroPlatformText.textContent = 'iPhone detected — install the web app from Safari';
            if (heroBadge) heroBadge.classList.add('ios');
        } else {
            heroPlatformText.textContent = 'Available on Android — iOS coming soon';
        }
    }

    // APK fallback is only relevant for Android visitors.
    const apkFallback = document.getElementById('apk-fallback');
    if (isAndroid && apkFallback) apkFallback.style.display = 'block';
}

document.addEventListener('DOMContentLoaded', initPlatformUI);

// ── APK fallback download (kept for the "advanced" disclosure on Android) ──
function triggerAPKDownload() {
    const link = document.createElement('a');
    link.href = APK_DOWNLOAD_URL;
    link.download = 'diaspora-nearby.apk';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
}

function openPlayStoreListing() {
    window.location.href = PLAY_STORE_LISTING_URL;
}

// ── Mobile Navigation ──
const navToggle = document.getElementById('nav-toggle');
const navLinks = document.getElementById('nav-links');

if (navToggle && navLinks) {
    navToggle.addEventListener('click', () => {
        navLinks.classList.toggle('open');
    });

    navLinks.querySelectorAll('a').forEach((link) => {
        link.addEventListener('click', () => {
            navLinks.classList.remove('open');
        });
    });
}

// ── Smooth Scroll ──
document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
    anchor.addEventListener('click', (e) => {
        const target = document.querySelector(anchor.getAttribute('href'));
        if (target) {
            e.preventDefault();
            const offset = 64;
            const y = target.getBoundingClientRect().top + window.pageYOffset - offset;
            window.scrollTo({ top: y, behavior: 'smooth' });
        }
    });
});

// ── Intersection Observer for fade-in ──
const observer = new IntersectionObserver(
    (entries) => {
        entries.forEach((entry) => {
            if (entry.isIntersecting) {
                entry.target.classList.add('visible');
                observer.unobserve(entry.target);
            }
        });
    },
    { threshold: 0.1, rootMargin: '0px 0px -40px 0px' }
);

document.querySelectorAll('.fade-in').forEach((el) => observer.observe(el));
