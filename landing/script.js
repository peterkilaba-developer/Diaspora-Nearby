/* ═══════════════════════════════════════════════════════
   DIASPORA NEARBY — LANDING PAGE SCRIPTS
   Lucide, platform detection, early access signup, nav, animations
   ═══════════════════════════════════════════════════════ */

// ── Download URLs ──
// Deep link & listing for Google Play Store
const PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=com.diasporanearby.diasporanearby';
const PLAY_STORE_TEST_URL = PLAY_STORE_URL;
const PLAY_STORE_LISTING_URL = PLAY_STORE_URL;
// Apple TestFlight Invite URL
const TESTFLIGHT_URL = 'https://testflight.apple.com/join/vB3XzPKg';
const TESTFLIGHT_DEEPLINK_URL = 'itms-beta://testflight.apple.com/join/vB3XzPKg';
const TESTFLIGHT_APP_STORE_URL = 'https://apps.apple.com/us/app/testflight/id899247664';
// Google Group join page (kept for testing reference)
const GOOGLE_GROUP_JOIN_URL = 'https://groups.google.com/g/diaspora-nearby-testers';

// ── Platform Detection ──
function detectPlatform() {
    const ua = navigator.userAgent || '';
    if (/android/i.test(ua)) return 'android';
    if (/iPad|iPhone|iPod/.test(ua) && !window.MSStream) return 'ios';
    if (/Mac/.test(ua) && navigator.maxTouchPoints > 1) return 'ios'; // iPad Safari with desktop UA
    if (/Mac/.test(ua)) return 'macos';
    if (/Win/.test(ua)) return 'windows';
    if (/Linux/.test(ua)) return 'linux';
    return 'unknown';
}

const detectedPlatform = detectPlatform();

// ── Route Handling (/invite, /download, /profile) ──
(function handleRoutes() {
    const rawPath = window.location.pathname.replace(/\/+$/, '') || '/';
    const params = new URLSearchParams(window.location.search);
    const code = params.get('code') || params.get('ref');

    if (code) {
        try {
            localStorage.setItem('dn_referral_code', code);
        } catch (e) {}
    }

    // /invite or /download: redirect mobile users directly to their phone platform store
    if (rawPath === '/invite' || rawPath === '/download') {
        const platform = detectedPlatform;

        if (platform === 'ios') {
            renderRedirectScreen('ios', TESTFLIGHT_URL);
            // Do NOT call window.location.href/replace on iOS: iOS blocks Universal Links
            // on script-initiated navigations, and itms-beta:// opens TestFlight to the Redeem Code screen.
            // A direct user tap on the <a href="https://testflight.apple.com/join/vB3XzPKg"> button
            // triggers the iOS Universal Link into Diaspora Nearby's Accept/Install sheet.
            return;
        } else if (platform === 'android') {
            let androidUrl = PLAY_STORE_URL;
            if (code) {
                androidUrl += '&referrer=' + encodeURIComponent('utm_source=invite&referral_code=' + code);
            }
            renderRedirectScreen('android', androidUrl);
            window.location.replace(androidUrl);
            return;
        } else {
            // Desktop / Mac / PC: show landing page, scroll to #get-app
            document.addEventListener('DOMContentLoaded', () => {
                const getAppSection = document.getElementById('get-app');
                if (getAppSection) {
                    setTimeout(() => {
                        const offset = 64;
                        const y = getAppSection.getBoundingClientRect().top + window.pageYOffset - offset;
                        window.scrollTo({ top: y, behavior: 'smooth' });
                    }, 300);
                }

                if (code) {
                    showInviteToast(code);
                }
            });
        }
    }

    // /profile/{uid} — redirect to mobile app download
    if (rawPath.startsWith('/profile/')) {
        window.location.replace('/#get-app');
        return;
    }
})();

// ── Fallback UI for mobile in-app browsers ──
function renderRedirectScreen(platform, targetUrl) {
    const isIOS = platform === 'ios';
    const storeName = isIOS ? 'Apple TestFlight' : 'Google Play Store';
    const btnLabel = isIOS ? 'Open in TestFlight' : 'Open in Google Play';

    const inject = () => {
        if (document.getElementById('platform-redirect-overlay')) return;
        const overlay = document.createElement('div');
        overlay.id = 'platform-redirect-overlay';
        overlay.className = 'redirect-overlay';
        overlay.innerHTML = `
            <div class="redirect-card">
                <img src="icons/Icon-192.png" alt="Diaspora Nearby" class="redirect-app-icon" onerror="this.src='favicon.png'">
                ${isIOS ? '' : '<div class="redirect-spinner"></div>'}
                <h2>${isIOS ? 'Join Diaspora Nearby on iOS' : 'Opening Diaspora Nearby...'}</h2>
                <p>${isIOS ? 'Tap below to open the beta directly in <strong>Apple TestFlight</strong> (no invite code needed).' : `Redirecting you to <strong>${storeName}</strong> to download the app.`}</p>
                <a href="${targetUrl}" class="btn-primary-redirect" id="redirect-now-btn">
                    <span>${btnLabel}</span>
                    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"></path><polyline points="15 3 21 3 21 9"></polyline><line x1="10" y1="14" x2="21" y2="3"></line></svg></a>${isIOS ? `<div style="margin-top: 16px; padding: 14px; border-radius: 12px; background: var(--surface-hover, rgba(128,128,128,0.08)); border: none; font-size: 13px; color: var(--fg-muted); text-align: left; line-height: 1.55; width: 100%;"><strong style="color: var(--fg); display: block; margin-bottom: 6px;">First time using TestFlight?</strong>1. <a href="${TESTFLIGHT_APP_STORE_URL}" target="_blank" rel="noopener" style="color: var(--sage); font-weight: 600; text-decoration: underline;">Install Apple TestFlight</a> from the App Store first.<br>2. <strong>Come back to this page</strong> and tap <strong>Open in TestFlight</strong> above (do <em>not</em> open TestFlight from the App Store or tap "Redeem"—no invite code is needed).<br><span style="display:block; margin-top:6px; font-size:12px; opacity:0.85;">💡 If you opened this inside WhatsApp/Instagram and it asks for a code, tap the browser icon in the corner to <strong>Open in Safari</strong>.</span></div>` : ''}<a style="display:none">
                </a>
                <div style="margin-top: 18px;">
                    <button type="button" class="redirect-cancel-link" onclick="dismissRedirectOverlay(event)">
                        Or view full website
                    </button>
                </div>
            </div>
        `;
        document.body.prepend(overlay);
        if (typeof lucide !== 'undefined') lucide.createIcons();
    };

    if (document.body) {
        inject();
    } else {
        document.addEventListener('DOMContentLoaded', inject);
    }
}

function dismissRedirectOverlay(e) {
    if (e) e.preventDefault();
    const overlay = document.getElementById('platform-redirect-overlay');
    if (overlay) overlay.remove();
}

function showInviteToast(code) {
    const toast = document.createElement('div');
    toast.className = 'invite-toast';
    toast.innerHTML = `
        <span style="font-size: 20px;">🎉</span>
        <div style="text-align: left;">
            <div style="font-size: 13px; font-weight: 700; color: var(--fg);">You were invited to Diaspora Nearby!</div>
            <div style="font-size: 12px; color: var(--fg-muted);">Referral code <code>${code}</code> saved for signup.</div>
        </div>
        <button type="button" style="background:none;border:none;color:var(--fg-muted);cursor:pointer;padding:4px;margin-left:8px;font-size:16px;" onclick="this.parentElement.remove()">✕</button>
    `;
    document.body.appendChild(toast);
    setTimeout(() => {
        if (toast.parentElement) toast.remove();
    }, 8000);
}

// ── Lucide Icons ──
document.addEventListener('DOMContentLoaded', () => {
    if (typeof lucide !== 'undefined') {
        lucide.createIcons();
    }
});

// ── Update UI based on platform ──
function initPlatformUI() {
    const isAndroid = detectedPlatform === 'android';
    const isIOS = detectedPlatform === 'ios';

    document.body.classList.add('platform-' + detectedPlatform);

    // 0. Hero Platform Button Enforcement
    const heroBtnAndroid = document.getElementById('hero-btn-android');
    const heroBtnIOS = document.getElementById('hero-btn-ios');
    if (heroBtnAndroid && heroBtnIOS) {
        if (isIOS) {
            heroBtnAndroid.style.setProperty('display', 'none', 'important');
            heroBtnIOS.style.setProperty('display', 'inline-flex', 'important');
        } else if (isAndroid) {
            heroBtnAndroid.style.setProperty('display', 'inline-flex', 'important');
            heroBtnIOS.style.setProperty('display', 'none', 'important');
        } else {
            // Desktop / Mac: show both platform buttons
            heroBtnAndroid.style.setProperty('display', 'inline-flex', 'important');
            heroBtnIOS.style.setProperty('display', 'inline-flex', 'important');
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
                if (pillText) pillText.textContent = 'Android detected — Google Play available';
            }
        } else if (isIOS) {
            blockAndroid.style.display = 'none';
            blockIOS.style.display = 'flex';
            blockDefault.style.display = 'none';
            if (pill) {
                pill.style.display = 'inline-flex';
                if (pillIcon) pillIcon.textContent = '🍏 ';
                if (pillText) pillText.textContent = 'iOS detected — TestFlight Beta';
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
                if (pillTextV2) pillTextV2.textContent = 'Android detected — Google Play available';
            }
        } else if (isIOS) {
            blockAndroidV2.style.display = 'none';
            blockIOSV2.style.display = 'flex';
            blockDefaultV2.style.display = 'none';
            if (pillV2) {
                pillV2.style.display = 'inline-flex';
                if (pillIconV2) pillIconV2.textContent = '🍏 ';
                if (pillTextV2) pillTextV2.textContent = 'iOS detected — TestFlight Beta';
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
            installDetectedText.textContent = 'Android detected — install directly from Google Play';
        } else if (isIOS) {
            installDetectedText.textContent = 'iOS detected — request TestFlight invite';
        } else {
            installDetectedText.textContent = 'Google Play (Android) or TestFlight (iOS)';
        }
    }

    if (isAndroid && androidOpt) {
        androidOpt.classList.add('active');
    } else if (isIOS && iosOpt) {
        iosOpt.classList.add('active');
    }

    // Show Play Store and APK fallback buttons for Android, TestFlight for iOS, both for Desktop/Mac
    const playStoreDirect = document.getElementById('play-store-direct');
    const apkFallback = document.getElementById('apk-fallback');
    const installSignupBtn = document.getElementById('install-signup-btn');
    const installIOSBtn = document.getElementById('install-ios-btn');
    const getAppSubtitle = document.getElementById('get-app-subtitle');

    if (isIOS) {
        if (installSignupBtn) installSignupBtn.style.setProperty('display', 'none', 'important');
        if (installIOSBtn) installIOSBtn.style.setProperty('display', 'inline-flex', 'important');
        if (playStoreDirect) playStoreDirect.style.display = 'none';
        if (apkFallback) apkFallback.style.display = 'none';
        if (getAppSubtitle) getAppSubtitle.textContent = 'Join the iOS TestFlight Beta.';
    } else if (isAndroid) {
        if (installIOSBtn) installIOSBtn.style.setProperty('display', 'none', 'important');
        if (installSignupBtn) installSignupBtn.style.setProperty('display', 'inline-flex', 'important');
        if (playStoreDirect) playStoreDirect.style.display = 'block';
        if (apkFallback) apkFallback.style.display = 'none';
        if (getAppSubtitle) getAppSubtitle.textContent = 'Install the native Android app from Google Play.';
    } else {
        // Desktop / Mac: show both links
        if (installSignupBtn) installSignupBtn.style.setProperty('display', 'inline-flex', 'important');
        if (installIOSBtn) installIOSBtn.style.setProperty('display', 'inline-flex', 'important');
        if (playStoreDirect) playStoreDirect.style.display = 'none';
        if (apkFallback) apkFallback.style.display = 'none';
        if (getAppSubtitle) getAppSubtitle.textContent = 'Install on Android (Google Play) or join the iOS TestFlight Beta.';
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
            showMessage(msgEl, 'You\u2019re in! Opening TestFlight now (no invite code required)...', 'success');
            // Do NOT call window.location.href/replace on iOS: iOS blocks Universal Links
            // on script-initiated navigations, and itms-beta:// opens TestFlight to the Redeem Code screen.
            // A direct user tap on the <a href="https://testflight.apple.com/join/vB3XzPKg"> button
            // triggers the iOS Universal Link into Diaspora Nearby's Accept/Install sheet.
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

/**
 * Shows the install options below the signup message.
 * Option 1: Install from Google Play
 * Option 2: Direct APK Download
 */
function showTesterSteps(msgEl) {
    if (!msgEl) return;
    let stepsContainer = document.getElementById('tester-steps');
    if (!stepsContainer) {
        stepsContainer = document.createElement('div');
        stepsContainer.id = 'tester-steps';
        stepsContainer.className = 'tester-steps';
        msgEl.parentNode.insertBefore(stepsContainer, msgEl.nextSibling);
    }

    stepsContainer.innerHTML = `
        <div class="tester-step">
            <span class="step-number">1</span>
            <div class="step-content">
                <strong>Install from Google Play</strong>
                <p>Download directly to your Android device</p>
                <a href="${PLAY_STORE_LISTING_URL}" target="_blank" rel="noopener" class="step-btn step-btn-primary">
                    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="5 3 19 12 5 21 5 3"></polygon></svg> Open Google Play
                </a>
            </div>
        </div>
    `;
    stepsContainer.style.display = 'block';
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

// ── Hamburger Navigation ──
const navToggle = document.getElementById('nav-toggle');
const navLinks = document.getElementById('nav-links');

if (navToggle && navLinks) {
    navToggle.addEventListener('click', (e) => {
        e.stopPropagation();
        const isOpen = navLinks.classList.toggle('open');
        navToggle.classList.toggle('open', isOpen);
        navToggle.setAttribute('aria-expanded', isOpen);
        navToggle.innerHTML = isOpen ? '<i data-lucide="x"></i>' : '<i data-lucide="menu"></i>';
        if (typeof lucide !== 'undefined') lucide.createIcons();
    });

    // Close on link click
    navLinks.querySelectorAll('a').forEach((link) => {
        link.addEventListener('click', () => {
            navLinks.classList.remove('open');
            navToggle.classList.remove('open');
            navToggle.setAttribute('aria-expanded', 'false');
            navToggle.innerHTML = '<i data-lucide="menu"></i>';
            if (typeof lucide !== 'undefined') lucide.createIcons();
        });
    });

    // Close when clicking outside
    document.addEventListener('click', (e) => {
        if (!navToggle.contains(e.target) && !navLinks.contains(e.target) && navLinks.classList.contains('open')) {
            navLinks.classList.remove('open');
            navToggle.classList.remove('open');
            navToggle.setAttribute('aria-expanded', 'false');
            navToggle.innerHTML = '<i data-lucide="menu"></i>';
            if (typeof lucide !== 'undefined') lucide.createIcons();
        }
    });

    // Close on Escape key
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && navLinks.classList.contains('open')) {
            navLinks.classList.remove('open');
            navToggle.classList.remove('open');
            navToggle.setAttribute('aria-expanded', 'false');
            navToggle.innerHTML = '<i data-lucide="menu"></i>';
            if (typeof lucide !== 'undefined') lucide.createIcons();
        }
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

// ── System Theme Mode & Theme Toggle ──
(function initTheme() {
    const THEME_KEY = 'dn_theme_mode'; // 'system' | 'light' | 'dark'
    const mediaQuery = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;

    function getSavedMode() {
        try {
            return localStorage.getItem(THEME_KEY) || 'system';
        } catch (e) {
            return 'system';
        }
    }

    function applyTheme(mode) {
        const prefersDark = mediaQuery ? mediaQuery.matches : false;
        const resolvedTheme = mode === 'system' ? (prefersDark ? 'dark' : 'light') : mode;

        document.documentElement.setAttribute('data-theme', resolvedTheme);
        document.documentElement.setAttribute('data-theme-mode', mode);
        document.documentElement.style.colorScheme = resolvedTheme;

        const toggleBtns = document.querySelectorAll('.theme-toggle');
        toggleBtns.forEach(btn => {
            if (mode === 'system') {
                btn.setAttribute('title', `Theme: System (${resolvedTheme}) — click for Light`);
                btn.setAttribute('aria-label', `Theme: System (${resolvedTheme}) — click for Light`);
            } else if (mode === 'light') {
                btn.setAttribute('title', 'Theme: Light — click for Dark');
                btn.setAttribute('aria-label', 'Theme: Light — click for Dark');
            } else {
                btn.setAttribute('title', 'Theme: Dark — click for System (Auto)');
                btn.setAttribute('aria-label', 'Theme: Dark — click for System (Auto)');
            }
        });
    }

    // OS / System listener for dynamic changes in real time
    if (mediaQuery) {
        const listener = () => {
            if (getSavedMode() === 'system') {
                applyTheme('system');
            }
        };
        if (mediaQuery.addEventListener) {
            mediaQuery.addEventListener('change', listener);
        } else if (mediaQuery.addListener) {
            mediaQuery.addListener(listener);
        }
    }

    function setupButtons() {
        const toggleBtns = document.querySelectorAll('.theme-toggle');
        toggleBtns.forEach(btn => {
            if (btn.dataset.themeBound) return;
            btn.dataset.themeBound = 'true';
            btn.addEventListener('click', (e) => {
                e.preventDefault();
                const currentMode = getSavedMode();
                let nextMode;
                if (currentMode === 'system') {
                    nextMode = 'light';
                } else if (currentMode === 'light') {
                    nextMode = 'dark';
                } else {
                    nextMode = 'system';
                }

                try {
                    localStorage.setItem(THEME_KEY, nextMode);
                } catch (err) {}

                applyTheme(nextMode);

                if (typeof lucide !== 'undefined') {
                    lucide.createIcons();
                }
            });
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => {
            applyTheme(getSavedMode());
            setupButtons();
        });
    } else {
        applyTheme(getSavedMode());
        setupButtons();
    }
})();

/* ═══════════════════════════════════════════════════════════════════════════
   WORLD OFFICIAL LANGUAGES & COUNTRIES SELECTOR (ALL COUNTRIES)
   ═══════════════════════════════════════════════════════════════════════════ */
(function initWorldLanguageSelector() {
    const LANG_STORAGE_KEY = 'dn_lang';

    const WORLD_LANGUAGES = [
        { code: 'en', name: 'English', nativeName: 'English', flag: '🇬🇧', rtl: false },
        { code: 'sw', name: 'Swahili', nativeName: 'Kiswahili', flag: '🇹🇿', rtl: false },
        { code: 'fr', name: 'French', nativeName: 'Français', flag: '🇫🇷', rtl: false },
        { code: 'ar', name: 'Arabic', nativeName: 'العربية', flag: '🇸🇦', rtl: true },
        { code: 'es', name: 'Spanish', nativeName: 'Español', flag: '🇪🇸', rtl: false },
        { code: 'pt', name: 'Portuguese', nativeName: 'Português', flag: '🇵🇹', rtl: false },
        { code: 'zh-CN', name: 'Chinese (Mandarin)', nativeName: '中文 (简体)', flag: '🇨🇳', rtl: false },
        { code: 'zh-TW', name: 'Chinese (Traditional)', nativeName: '繁體中文', flag: '🇹🇼', rtl: false },
        { code: 'hi', name: 'Hindi', nativeName: 'हिन्दी', flag: '🇮🇳', rtl: false },
        { code: 'ru', name: 'Russian', nativeName: 'Русский', flag: '🇷🇺', rtl: false },
        { code: 'de', name: 'German', nativeName: 'Deutsch', flag: '🇩🇪', rtl: false },
        { code: 'nl', name: 'Dutch', nativeName: 'Nederlands', flag: '🇳🇱', rtl: false },
        { code: 'am', name: 'Amharic', nativeName: 'አማርኛ', flag: '🇪🇹', rtl: false },
        { code: 'om', name: 'Oromo', nativeName: 'Afaan Oromoo', flag: '🇪🇹', rtl: false },
        { code: 'ti', name: 'Tigrinya', nativeName: 'ትግርኛ', flag: '🇪🇷', rtl: false },
        { code: 'so', name: 'Somali', nativeName: 'Soomaali', flag: '🇸🇴', rtl: false },
        { code: 'ha', name: 'Hausa', nativeName: 'Harshen Hausa', flag: '🇳🇬', rtl: false },
        { code: 'yo', name: 'Yoruba', nativeName: 'Èdè Yorùbá', flag: '🇳🇬', rtl: false },
        { code: 'ig', name: 'Igbo', nativeName: 'Asụsụ Igbo', flag: '🇳🇬', rtl: false },
        { code: 'rw', name: 'Kinyarwanda', nativeName: 'Ikinyarwanda', flag: '🇷🇼', rtl: false },
        { code: 'rn', name: 'Kirundi', nativeName: 'Ikirundi', flag: '🇧🇮', rtl: false },
        { code: 'ln', name: 'Lingala', nativeName: 'Lingála', flag: '🇨🇩', rtl: false },
        { code: 'kg', name: 'Kikongo', nativeName: 'Kikongo', flag: '🇨🇬', rtl: false },
        { code: 'mg', name: 'Malagasy', nativeName: 'Malagasy', flag: '🇲🇬', rtl: false },
        { code: 'sn', name: 'Shona', nativeName: 'ChiShona', flag: '🇿🇼', rtl: false },
        { code: 'ny', name: 'Chichewa', nativeName: 'Chichewa', flag: '🇲🇼', rtl: false },
        { code: 'zu', name: 'Zulu', nativeName: 'isiZulu', flag: '🇿🇦', rtl: false },
        { code: 'xh', name: 'Xhosa', nativeName: 'isiXhosa', flag: '🇿🇦', rtl: false },
        { code: 'af', name: 'Afrikaans', nativeName: 'Afrikaans', flag: '🇿🇦', rtl: false },
        { code: 'st', name: 'Sesotho', nativeName: 'Sesotho', flag: '🇱🇸', rtl: false },
        { code: 'tn', name: 'Setswana', nativeName: 'Setswana', flag: '🇧🇼', rtl: false },
        { code: 'ss', name: 'Siswati', nativeName: 'SiSwati', flag: '🇸🇿', rtl: false },
        { code: 'ak', name: 'Akan (Twi)', nativeName: 'Akan / Twi', flag: '🇬🇭', rtl: false },
        { code: 'ee', name: 'Ewe', nativeName: 'Eʋegbe', flag: '🇹🇬', rtl: false },
        { code: 'wo', name: 'Wolof', nativeName: 'Wolof', flag: '🇸🇳', rtl: false },
        { code: 'bm', name: 'Bambara', nativeName: 'Bamanankan', flag: '🇲🇱', rtl: false },
        { code: 'ff', name: 'Fula (Fulani)', nativeName: 'Fulfulde / Pulaar', flag: '🇬🇳', rtl: false },
        { code: 'lg', name: 'Luganda', nativeName: 'Oluganda', flag: '🇺🇬', rtl: false },
        { code: 'bn', name: 'Bengali', nativeName: 'বাংলা', flag: '🇧🇩', rtl: false },
        { code: 'ur', name: 'Urdu', nativeName: 'اردو', flag: '🇵🇰', rtl: true },
        { code: 'pa', name: 'Punjabi', nativeName: 'ਪੰਜਾਬੀ', flag: '🇮🇳', rtl: false },
        { code: 'ta', name: 'Tamil', nativeName: 'தமிழ்', flag: '🇱🇰', rtl: false },
        { code: 'te', name: 'Telugu', nativeName: 'తెలుగు', flag: '🇮🇳', rtl: false },
        { code: 'mr', name: 'Marathi', nativeName: 'मराठी', flag: '🇮🇳', rtl: false },
        { code: 'gu', name: 'Gujarati', nativeName: 'ગુજરાતી', flag: '🇮🇳', rtl: false },
        { code: 'kn', name: 'Kannada', nativeName: 'ಕನ್ನಡ', flag: '🇮🇳', rtl: false },
        { code: 'ml', name: 'Malayalam', nativeName: 'മലയാളം', flag: '🇮🇳', rtl: false },
        { code: 'si', name: 'Sinhala', nativeName: 'සිංහල', flag: '🇱🇰', rtl: false },
        { code: 'ne', name: 'Nepali', nativeName: 'नेपाली', flag: '🇳🇵', rtl: false },
        { code: 'dz', name: 'Dzongkha', nativeName: 'རྫོང་ཁ', flag: '🇧🇹', rtl: false },
        { code: 'dv', name: 'Divehi', nativeName: 'ދިވެހި', flag: '🇲🇻', rtl: true },
        { code: 'fa', name: 'Persian (Farsi / Dari)', nativeName: 'فارسی', flag: '🇮🇷', rtl: true },
        { code: 'ps', name: 'Pashto', nativeName: 'پښتو', flag: '🇦🇫', rtl: true },
        { code: 'tg', name: 'Tajik', nativeName: 'Тоҷикӣ', flag: '🇹🇯', rtl: false },
        { code: 'uz', name: 'Uzbek', nativeName: 'Oʻzbekcha', flag: '🇺🇿', rtl: false },
        { code: 'kk', name: 'Kazakh', nativeName: 'Қазақ тілі', flag: '🇰🇿', rtl: false },
        { code: 'ky', name: 'Kyrgyz', nativeName: 'Кыргызча', flag: '🇰🇬', rtl: false },
        { code: 'tk', name: 'Turkmen', nativeName: 'Türkmençe', flag: '🇹🇲', rtl: false },
        { code: 'mn', name: 'Mongolian', nativeName: 'Монгол хэл', flag: '🇲🇳', rtl: false },
        { code: 'tr', name: 'Turkish', nativeName: 'Türkçe', flag: '🇹🇷', rtl: false },
        { code: 'az', name: 'Azerbaijani', nativeName: 'Azərbaycan dili', flag: '🇦🇿', rtl: false },
        { code: 'ka', name: 'Georgian', nativeName: 'ქართული', flag: '🇬🇪', rtl: false },
        { code: 'hy', name: 'Armenian', nativeName: 'Հայերեն', flag: '🇦🇲', rtl: false },
        { code: 'iw', name: 'Hebrew', nativeName: 'עברית', flag: '🇮🇱', rtl: true },
        { code: 'ku', name: 'Kurdish', nativeName: 'Kurdî / کوردی', flag: '🇮🇶', rtl: false },
        { code: 'my', name: 'Burmese', nativeName: 'မြန်မာဘာသာ', flag: '🇲🇲', rtl: false },
        { code: 'th', name: 'Thai', nativeName: 'ภาษาไทย', flag: '🇹🇭', rtl: false },
        { code: 'lo', name: 'Lao', nativeName: 'ພາສາລາວ', flag: '🇱🇦', rtl: false },
        { code: 'km', name: 'Khmer', nativeName: 'ភាសាខ្មែរ', flag: '🇰🇭', rtl: false },
        { code: 'vi', name: 'Vietnamese', nativeName: 'Tiếng Việt', flag: '🇻🇳', rtl: false },
        { code: 'ms', name: 'Malay', nativeName: 'Bahasa Melayu', flag: '🇲🇾', rtl: false },
        { code: 'id', name: 'Indonesian', nativeName: 'Bahasa Indonesia', flag: '🇮🇩', rtl: false },
        { code: 'tl', name: 'Filipino (Tagalog)', nativeName: 'Filipino / Tagalog', flag: '🇵🇭', rtl: false },
        { code: 'tet', name: 'Tetum', nativeName: 'Tetun', flag: '🇹🇱', rtl: false },
        { code: 'ja', name: 'Japanese', nativeName: '日本語', flag: '🇯🇵', rtl: false },
        { code: 'ko', name: 'Korean', nativeName: '한국어', flag: '🇰🇷', rtl: false },
        { code: 'it', name: 'Italian', nativeName: 'Italiano', flag: '🇮🇹', rtl: false },
        { code: 'pl', name: 'Polish', nativeName: 'Polski', flag: '🇵🇱', rtl: false },
        { code: 'uk', name: 'Ukrainian', nativeName: 'Українська', flag: '🇺🇦', rtl: false },
        { code: 'be', name: 'Belarusian', nativeName: 'Беларуская', flag: '🇧🇾', rtl: false },
        { code: 'ro', name: 'Romanian', nativeName: 'Română', flag: '🇷🇴', rtl: false },
        { code: 'el', name: 'Greek', nativeName: 'Ελληνικά', flag: '🇬🇷', rtl: false },
        { code: 'cs', name: 'Czech', nativeName: 'Čeština', flag: '🇨🇿', rtl: false },
        { code: 'sk', name: 'Slovak', nativeName: 'Slovenčina', flag: '🇸🇰', rtl: false },
        { code: 'hu', name: 'Hungarian', nativeName: 'Magyar', flag: '🇭🇺', rtl: false },
        { code: 'bg', name: 'Bulgarian', nativeName: 'Български', flag: '🇧🇬', rtl: false },
        { code: 'sr', name: 'Serbian', nativeName: 'Српски / Srpski', flag: '🇷🇸', rtl: false },
        { code: 'hr', name: 'Croatian', nativeName: 'Hrvatski', flag: '🇭🇷', rtl: false },
        { code: 'bs', name: 'Bosnian', nativeName: 'Bosanski', flag: '🇧🇦', rtl: false },
        { code: 'sl', name: 'Slovenian', nativeName: 'Slovenščina', flag: '🇸🇮', rtl: false },
        { code: 'mk', name: 'Macedonian', nativeName: 'Македонски', flag: '🇲🇰', rtl: false },
        { code: 'sq', name: 'Albanian', nativeName: 'Shqip', flag: '🇦🇱', rtl: false },
        { code: 'sv', name: 'Swedish', nativeName: 'Svenska', flag: '🇸🇪', rtl: false },
        { code: 'no', name: 'Norwegian', nativeName: 'Norsk', flag: '🇳🇴', rtl: false },
        { code: 'da', name: 'Danish', nativeName: 'Dansk', flag: '🇩🇰', rtl: false },
        { code: 'fi', name: 'Finnish', nativeName: 'Suomi', flag: '🇫🇮', rtl: false },
        { code: 'is', name: 'Icelandic', nativeName: 'Íslenska', flag: '🇮🇸', rtl: false },
        { code: 'et', name: 'Estonian', nativeName: 'Eesti', flag: '🇪🇪', rtl: false },
        { code: 'lv', name: 'Latvian', nativeName: 'Latviešu', flag: '🇱🇻', rtl: false },
        { code: 'lt', name: 'Lithuanian', nativeName: 'Lietuvių', flag: '🇱🇹', rtl: false },
        { code: 'ga', name: 'Irish', nativeName: 'Gaeilge', flag: '🇮🇪', rtl: false },
        { code: 'cy', name: 'Welsh', nativeName: 'Cymraeg', flag: '🏴󠁧󠁢󠁷󠁬󠁳󠁿', rtl: false },
        { code: 'gd', name: 'Scottish Gaelic', nativeName: 'Gàidhlig', flag: '🏴󠁧󠁢󠁳󠁣󠁴󠁿', rtl: false },
        { code: 'mt', name: 'Maltese', nativeName: 'Malti', flag: '🇲🇹', rtl: false },
        { code: 'lb', name: 'Luxembourgish', nativeName: 'Lëtzebuergesch', flag: '🇱🇺', rtl: false },
        { code: 'ca', name: 'Catalan', nativeName: 'Català', flag: '🇦🇩', rtl: false },
        { code: 'ht', name: 'Haitian Creole', nativeName: 'Kreyòl Ayisyen', flag: '🇭🇹', rtl: false },
        { code: 'qu', name: 'Quechua', nativeName: 'Runasimi', flag: '🇵🇪', rtl: false },
        { code: 'gn', name: 'Guarani', nativeName: 'Avañe\'ẽ', flag: '🇵🇾', rtl: false },
        { code: 'ay', name: 'Aymara', nativeName: 'Aymar aru', flag: '🇧🇴', rtl: false },
        { code: 'mi', name: 'Māori', nativeName: 'Te Reo Māori', flag: '🇳🇿', rtl: false },
        { code: 'sm', name: 'Samoan', nativeName: 'Gagana Faʻa Sāmoa', flag: '🇼🇸', rtl: false },
        { code: 'fj', name: 'Fijian', nativeName: 'Vosa Vakaviti', flag: '🇫🇯', rtl: false },
        { code: 'to', name: 'Tongan', nativeName: 'Lea Fakatonga', flag: '🇹🇴', rtl: false }
    ];

    const WORLD_COUNTRIES = [
        { code: 'AF', name: 'Afghanistan', flag: '🇦🇫', continent: 'Asia', langs: ['ps', 'fa'] },
        { code: 'AL', name: 'Albania', flag: '🇦🇱', continent: 'Europe', langs: ['sq'] },
        { code: 'DZ', name: 'Algeria', flag: '🇩🇿', continent: 'Africa', langs: ['ar', 'fr'] },
        { code: 'AD', name: 'Andorra', flag: '🇦🇩', continent: 'Europe', langs: ['ca', 'es', 'fr'] },
        { code: 'AO', name: 'Angola', flag: '🇦🇴', continent: 'Africa', langs: ['pt', 'kg'] },
        { code: 'AG', name: 'Antigua and Barbuda', flag: '🇦🇬', continent: 'Caribbean', langs: ['en'] },
        { code: 'AR', name: 'Argentina', flag: '🇦🇷', continent: 'South America', langs: ['es'] },
        { code: 'AM', name: 'Armenia', flag: '🇦🇲', continent: 'Asia', langs: ['hy'] },
        { code: 'AU', name: 'Australia', flag: '🇦🇺', continent: 'Oceania', langs: ['en'] },
        { code: 'AT', name: 'Austria', flag: '🇦🇹', continent: 'Europe', langs: ['de'] },
        { code: 'AZ', name: 'Azerbaijan', flag: '🇦🇿', continent: 'Asia', langs: ['az'] },
        { code: 'BS', name: 'Bahamas', flag: '🇧🇸', continent: 'Caribbean', langs: ['en'] },
        { code: 'BH', name: 'Bahrain', flag: '🇧🇭', continent: 'Asia', langs: ['ar'] },
        { code: 'BD', name: 'Bangladesh', flag: '🇧🇩', continent: 'Asia', langs: ['bn'] },
        { code: 'BB', name: 'Barbados', flag: '🇧🇧', continent: 'Caribbean', langs: ['en'] },
        { code: 'BY', name: 'Belarus', flag: '🇧🇾', continent: 'Europe', langs: ['be', 'ru'] },
        { code: 'BE', name: 'Belgium', flag: '🇧🇪', continent: 'Europe', langs: ['nl', 'fr', 'de'] },
        { code: 'BZ', name: 'Belize', flag: '🇧🇿', continent: 'North America', langs: ['en', 'es'] },
        { code: 'BJ', name: 'Benin', flag: '🇧🇯', continent: 'Africa', langs: ['fr', 'yo'] },
        { code: 'BT', name: 'Bhutan', flag: '🇧🇹', continent: 'Asia', langs: ['dz'] },
        { code: 'BO', name: 'Bolivia', flag: '🇧🇴', continent: 'South America', langs: ['es', 'qu', 'ay', 'gn'] },
        { code: 'BA', name: 'Bosnia and Herzegovina', flag: '🇧🇦', continent: 'Europe', langs: ['bs', 'hr', 'sr'] },
        { code: 'BW', name: 'Botswana', flag: '🇧🇼', continent: 'Africa', langs: ['en', 'tn'] },
        { code: 'BR', name: 'Brazil', flag: '🇧🇷', continent: 'South America', langs: ['pt'] },
        { code: 'BN', name: 'Brunei', flag: '🇧🇳', continent: 'Asia', langs: ['ms', 'en'] },
        { code: 'BG', name: 'Bulgaria', flag: '🇧🇬', continent: 'Europe', langs: ['bg'] },
        { code: 'BF', name: 'Burkina Faso', flag: '🇧🇫', continent: 'Africa', langs: ['fr', 'ff'] },
        { code: 'BI', name: 'Burundi', flag: '🇧🇮', continent: 'Africa', langs: ['rn', 'fr', 'sw'] },
        { code: 'KH', name: 'Cambodia', flag: '🇰🇭', continent: 'Asia', langs: ['km'] },
        { code: 'CM', name: 'Cameroon', flag: '🇨🇲', continent: 'Africa', langs: ['fr', 'en', 'ff'] },
        { code: 'CA', name: 'Canada', flag: '🇨🇦', continent: 'North America', langs: ['en', 'fr'] },
        { code: 'CV', name: 'Cape Verde', flag: '🇨🇻', continent: 'Africa', langs: ['pt'] },
        { code: 'CF', name: 'Central African Republic', flag: '🇨🇫', continent: 'Africa', langs: ['fr'] },
        { code: 'TD', name: 'Chad', flag: '🇹🇩', continent: 'Africa', langs: ['fr', 'ar'] },
        { code: 'CL', name: 'Chile', flag: '🇨🇱', continent: 'South America', langs: ['es'] },
        { code: 'CN', name: 'China', flag: '🇨🇳', continent: 'Asia', langs: ['zh-CN'] },
        { code: 'CO', name: 'Colombia', flag: '🇨🇴', continent: 'South America', langs: ['es'] },
        { code: 'KM', name: 'Comoros', flag: '🇰🇲', continent: 'Africa', langs: ['ar', 'fr'] },
        { code: 'CG', name: 'Congo', flag: '🇨🇬', continent: 'Africa', langs: ['fr', 'ln', 'kg'] },
        { code: 'CD', name: 'Congo (DRC)', flag: '🇨🇩', continent: 'Africa', langs: ['fr', 'ln', 'sw', 'kg'] },
        { code: 'CR', name: 'Costa Rica', flag: '🇨🇷', continent: 'North America', langs: ['es'] },
        { code: 'CI', name: 'Côte d\'Ivoire', flag: '🇨🇮', continent: 'Africa', langs: ['fr'] },
        { code: 'HR', name: 'Croatia', flag: '🇭🇷', continent: 'Europe', langs: ['hr'] },
        { code: 'CU', name: 'Cuba', flag: '🇨🇺', continent: 'Caribbean', langs: ['es'] },
        { code: 'CY', name: 'Cyprus', flag: '🇨🇾', continent: 'Europe', langs: ['el', 'tr'] },
        { code: 'CZ', name: 'Czechia', flag: '🇨🇿', continent: 'Europe', langs: ['cs'] },
        { code: 'DK', name: 'Denmark', flag: '🇩🇰', continent: 'Europe', langs: ['da'] },
        { code: 'DJ', name: 'Djibouti', flag: '🇩🇯', continent: 'Africa', langs: ['fr', 'ar', 'so'] },
        { code: 'DM', name: 'Dominica', flag: '🇩🇲', continent: 'Caribbean', langs: ['en'] },
        { code: 'DO', name: 'Dominican Republic', flag: '🇩🇴', continent: 'Caribbean', langs: ['es'] },
        { code: 'EC', name: 'Ecuador', flag: '🇪🇨', continent: 'South America', langs: ['es', 'qu'] },
        { code: 'EG', name: 'Egypt', flag: '🇪🇬', continent: 'Africa', langs: ['ar'] },
        { code: 'SV', name: 'El Salvador', flag: '🇸🇻', continent: 'North America', langs: ['es'] },
        { code: 'GQ', name: 'Equatorial Guinea', flag: '🇬🇶', continent: 'Africa', langs: ['es', 'fr', 'pt'] },
        { code: 'ER', name: 'Eritrea', flag: '🇪🇷', continent: 'Africa', langs: ['ti', 'ar', 'en'] },
        { code: 'EE', name: 'Estonia', flag: '🇪🇪', continent: 'Europe', langs: ['et'] },
        { code: 'SZ', name: 'Eswatini', flag: '🇸🇿', continent: 'Africa', langs: ['ss', 'en'] },
        { code: 'ET', name: 'Ethiopia', flag: '🇪🇹', continent: 'Africa', langs: ['am', 'om', 'ti', 'so'] },
        { code: 'FJ', name: 'Fiji', flag: '🇫🇯', continent: 'Oceania', langs: ['en', 'fj', 'hi'] },
        { code: 'FI', name: 'Finland', flag: '🇫🇮', continent: 'Europe', langs: ['fi', 'sv'] },
        { code: 'FR', name: 'France', flag: '🇫🇷', continent: 'Europe', langs: ['fr'] },
        { code: 'GA', name: 'Gabon', flag: '🇬🇦', continent: 'Africa', langs: ['fr'] },
        { code: 'GM', name: 'Gambia', flag: '🇬🇲', continent: 'Africa', langs: ['en', 'wo'] },
        { code: 'GE', name: 'Georgia', flag: '🇬🇪', continent: 'Asia', langs: ['ka'] },
        { code: 'DE', name: 'Germany', flag: '🇩🇪', continent: 'Europe', langs: ['de'] },
        { code: 'GH', name: 'Ghana', flag: '🇬🇭', continent: 'Africa', langs: ['en', 'ak', 'ee', 'ha'] },
        { code: 'GR', name: 'Greece', flag: '🇬🇷', continent: 'Europe', langs: ['el'] },
        { code: 'GD', name: 'Grenada', flag: '🇬🇩', continent: 'Caribbean', langs: ['en'] },
        { code: 'GT', name: 'Guatemala', flag: '🇬🇹', continent: 'North America', langs: ['es'] },
        { code: 'GN', name: 'Guinea', flag: '🇬🇳', continent: 'Africa', langs: ['fr', 'ff'] },
        { code: 'GW', name: 'Guinea-Bissau', flag: '🇬🇼', continent: 'Africa', langs: ['pt'] },
        { code: 'GY', name: 'Guyana', flag: '🇬🇾', continent: 'South America', langs: ['en'] },
        { code: 'HT', name: 'Haiti', flag: '🇭🇹', continent: 'Caribbean', langs: ['ht', 'fr'] },
        { code: 'HN', name: 'Honduras', flag: '🇭🇳', continent: 'North America', langs: ['es'] },
        { code: 'HK', name: 'Hong Kong', flag: '🇭🇰', continent: 'Asia', langs: ['zh-TW', 'en'] },
        { code: 'HU', name: 'Hungary', flag: '🇭🇺', continent: 'Europe', langs: ['hu'] },
        { code: 'IS', name: 'Iceland', flag: '🇮🇸', continent: 'Europe', langs: ['is'] },
        { code: 'IN', name: 'India', flag: '🇮🇳', continent: 'Asia', langs: ['hi', 'en', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'ur'] },
        { code: 'ID', name: 'Indonesia', flag: '🇮🇩', continent: 'Asia', langs: ['id'] },
        { code: 'IR', name: 'Iran', flag: '🇮🇷', continent: 'Asia', langs: ['fa'] },
        { code: 'IQ', name: 'Iraq', flag: '🇮🇶', continent: 'Asia', langs: ['ar', 'ku'] },
        { code: 'IE', name: 'Ireland', flag: '🇮🇪', continent: 'Europe', langs: ['ga', 'en'] },
        { code: 'IL', name: 'Israel', flag: '🇮🇱', continent: 'Asia', langs: ['iw', 'ar'] },
        { code: 'IT', name: 'Italy', flag: '🇮🇹', continent: 'Europe', langs: ['it'] },
        { code: 'JM', name: 'Jamaica', flag: '🇯🇲', continent: 'Caribbean', langs: ['en'] },
        { code: 'JP', name: 'Japan', flag: '🇯🇵', continent: 'Asia', langs: ['ja'] },
        { code: 'JO', name: 'Jordan', flag: '🇯🇴', continent: 'Asia', langs: ['ar'] },
        { code: 'KZ', name: 'Kazakhstan', flag: '🇰🇿', continent: 'Asia', langs: ['kk', 'ru'] },
        { code: 'KE', name: 'Kenya', flag: '🇰🇪', continent: 'Africa', langs: ['sw', 'en'] },
        { code: 'KI', name: 'Kiribati', flag: '🇰🇮', continent: 'Oceania', langs: ['en'] },
        { code: 'XK', name: 'Kosovo', flag: '🇽🇰', continent: 'Europe', langs: ['sq', 'sr'] },
        { code: 'KW', name: 'Kuwait', flag: '🇰🇼', continent: 'Asia', langs: ['ar'] },
        { code: 'KG', name: 'Kyrgyzstan', flag: '🇰🇬', continent: 'Asia', langs: ['ky', 'ru'] },
        { code: 'LA', name: 'Laos', flag: '🇱🇦', continent: 'Asia', langs: ['lo'] },
        { code: 'LV', name: 'Latvia', flag: '🇱🇻', continent: 'Europe', langs: ['lv'] },
        { code: 'LB', name: 'Lebanon', flag: '🇱🇧', continent: 'Asia', langs: ['ar', 'fr'] },
        { code: 'LS', name: 'Lesotho', flag: '🇱🇸', continent: 'Africa', langs: ['st', 'en'] },
        { code: 'LR', name: 'Liberia', flag: '🇱🇷', continent: 'Africa', langs: ['en'] },
        { code: 'LY', name: 'Libya', flag: '🇱🇾', continent: 'Africa', langs: ['ar'] },
        { code: 'LI', name: 'Liechtenstein', flag: '🇱🇮', continent: 'Europe', langs: ['de'] },
        { code: 'LT', name: 'Lithuania', flag: '🇱🇹', continent: 'Europe', langs: ['lt'] },
        { code: 'LU', name: 'Luxembourg', flag: '🇱🇺', continent: 'Europe', langs: ['lb', 'fr', 'de'] },
        { code: 'MG', name: 'Madagascar', flag: '🇲🇬', continent: 'Africa', langs: ['mg', 'fr'] },
        { code: 'MW', name: 'Malawi', flag: '🇲🇼', continent: 'Africa', langs: ['ny', 'en'] },
        { code: 'MY', name: 'Malaysia', flag: '🇲🇾', continent: 'Asia', langs: ['ms', 'en', 'zh-CN', 'ta'] },
        { code: 'MV', name: 'Maldives', flag: '🇲🇻', continent: 'Asia', langs: ['dv'] },
        { code: 'ML', name: 'Mali', flag: '🇲🇱', continent: 'Africa', langs: ['bm', 'fr', 'ff'] },
        { code: 'MT', name: 'Malta', flag: '🇲🇹', continent: 'Europe', langs: ['mt', 'en'] },
        { code: 'MH', name: 'Marshall Islands', flag: '🇲🇭', continent: 'Oceania', langs: ['en'] },
        { code: 'MR', name: 'Mauritania', flag: '🇲🇷', continent: 'Africa', langs: ['ar', 'fr', 'wo'] },
        { code: 'MU', name: 'Mauritius', flag: '🇲🇺', continent: 'Africa', langs: ['en', 'fr'] },
        { code: 'MX', name: 'Mexico', flag: '🇲🇽', continent: 'North America', langs: ['es'] },
        { code: 'FM', name: 'Micronesia', flag: '🇫🇲', continent: 'Oceania', langs: ['en'] },
        { code: 'MD', name: 'Moldova', flag: '🇲🇩', continent: 'Europe', langs: ['ro', 'ru'] },
        { code: 'MC', name: 'Monaco', flag: '🇲🇨', continent: 'Europe', langs: ['fr'] },
        { code: 'MN', name: 'Mongolia', flag: '🇲🇳', continent: 'Asia', langs: ['mn'] },
        { code: 'ME', name: 'Montenegro', flag: '🇲🇪', continent: 'Europe', langs: ['sr', 'bs', 'sq', 'hr'] },
        { code: 'MA', name: 'Morocco', flag: '🇲🇦', continent: 'Africa', langs: ['ar', 'fr'] },
        { code: 'MZ', name: 'Mozambique', flag: '🇲🇿', continent: 'Africa', langs: ['pt', 'sw'] },
        { code: 'MM', name: 'Myanmar', flag: '🇲🇲', continent: 'Asia', langs: ['my'] },
        { code: 'NA', name: 'Namibia', flag: '🇳🇦', continent: 'Africa', langs: ['en', 'af', 'de'] },
        { code: 'NR', name: 'Nauru', flag: '🇳🇷', continent: 'Oceania', langs: ['en'] },
        { code: 'NP', name: 'Nepal', flag: '🇳🇵', continent: 'Asia', langs: ['ne'] },
        { code: 'NL', name: 'Netherlands', flag: '🇳🇱', continent: 'Europe', langs: ['nl'] },
        { code: 'NZ', name: 'New Zealand', flag: '🇳🇿', continent: 'Oceania', langs: ['en', 'mi'] },
        { code: 'NI', name: 'Nicaragua', flag: '🇳🇮', continent: 'North America', langs: ['es'] },
        { code: 'NE', name: 'Niger', flag: '🇳🇪', continent: 'Africa', langs: ['ha', 'fr'] },
        { code: 'NG', name: 'Nigeria', flag: '🇳🇬', continent: 'Africa', langs: ['en', 'ha', 'yo', 'ig'] },
        { code: 'KP', name: 'North Korea', flag: '🇰🇵', continent: 'Asia', langs: ['ko'] },
        { code: 'MK', name: 'North Macedonia', flag: '🇲🇰', continent: 'Europe', langs: ['mk', 'sq'] },
        { code: 'NO', name: 'Norway', flag: '🇳🇴', continent: 'Europe', langs: ['no'] },
        { code: 'OM', name: 'Oman', flag: '🇴🇲', continent: 'Asia', langs: ['ar'] },
        { code: 'PK', name: 'Pakistan', flag: '🇵🇰', continent: 'Asia', langs: ['ur', 'en', 'pa', 'ps'] },
        { code: 'PW', name: 'Palau', flag: '🇵🇼', continent: 'Oceania', langs: ['en'] },
        { code: 'PS', name: 'Palestine', flag: '🇵🇸', continent: 'Asia', langs: ['ar'] },
        { code: 'PA', name: 'Panama', flag: '🇵🇦', continent: 'North America', langs: ['es'] },
        { code: 'PG', name: 'Papua New Guinea', flag: '🇵🇬', continent: 'Oceania', langs: ['en'] },
        { code: 'PY', name: 'Paraguay', flag: '🇵🇾', continent: 'South America', langs: ['es', 'gn'] },
        { code: 'PE', name: 'Peru', flag: '🇵🇪', continent: 'South America', langs: ['es', 'qu', 'ay'] },
        { code: 'PH', name: 'Philippines', flag: '🇵🇭', continent: 'Asia', langs: ['tl', 'en'] },
        { code: 'PL', name: 'Poland', flag: '🇵🇱', continent: 'Europe', langs: ['pl'] },
        { code: 'PT', name: 'Portugal', flag: '🇵🇹', continent: 'Europe', langs: ['pt'] },
        { code: 'PR', name: 'Puerto Rico', flag: '🇵🇷', continent: 'Caribbean', langs: ['es', 'en'] },
        { code: 'QA', name: 'Qatar', flag: '🇶🇦', continent: 'Asia', langs: ['ar'] },
        { code: 'RO', name: 'Romania', flag: '🇷🇴', continent: 'Europe', langs: ['ro'] },
        { code: 'RU', name: 'Russia', flag: '🇷🇺', continent: 'Europe', langs: ['ru'] },
        { code: 'RW', name: 'Rwanda', flag: '🇷🇼', continent: 'Africa', langs: ['rw', 'en', 'fr', 'sw'] },
        { code: 'KN', name: 'Saint Kitts and Nevis', flag: '🇰🇳', continent: 'Caribbean', langs: ['en'] },
        { code: 'LC', name: 'Saint Lucia', flag: '🇱🇨', continent: 'Caribbean', langs: ['en'] },
        { code: 'VC', name: 'Saint Vincent and the Grenadines', flag: '🇻🇨', continent: 'Caribbean', langs: ['en'] },
        { code: 'WS', name: 'Samoa', flag: '🇼🇸', continent: 'Oceania', langs: ['sm', 'en'] },
        { code: 'SM', name: 'San Marino', flag: '🇸🇲', continent: 'Europe', langs: ['it'] },
        { code: 'ST', name: 'São Tomé and Príncipe', flag: '🇸🇹', continent: 'Africa', langs: ['pt'] },
        { code: 'SA', name: 'Saudi Arabia', flag: '🇸🇦', continent: 'Asia', langs: ['ar'] },
        { code: 'SN', name: 'Senegal', flag: '🇸🇳', continent: 'Africa', langs: ['fr', 'wo'] },
        { code: 'RS', name: 'Serbia', flag: '🇷🇸', continent: 'Europe', langs: ['sr'] },
        { code: 'SC', name: 'Seychelles', flag: '🇸🇨', continent: 'Africa', langs: ['fr', 'en'] },
        { code: 'SL', name: 'Sierra Leone', flag: '🇸🇱', continent: 'Africa', langs: ['en'] },
        { code: 'SG', name: 'Singapore', flag: '🇸🇬', continent: 'Asia', langs: ['en', 'ms', 'zh-CN', 'ta'] },
        { code: 'SK', name: 'Slovakia', flag: '🇸🇰', continent: 'Europe', langs: ['sk'] },
        { code: 'SI', name: 'Slovenia', flag: '🇸🇮', continent: 'Europe', langs: ['sl'] },
        { code: 'SB', name: 'Solomon Islands', flag: '🇸🇧', continent: 'Oceania', langs: ['en'] },
        { code: 'SO', name: 'Somalia', flag: '🇸🇴', continent: 'Africa', langs: ['so', 'ar'] },
        { code: 'ZA', name: 'South Africa', flag: '🇿🇦', continent: 'Africa', langs: ['zu', 'xh', 'af', 'en', 'st', 'tn', 'ss'] },
        { code: 'KR', name: 'South Korea', flag: '🇰🇷', continent: 'Asia', langs: ['ko'] },
        { code: 'SS', name: 'South Sudan', flag: '🇸🇸', continent: 'Africa', langs: ['en', 'ar'] },
        { code: 'ES', name: 'Spain', flag: '🇪🇸', continent: 'Europe', langs: ['es', 'ca'] },
        { code: 'LK', name: 'Sri Lanka', flag: '🇱🇰', continent: 'Asia', langs: ['si', 'ta', 'en'] },
        { code: 'SD', name: 'Sudan', flag: '🇸🇩', continent: 'Africa', langs: ['ar', 'en'] },
        { code: 'SR', name: 'Suriname', flag: '🇸🇷', continent: 'South America', langs: ['nl'] },
        { code: 'SE', name: 'Sweden', flag: '🇸🇪', continent: 'Europe', langs: ['sv'] },
        { code: 'CH', name: 'Switzerland', flag: '🇨🇭', continent: 'Europe', langs: ['de', 'fr', 'it'] },
        { code: 'SY', name: 'Syria', flag: '🇸🇾', continent: 'Asia', langs: ['ar'] },
        { code: 'TW', name: 'Taiwan', flag: '🇹🇼', continent: 'Asia', langs: ['zh-TW'] },
        { code: 'TJ', name: 'Tajikistan', flag: '🇹🇯', continent: 'Asia', langs: ['tg', 'ru'] },
        { code: 'TZ', name: 'Tanzania', flag: '🇹🇿', continent: 'Africa', langs: ['sw', 'en'] },
        { code: 'TH', name: 'Thailand', flag: '🇹🇭', continent: 'Asia', langs: ['th'] },
        { code: 'TL', name: 'Timor-Leste', flag: '🇹🇱', continent: 'Asia', langs: ['tet', 'pt'] },
        { code: 'TG', name: 'Togo', flag: '🇹🇬', continent: 'Africa', langs: ['fr', 'ee'] },
        { code: 'TO', name: 'Tonga', flag: '🇹🇴', continent: 'Oceania', langs: ['to', 'en'] },
        { code: 'TT', name: 'Trinidad and Tobago', flag: '🇹🇹', continent: 'Caribbean', langs: ['en'] },
        { code: 'TN', name: 'Tunisia', flag: '🇹🇳', continent: 'Africa', langs: ['ar', 'fr'] },
        { code: 'TR', name: 'Turkey', flag: '🇹🇷', continent: 'Asia', langs: ['tr'] },
        { code: 'TM', name: 'Turkmenistan', flag: '🇹🇲', continent: 'Asia', langs: ['tk', 'ru'] },
        { code: 'TV', name: 'Tuvalu', flag: '🇹🇻', continent: 'Oceania', langs: ['en'] },
        { code: 'UG', name: 'Uganda', flag: '🇺🇬', continent: 'Africa', langs: ['en', 'sw', 'lg'] },
        { code: 'UA', name: 'Ukraine', flag: '🇺🇦', continent: 'Europe', langs: ['uk'] },
        { code: 'AE', name: 'United Arab Emirates', flag: '🇦🇪', continent: 'Asia', langs: ['ar', 'en'] },
        { code: 'GB', name: 'United Kingdom', flag: '🇬🇧', continent: 'Europe', langs: ['en', 'cy', 'gd'] },
        { code: 'US', name: 'United States', flag: '🇺🇸', continent: 'North America', langs: ['en', 'es'] },
        { code: 'UY', name: 'Uruguay', flag: '🇺🇾', continent: 'South America', langs: ['es'] },
        { code: 'UZ', name: 'Uzbekistan', flag: '🇺🇿', continent: 'Asia', langs: ['uz', 'ru'] },
        { code: 'VU', name: 'Vanuatu', flag: '🇻🇺', continent: 'Oceania', langs: ['en', 'fr'] },
        { code: 'VA', name: 'Vatican City', flag: '🇻🇦', continent: 'Europe', langs: ['it'] },
        { code: 'VE', name: 'Venezuela', flag: '🇻🇪', continent: 'South America', langs: ['es'] },
        { code: 'VN', name: 'Vietnam', flag: '🇻🇳', continent: 'Asia', langs: ['vi'] },
        { code: 'YE', name: 'Yemen', flag: '🇾🇪', continent: 'Asia', langs: ['ar'] },
        { code: 'ZM', name: 'Zambia', flag: '🇿🇲', continent: 'Africa', langs: ['en', 'ny'] },
        { code: 'ZW', name: 'Zimbabwe', flag: '🇿🇼', continent: 'Africa', langs: ['sn', 'en', 'ny'] }
    ];

    function getLangByCode(code) {
        if (!code) return WORLD_LANGUAGES[0];
        const lower = code.toLowerCase();
        return (
            WORLD_LANGUAGES.find(l => l.code.toLowerCase() === lower) ||
            WORLD_LANGUAGES.find(l => l.code.toLowerCase().split('-')[0] === lower.split('-')[0]) ||
            WORLD_LANGUAGES[0]
        );
    }

    function getCountriesForLangCode(code) {
        return WORLD_COUNTRIES.filter(c => c.langs.includes(code));
    }

    function getInitialLangCode() {
        try {
            const params = new URLSearchParams(window.location.search);
            const urlLang = params.get('lang');
            if (urlLang) {
                const match = getLangByCode(urlLang);
                localStorage.setItem(LANG_STORAGE_KEY, match.code);
                return match.code;
            }
            const saved = localStorage.getItem(LANG_STORAGE_KEY);
            if (saved) return getLangByCode(saved).code;
        } catch (e) {}
        return 'en';
    }

    let currentLangCode = getInitialLangCode();
    let byCountryMode = false;
    let searchQuery = '';

    function setGoogTransCookie(langCode) {
        try {
            const target = langCode === 'en' ? '' : `/en/${langCode}`;
            const host = window.location.hostname;
            if (!target) {
                document.cookie = 'googtrans=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;';
                if (host) {
                    document.cookie = `googtrans=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/; domain=${host};`;
                    document.cookie = `googtrans=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/; domain=.${host};`;
                }
            } else {
                document.cookie = `googtrans=${target}; path=/`;
                if (host && host !== 'localhost') {
                    document.cookie = `googtrans=${target}; path=/; domain=${host}`;
                    document.cookie = `googtrans=${target}; path=/; domain=.${host}`;
                }
            }
        } catch (e) {}
    }

    function ensureGoogleTranslateLoaded() {
        if (document.getElementById('dn-google-translate-script')) return;
        let holder = document.getElementById('google_translate_element');
        if (!holder) {
            holder = document.createElement('div');
            holder.id = 'google_translate_element';
            holder.style.display = 'none';
            document.body.appendChild(holder);
        }
        window.googleTranslateElementInit = function () {
            if (window.google && window.google.translate) {
                new window.google.translate.TranslateElement(
                    {
                        pageLanguage: 'en',
                        autoDisplay: false
                    },
                    'google_translate_element'
                );
            }
        };
        const s = document.createElement('script');
        s.id = 'dn-google-translate-script';
        s.src = 'https://translate.google.com/translate_a/element.js?cb=googleTranslateElementInit';
        s.async = true;
        document.head.appendChild(s);
    }

    function triggerNeuralTranslate(langCode) {
        setGoogTransCookie(langCode);
        ensureGoogleTranslateLoaded();

        let attempts = 0;
        const applyCombo = () => {
            const combo = document.querySelector('.goog-te-combo');
            if (combo) {
                combo.value = langCode === 'en' ? 'en' : langCode;
                combo.dispatchEvent(new Event('change'));
                return true;
            }
            return false;
        };

        if (!applyCombo()) {
            const timer = setInterval(() => {
                attempts++;
                if (applyCombo() || attempts > 25) {
                    clearInterval(timer);
                }
            }, 200);
        }
    }

    function updateToggleButtonUI() {
        const lang = getLangByCode(currentLangCode);
        const flagEl = document.getElementById('lang-toggle-flag');
        const codeEl = document.getElementById('lang-toggle-code');
        const btn = document.getElementById('lang-toggle');
        if (flagEl) flagEl.textContent = lang.flag;
        if (codeEl) codeEl.textContent = lang.code.split('-')[0].toUpperCase();
        if (btn) {
            btn.setAttribute('title', `Language: ${lang.nativeName} (${lang.name})`);
        }
        document.documentElement.setAttribute('lang', lang.code);
        document.documentElement.setAttribute('dir', lang.rtl ? 'rtl' : 'ltr');
    }

    function renderModalList() {
        const body = document.getElementById('lang-modal-body');
        const tabLangs = document.getElementById('lang-tab-all');
        const tabCountries = document.getElementById('lang-tab-countries');
        const clearBtn = document.getElementById('lang-search-clear');
        if (!body) return;

        if (tabLangs) tabLangs.classList.toggle('active', !byCountryMode);
        if (tabCountries) tabCountries.classList.toggle('active', byCountryMode);
        if (clearBtn) clearBtn.classList.toggle('visible', searchQuery.trim().length > 0);

        const q = searchQuery.trim().toLowerCase();

        if (!byCountryMode) {
            const filtered = WORLD_LANGUAGES.filter(l => {
                if (!q) return true;
                if (
                    l.name.toLowerCase().includes(q) ||
                    l.nativeName.toLowerCase().includes(q) ||
                    l.code.toLowerCase().includes(q)
                ) {
                    return true;
                }
                const countries = getCountriesForLangCode(l.code);
                return countries.some(
                    c => c.name.toLowerCase().includes(q) || c.continent.toLowerCase().includes(q)
                );
            });

            if (filtered.length === 0) {
                body.innerHTML = `<div style="padding:32px;text-align:center;color:var(--fg-muted);font-size:14px;">No matching languages or countries found.</div>`;
                return;
            }

            body.innerHTML = `<div class="lang-grid">${filtered
                .map(l => {
                    const isActive = l.code.toLowerCase() === currentLangCode.toLowerCase();
                    const countries = getCountriesForLangCode(l.code);
                    const countryNames = countries.slice(0, 3).map(c => c.name).join(', ');
                    const sub = countryNames ? `${l.name} • ${countryNames}` : l.name;
                    return `
                        <button type="button" class="lang-item ${isActive ? 'active' : ''}" data-lang="${l.code}">
                            <span class="lang-item-flag">${l.flag}</span>
                            <div class="lang-item-info">
                                <div class="lang-item-native">${l.nativeName}</div>
                                <div class="lang-item-english">${sub}</div>
                            </div>
                            <span class="lang-item-badge">${isActive ? '✓' : l.code.split('-')[0].toUpperCase()}</span>
                        </button>
                    `;
                })
                .join('')}</div>`;
        } else {
            const filteredCountries = WORLD_COUNTRIES.filter(c => {
                if (!q) return true;
                if (
                    c.name.toLowerCase().includes(q) ||
                    c.code.toLowerCase().includes(q) ||
                    c.continent.toLowerCase().includes(q)
                ) {
                    return true;
                }
                return c.langs.some(code => {
                    const l = getLangByCode(code);
                    return (
                        l.name.toLowerCase().includes(q) ||
                        l.nativeName.toLowerCase().includes(q)
                    );
                });
            });

            if (filteredCountries.length === 0) {
                body.innerHTML = `<div style="padding:32px;text-align:center;color:var(--fg-muted);font-size:14px;">No matching countries found.</div>`;
                return;
            }

            body.innerHTML = `<div class="country-lang-list">${filteredCountries
                .map(c => {
                    const chips = c.langs
                        .map(code => {
                            const l = getLangByCode(code);
                            const active = l.code.toLowerCase() === currentLangCode.toLowerCase();
                            const label =
                                l.nativeName.toLowerCase() === l.name.toLowerCase()
                                    ? l.name
                                    : `${l.nativeName} (${l.name})`;
                            return `<button type="button" class="country-lang-chip ${active ? 'active' : ''}" data-lang="${l.code}">${label}${active ? ' ✓' : ''}</button>`;
                        })
                        .join('');
                    return `
                        <div class="country-lang-row">
                            <div class="country-lang-head">
                                <div class="country-lang-name"><span>${c.flag}</span><span>${c.name}</span></div>
                                <span class="country-lang-continent">${c.continent}</span>
                            </div>
                            <div class="country-lang-chips">${chips}</div>
                        </div>
                    `;
                })
                .join('')}</div>`;
        }

        body.querySelectorAll('[data-lang]').forEach(el => {
            el.addEventListener('click', () => {
                const chosen = el.getAttribute('data-lang');
                selectLanguage(chosen);
            });
        });
    }

    function selectLanguage(code) {
        const lang = getLangByCode(code);
        currentLangCode = lang.code;
        try {
            localStorage.setItem(LANG_STORAGE_KEY, lang.code);
        } catch (e) {}

        updateToggleButtonUI();
        closeModal();

        if (lang.code === 'en') {
            setGoogTransCookie('en');
            if (document.querySelector('.goog-te-combo')) {
                window.location.reload();
            }
        } else {
            triggerNeuralTranslate(lang.code);
        }
    }

    function openModal() {
        let overlay = document.getElementById('lang-modal-overlay');
        if (!overlay) {
            overlay = document.createElement('div');
            overlay.id = 'lang-modal-overlay';
            overlay.className = 'lang-modal-overlay notranslate';
            overlay.setAttribute('translate', 'no');
            overlay.innerHTML = `
                <div class="lang-modal-card" role="dialog" aria-modal="true" aria-labelledby="lang-modal-title">
                    <div class="lang-modal-header">
                        <div class="lang-modal-title-wrap">
                            <div class="lang-modal-icon">🌐</div>
                            <div>
                                <h3 class="lang-modal-title" id="lang-modal-title">Select World Language</h3>
                                <p class="lang-modal-subtitle">All main official languages of every country in the world</p>
                            </div>
                        </div>
                        <button type="button" class="lang-modal-close" id="lang-modal-close" aria-label="Close">✕</button>
                    </div>
                    <div class="lang-modal-controls">
                        <div class="lang-search-wrap">
                            <input type="text" class="lang-search-input" id="lang-search-input" placeholder="Search country (e.g. Tanzania, Brazil) or language..." autocomplete="off">
                            <button type="button" class="lang-search-clear" id="lang-search-clear" aria-label="Clear search">✕</button>
                        </div>
                        <div class="lang-mode-tabs">
                            <button type="button" class="lang-mode-tab active" id="lang-tab-all">All Official Languages (${WORLD_LANGUAGES.length})</button>
                            <button type="button" class="lang-mode-tab" id="lang-tab-countries">By Country (${WORLD_COUNTRIES.length})</button>
                        </div>
                    </div>
                    <div class="lang-modal-body" id="lang-modal-body"></div>
                </div>
            `;
            document.body.appendChild(overlay);

            overlay.addEventListener('click', e => {
                if (e.target === overlay) closeModal();
            });
            document.getElementById('lang-modal-close').addEventListener('click', closeModal);

            const searchInput = document.getElementById('lang-search-input');
            const clearBtn = document.getElementById('lang-search-clear');
            searchInput.addEventListener('input', e => {
                searchQuery = e.target.value || '';
                renderModalList();
            });
            clearBtn.addEventListener('click', () => {
                searchQuery = '';
                searchInput.value = '';
                renderModalList();
                searchInput.focus();
            });

            document.getElementById('lang-tab-all').addEventListener('click', () => {
                byCountryMode = false;
                renderModalList();
            });
            document.getElementById('lang-tab-countries').addEventListener('click', () => {
                byCountryMode = true;
                renderModalList();
            });

            document.addEventListener('keydown', e => {
                if (e.key === 'Escape' && overlay.classList.contains('open')) {
                    closeModal();
                }
            });
        }

        renderModalList();
        overlay.classList.add('open');
        const input = document.getElementById('lang-search-input');
        if (input) setTimeout(() => input.focus(), 60);
    }

    function closeModal() {
        const overlay = document.getElementById('lang-modal-overlay');
        if (overlay) overlay.classList.remove('open');
    }

    function setupNavbarTrigger() {
        let btn = document.getElementById('lang-toggle');
        if (!btn) {
            const navActions = document.querySelector('.nav-actions');
            if (navActions) {
                btn = document.createElement('button');
                btn.className = 'lang-toggle notranslate';
                btn.id = 'lang-toggle';
                btn.setAttribute('translate', 'no');
                btn.setAttribute('aria-label', 'Select language');
                btn.innerHTML = `<span class="lang-toggle-flag" id="lang-toggle-flag">🌐</span><span class="lang-toggle-code" id="lang-toggle-code">EN</span>`;
                navActions.prepend(btn);
            }
        }
        if (btn && !btn.dataset.langBound) {
            btn.dataset.langBound = 'true';
            btn.addEventListener('click', e => {
                e.preventDefault();
                openModal();
            });
        }
        updateToggleButtonUI();
        if (currentLangCode !== 'en') {
            triggerNeuralTranslate(currentLangCode);
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', setupNavbarTrigger);
    } else {
        setupNavbarTrigger();
    }
})();

