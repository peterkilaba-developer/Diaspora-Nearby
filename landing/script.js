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
    if (/Mac/.test(ua) && navigator.maxTouchPoints > 1) return 'ios'; // iPad Safari
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

    document.body.classList.add('platform-' + detectedPlatform);

    // 0. Hero Single-Platform Button Enforcement (Android vs iOS)
    const heroBtnAndroid = document.getElementById('hero-btn-android');
    const heroBtnIOS = document.getElementById('hero-btn-ios');
    if (heroBtnAndroid && heroBtnIOS) {
        if (isIOS) {
            heroBtnAndroid.style.setProperty('display', 'none', 'important');
            heroBtnIOS.style.setProperty('display', 'inline-flex', 'important');
        } else {
            heroBtnAndroid.style.setProperty('display', 'inline-flex', 'important');
            heroBtnIOS.style.setProperty('display', 'none', 'important');
        }
    }

    // 1. Dynamic Hero Platform Blocks for index.html
    const blockAndroid = document.getElementById('hero-block-android');
    const blockIOS = document.getElementById('hero-block-ios');
    const blockDefault = document.getElementById('hero-block-default');
    const pill = document.getElementById('hero-platform-pill');
    const pillIcon = document.getElementById('hero-platform-pill-icon');
    const pillText = document.getElementById('hero-platform-pill-text');

    if (blockAndroid && blockIOS && blockDefault) {
        if (isAndroid) {
            blockAndroid.style.display = 'flex';
            blockIOS.style.display = 'none';
            blockDefault.style.display = 'none';
            if (pill) {
                pill.style.display = 'inline-flex';
                if (pillIcon) pillIcon.textContent = '🤖 ';
                if (pillText) pillText.textContent = 'Android detected — Google Play & Direct APK available';
            }
        } else if (isIOS) {
            blockAndroid.style.display = 'none';
            blockIOS.style.display = 'flex';
            blockDefault.style.display = 'none';
            if (pill) {
                pill.style.display = 'inline-flex';
                if (pillIcon) pillIcon.textContent = '🍏 ';
                if (pillText) pillText.textContent = 'iOS detected — Instant Web App & TestFlight Beta';
            }
        } else {
            blockAndroid.style.display = 'none';
            blockIOS.style.display = 'none';
            blockDefault.style.display = 'flex';
            if (pill) pill.style.display = 'none';
        }
    }

    // 2. Dynamic Hero Platform Blocks for index_v2.html
    const blockAndroidV2 = document.getElementById('hero-block-android-v2');
    const blockIOSV2 = document.getElementById('hero-block-ios-v2');
    const blockDefaultV2 = document.getElementById('hero-block-default-v2');
    const pillV2 = document.getElementById('hero-platform-pill-v2');
    const pillIconV2 = document.getElementById('hero-platform-pill-icon-v2');
    const pillTextV2 = document.getElementById('hero-platform-pill-text-v2');

    if (blockAndroidV2 && blockIOSV2 && blockDefaultV2) {
        if (isAndroid) {
            blockAndroidV2.style.display = 'flex';
            blockIOSV2.style.display = 'none';
            blockDefaultV2.style.display = 'none';
            if (pillV2) {
                pillV2.style.display = 'inline-flex';
                if (pillIconV2) pillIconV2.textContent = '🤖 ';
                if (pillTextV2) pillTextV2.textContent = 'Android detected — Google Play & Direct APK available';
            }
        } else if (isIOS) {
            blockAndroidV2.style.display = 'none';
            blockIOSV2.style.display = 'flex';
            blockDefaultV2.style.display = 'none';
            if (pillV2) {
                pillV2.style.display = 'inline-flex';
                if (pillIconV2) pillIconV2.textContent = '🍏 ';
                if (pillTextV2) pillTextV2.textContent = 'iOS detected — Instant Web App & TestFlight Beta';
            }
        } else {
            blockAndroidV2.style.display = 'none';
            blockIOSV2.style.display = 'none';
            blockDefaultV2.style.display = 'flex';
            if (pillV2) pillV2.style.display = 'none';
        }
    }

    // 3. Install section platform detection
    const installDetectedText = document.getElementById('install-detected-text');
    const androidOpt = document.getElementById('install-android-opt');
    const iosOpt = document.getElementById('install-ios-opt');

    if (installDetectedText) {
        if (isAndroid) {
            installDetectedText.textContent = 'Android detected — install directly from Google Play or download APK';
        } else if (isIOS) {
            installDetectedText.textContent = 'iOS detected — launch Web App or request TestFlight invite';
        } else {
            installDetectedText.textContent = 'Google Play (Android), Web App (iOS/Desktop), or Direct APK';
        }
    }

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

    // Refresh icons inside dynamic blocks
    if (typeof lucide !== 'undefined') {
        lucide.createIcons();
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

// ── PSA Rewards Directory Category Filter ──
document.addEventListener('DOMContentLoaded', () => {
    const filterPills = document.querySelectorAll('#reward-filter-pills .pill');
    const rewardItems = document.querySelectorAll('.rewards-grid .reward-item[data-category]');

    if (filterPills.length > 0 && rewardItems.length > 0) {
        filterPills.forEach((pill) => {
            pill.addEventListener('click', () => {
                filterPills.forEach((p) => p.classList.remove('active'));
                pill.classList.add('active');
                const cat = pill.getAttribute('data-filter');

                rewardItems.forEach((item) => {
                    const itemCat = item.getAttribute('data-category');
                    if (cat === 'all' || itemCat === cat) {
                        item.classList.remove('cat-hidden');
                    } else {
                        item.classList.add('cat-hidden');
                    }
                });
            });
        });
    }

    // ── Interactive Earnings & Trust Calculator ──
    const sliderConn = document.getElementById('slider-connections');
    const sliderTrust = document.getElementById('slider-trust');
    const sliderSpend = document.getElementById('slider-spend');

    const valConn = document.getElementById('val-connections');
    const valTrust = document.getElementById('val-trust');
    const valSpend = document.getElementById('val-spend');

    const resDsp = document.getElementById('res-dsp');
    const resDiaspora = document.getElementById('res-diaspora');
    const resMatch = document.getElementById('res-match');
    const resPct = document.getElementById('res-pct');

    function updateEarningsCalculator() {
        if (!sliderConn || !sliderTrust || !sliderSpend) return;

        const connections = parseInt(sliderConn.value, 10) || 0;
        const trustInteractions = parseInt(sliderTrust.value, 10) || 0;
        const spend = parseInt(sliderSpend.value, 10) || 0;

        if (valConn) valConn.textContent = connections + (connections === 1 ? ' member' : ' members');
        if (valTrust) valTrust.textContent = trustInteractions + (trustInteractions === 1 ? ' interaction' : ' interactions');
        if (valSpend) valSpend.textContent = '$' + spend.toLocaleString('en-US');

        // Calculation Model:
        // Base Genesis PoH = up to 70,000 DSP (prorated 7k per verified connection)
        let baseDSP = Math.min(connections * 7000, 70000);
        if (connections > 10) {
            baseDSP += (connections - 10) * 1000;
        }
        const trustDSP = trustInteractions * 1000;
        const spendDSP = spend * 1;
        const totalDSP = baseDSP + trustDSP + spendDSP;

        // On-chain $DIASPORA unlocked: 7,000 minted on Base when 10 connections complete
        const tokensMinted = connections >= 10 ? 7000 : Math.round(connections * 700);

        // Projected PCT Score
        let pctScore = Math.min(connections * 7, 70) + Math.floor(trustInteractions / 2) + (spend > 0 ? 5 : 0);
        pctScore = Math.min(Math.max(pctScore, 5), 100);

        if (resDsp) resDsp.textContent = totalDSP.toLocaleString('en-US') + ' DSP';
        if (resDiaspora) resDiaspora.textContent = tokensMinted.toLocaleString('en-US') + ' $DIASPORA';
        if (resMatch) resMatch.textContent = totalDSP.toLocaleString('en-US') + ' DSP';
        if (resPct) resPct.textContent = pctScore + ' PCT';
    }

    if (sliderConn && sliderTrust && sliderSpend) {
        sliderConn.addEventListener('input', updateEarningsCalculator);
        sliderTrust.addEventListener('input', updateEarningsCalculator);
        sliderSpend.addEventListener('input', updateEarningsCalculator);
        updateEarningsCalculator();
    }
});
