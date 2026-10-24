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
                    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"></path><polyline points="15 3 21 3 21 9"></polyline><line x1="10" y1="14" x2="21" y2="3"></line></svg></a>${isIOS ? `<div style="margin-top: 16px; padding: 14px; border-radius: 12px; background: var(--surface-hover, rgba(128,128,128,0.08)); border: 1px solid var(--border); font-size: 13px; color: var(--fg-muted); text-align: left; line-height: 1.55; width: 100%;"><strong style="color: var(--fg); display: block; margin-bottom: 6px;">First time using TestFlight?</strong>1. <a href="${TESTFLIGHT_APP_STORE_URL}" target="_blank" rel="noopener" style="color: var(--sage); font-weight: 600; text-decoration: underline;">Install Apple TestFlight</a> from the App Store first.<br>2. <strong>Come back to this page</strong> and tap <strong>Open in TestFlight</strong> above (do <em>not</em> open TestFlight from the App Store or tap "Redeem"—no invite code is needed).<br><span style="display:block; margin-top:6px; font-size:12px; opacity:0.85;">💡 If you opened this inside WhatsApp/Instagram and it asks for a code, tap the browser icon in the corner to <strong>Open in Safari</strong>.</span></div>` : ''}<a style="display:none">
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
