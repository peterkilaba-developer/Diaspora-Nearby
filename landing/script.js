/* ═══════════════════════════════════════════════════════
   DIASPORA NEARBY — LANDING PAGE SCRIPTS
   Lucide, platform detection, early access signup, nav, animations
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
        // Scroll to get-app section after DOM loads
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
// Google Play closed testing opt-in link — testers who are in the Google Group can join
const PLAY_STORE_TEST_URL = 'https://play.google.com/apps/testing/com.diasporanearby.diasporanearby';
// Google Group join page — testers must join this group to get Play Store access
const GOOGLE_GROUP_JOIN_URL = 'https://groups.google.com/g/diaspora-nearby-testers';
// Deep link that opens the app listing in the Play Store app on the device
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
function initPlatformUI() {
    const isAndroid = detectedPlatform === 'android';
    const isIOS = detectedPlatform === 'ios';
    const isMobile = isAndroid || isIOS;

    // Hero section platform badge
    const heroPlatformText = document.getElementById('hero-platform-text');
    const heroBtnText = document.getElementById('hero-btn-text');
    const heroBadge = document.getElementById('hero-platform-badge');

    if (heroPlatformText) {
        if (isAndroid) {
            heroPlatformText.textContent = 'Android detected — install via Google Play';
            if (heroBadge) heroBadge.classList.add('android');
        } else if (isIOS) {
            heroPlatformText.textContent = 'iOS detected — TestFlight invite';
            if (heroBadge) heroBadge.classList.add('ios');
        } else {
            heroPlatformText.textContent = 'Enter your email to get the native app';
        }
    }

    if (heroBtnText) {
        if (isAndroid) {
            heroBtnText.textContent = 'Sign Up & Get the App';
        } else if (isIOS) {
            heroBtnText.textContent = 'Sign Up for TestFlight';
        } else {
            heroBtnText.textContent = 'Get Early Access';
        }
    }

    // Install section platform detection
    const installDetectedText = document.getElementById('install-detected-text');
    const installBtnText = document.getElementById('install-btn-text');
    const androidOpt = document.getElementById('install-android-opt');
    const iosOpt = document.getElementById('install-ios-opt');

    if (installDetectedText) {
        if (isAndroid) {
            installDetectedText.textContent = 'Android detected — install from Google Play after signup';
        } else if (isIOS) {
            installDetectedText.textContent = 'iOS detected — we\u2019ll send your TestFlight invite';
        } else {
            installDetectedText.textContent = 'We\u2019ll send you the right version for your device';
        }
    }

    if (installBtnText) {
        if (isAndroid) {
            installBtnText.textContent = 'Sign Up & Get the App';
        } else if (isIOS) {
            installBtnText.textContent = 'Sign Up for TestFlight';
        } else {
            installBtnText.textContent = 'Get Early Access';
        }
    }

    // Highlight detected platform in the install section
    if (isAndroid && androidOpt) {
        androidOpt.classList.add('active');
    } else if (isIOS && iosOpt) {
        iosOpt.classList.add('active');
    }

    // Show Play Store and APK fallback buttons only for Android
    const playStoreDirect = document.getElementById('play-store-direct');
    const apkFallback = document.getElementById('apk-fallback');
    if (isAndroid) {
        if (playStoreDirect) playStoreDirect.style.display = 'block';
        if (apkFallback) apkFallback.style.display = 'block';
    }

    // ── Restore persisted state: hide already-completed steps ──
    // If user already signed up via hero form
    if (localStorage.getItem('dn_signup_hero')) {
        const heroEmail = document.getElementById('hero-email');
        const heroBtn = document.getElementById('hero-signup-btn');
        const heroMsg = document.getElementById('hero-signup-message');
        if (heroEmail) heroEmail.style.display = 'none';
        if (heroBtn) heroBtn.style.display = 'none';
        if (heroMsg) {
            heroMsg.textContent = '✓ You\'re signed up!';
            heroMsg.className = 'form-message success';
        }
        // Show tester steps for Android
        if (isAndroid && heroMsg) showTesterSteps(heroMsg);
    }

    // If user already signed up via install form
    if (localStorage.getItem('dn_signup_install')) {
        const installEmail = document.getElementById('install-email');
        const installBtn = document.getElementById('install-signup-btn');
        const installMsg = document.getElementById('install-signup-message');
        if (installEmail) installEmail.style.display = 'none';
        if (installBtn) installBtn.style.display = 'none';
        if (installMsg) {
            installMsg.textContent = '✓ You\'re signed up!';
            installMsg.className = 'form-message success';
        }
        if (isAndroid && installMsg) showTesterSteps(installMsg);
    }
}

// Initialize after DOM is ready
document.addEventListener('DOMContentLoaded', initPlatformUI);

// ── Early Access Signup ──
async function submitEarlyAccess(formPrefix) {
    const emailInput = document.getElementById(formPrefix + '-email');
    const msgEl = document.getElementById(formPrefix + '-signup-message');
    const btn = document.getElementById(formPrefix + '-signup-btn');
    const btnText = document.getElementById(formPrefix + '-btn-text');
    const email = emailInput?.value?.trim();

    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        showMessage(msgEl, 'Please enter a valid email address.', 'error');
        return;
    }

    btn.disabled = true;
    const originalText = btnText?.textContent;
    if (btnText) btnText.textContent = 'Signing up\u2026';

    try {
        const addPlayStoreTester = window._addPlayStoreTester;

        if (!addPlayStoreTester) {
            throw new Error('Secure signup service is unavailable');
        }

        // Capture referral code from invite link (if any)
        const referralCode = localStorage.getItem('dn_referral_code') || null;

        const signupType = detectedPlatform === 'android'
            ? 'play_store_closed_test'
            : detectedPlatform === 'ios' ? 'testflight' : 'early_access';
        const result = await addPlayStoreTester({
            email,
            platform: detectedPlatform,
            signupType,
            referralCode,
        });
        const response = result.data;

        if (detectedPlatform === 'android') {
            showMessage(
                msgEl,
                response.alreadyTester
                    ? '✓ You\'re already signed up!'
                    : '✓ Signup recorded! Follow the steps below to install:',
                'success'
            );
            emailInput.value = '';
            hideFormAfterSignup(formPrefix);
            showTesterSteps(msgEl);
        } else if (detectedPlatform === 'ios') {
            showMessage(msgEl, 'You\u2019re in! We\u2019ll send your TestFlight invite to ' + email + ' shortly.', 'success');
            emailInput.value = '';
            hideFormAfterSignup(formPrefix);
        } else {
            showMessage(msgEl, 'You\u2019re in! We\u2019ll notify you when the native app is ready for your platform.', 'success');
            emailInput.value = '';
            hideFormAfterSignup(formPrefix);
        }
    } catch (err) {
        console.error('Signup error:', err);
        showMessage(msgEl, 'Something went wrong. Please try again.', 'error');
    } finally {
        btn.disabled = false;
        if (btnText) btnText.textContent = originalText;
    }
}

/**
 * Hide email input + submit button after successful signup.
 * Persists state in localStorage so re-visits don't show the form again.
 */
function hideFormAfterSignup(formPrefix) {
    // Hide the form row (input + button)
    const emailInput = document.getElementById(formPrefix + '-email');
    const btn = document.getElementById(formPrefix + '-signup-btn');
    if (emailInput) emailInput.style.display = 'none';
    if (btn) btn.style.display = 'none';

    // Persist signup state
    localStorage.setItem('dn_signup_' + formPrefix, 'done');
}

function triggerAPKDownload() {
    const link = document.createElement('a');
    link.href = APK_DOWNLOAD_URL;
    link.download = 'diaspora-nearby.apk';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
}

/**
 * Shows the 2-step tester onboarding guide below the signup message.
 * Step 1: Join the Google Group (grants Play Store access)
 * Step 2: Accept the test on Google Play
 */
function showTesterSteps(msgEl) {
    if (!msgEl) return;
    // Create the steps container below the message
    let stepsContainer = document.getElementById('tester-steps');
    if (!stepsContainer) {
        stepsContainer = document.createElement('div');
        stepsContainer.id = 'tester-steps';
        stepsContainer.className = 'tester-steps';
        msgEl.parentNode.insertBefore(stepsContainer, msgEl.nextSibling);
    }

    // Check if Join Group was already clicked
    const joinGroupDone = localStorage.getItem('dn_join_group_clicked');

    stepsContainer.innerHTML = `
        ${joinGroupDone ? '' : `
        <div class="tester-step" id="tester-step-join-group">
            <span class="step-number">1</span>
            <div class="step-content">
                <strong>Join our Testers Group</strong>
                <p>This grants you Play Store access</p>
                <a href="${GOOGLE_GROUP_JOIN_URL}" target="_blank" rel="noopener" class="step-btn step-btn-primary" onclick="markJoinGroupDone()">
                    <i data-lucide="users" style="width:16px;height:16px"></i> Join Group
                </a>
            </div>
        </div>
        `}
        <div class="tester-step">
            <span class="step-number">${joinGroupDone ? '1' : '2'}</span>
            <div class="step-content">
                <strong>Accept the test on Google Play</strong>
                <p>Then install the app</p>
                <a href="${PLAY_STORE_TEST_URL}" target="_blank" rel="noopener" class="step-btn step-btn-secondary">
                    <i data-lucide="play" style="width:16px;height:16px"></i> Open Google Play
                </a>
            </div>
        </div>
    `;
    stepsContainer.style.display = 'block';
    // Re-render Lucide icons inside the new elements
    if (typeof lucide !== 'undefined') lucide.createIcons();
}

/**
 * Mark "Join Group" step as done — hides the card and persists in localStorage.
 */
function markJoinGroupDone() {
    localStorage.setItem('dn_join_group_clicked', 'done');
    // Hide the step card with a short delay so the link navigates first
    setTimeout(() => {
        const stepEl = document.getElementById('tester-step-join-group');
        if (stepEl) {
            stepEl.style.transition = 'opacity 0.3s, max-height 0.3s';
            stepEl.style.opacity = '0';
            stepEl.style.maxHeight = '0';
            stepEl.style.overflow = 'hidden';
            stepEl.style.padding = '0';
            stepEl.style.margin = '0';
            setTimeout(() => stepEl.remove(), 400);
        }
    }, 300);
}

function openPlayStoreListing() {
    window.location.href = PLAY_STORE_LISTING_URL;
}

function showMessage(el, text, type) {
    if (!el) return;
    el.textContent = text;
    el.className = 'form-message ' + type;
    // Only auto-clear non-success messages (success stays as confirmation)
    if (type !== 'success') {
        setTimeout(() => {
            el.textContent = '';
            el.className = 'form-message';
        }, 8000);
    }
}

// ── Mobile Navigation ──
const navToggle = document.getElementById('nav-toggle');
const navLinks = document.getElementById('nav-links');

if (navToggle && navLinks) {
    navToggle.addEventListener('click', () => {
        navLinks.classList.toggle('open');
    });

    // Close on link click
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
            const offset = 64; // nav height
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
