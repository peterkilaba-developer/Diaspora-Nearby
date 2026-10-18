/**
 * Diaspora Nearby – Unified Multi-Platform Social Publisher
 * 
 * Powered by Unified Social API (Ayrshare) with native API fallback.
 * Simultaneously broadcasts text, images, audio, and video to:
 * - X (Twitter)
 * - LinkedIn (Personal & Company Page)
 * - YouTube (Shorts & Standard Videos)
 * - Facebook (Page)
 * - Instagram (Feed & Reels)
 * - TikTok (Videos)
 */

const axios = require("axios");
const path = require("path");

const AYRSHARE_API_URL = "https://app.ayrshare.com/api/post";
const AYRSHARE_PROFILE_URL = "https://app.ayrshare.com/api/profiles";

/**
 * Check Ayrshare API Key configuration and connected platforms
 */
async function checkUnifiedApiStatus() {
  const apiKey = process.env.AYRSHARE_API_KEY;
  if (!apiKey) {
    return {
      configured: false,
      message: "AYRSHARE_API_KEY not set in functions/.env",
      platforms: [],
    };
  }

  try {
    const res = await axios.get(AYRSHARE_PROFILE_URL, {
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      timeout: 10000,
    });

    const activePlatforms = res.data?.activeSocialAccounts || [];
    return {
      configured: true,
      activePlatforms,
      details: res.data,
    };
  } catch (err) {
    return {
      configured: true,
      error: err.response?.data?.message || err.message,
      platforms: [],
    };
  }
}

/**
 * Broadcast multimedia post to all connected platforms
 * 
 * @param {Object} options
 * @param {string} options.post - Text copy / caption for social feeds
 * @param {string[]} [options.platforms] - Target platforms (default: all 6)
 * @param {string[]} [options.mediaUrls] - Public image/video URLs
 * @param {boolean} [options.isVideo] - Whether media is a video (Short/Reel/TikTok)
 * @param {string} [options.videoTitle] - Title for YouTube & TikTok
 * @param {string} [options.scheduleDate] - Optional ISO schedule string
 */
async function broadcastUnifiedPost({
  post,
  platforms = ["twitter", "linkedin", "facebook", "instagram", "youtube", "tiktok"],
  mediaUrls = [],
  isVideo = false,
  videoTitle = null,
  scheduleDate = null,
}) {
  const apiKey = process.env.AYRSHARE_API_KEY;

  if (!apiKey) {
    console.warn("⚠️ AYRSHARE_API_KEY missing in .env. Falling back to native publishers for X, LinkedIn, and YouTube...");
    return await fallbackNativePublish({ post, videoTitle, mediaUrls, isVideo });
  }

  const cleanPost = post.trim();
  const payload = {
    post: cleanPost,
    platforms,
    shortenLinks: true,
  };

  if (mediaUrls && mediaUrls.length > 0) {
    payload.mediaUrls = mediaUrls;
  }

  // Configure YouTube specific options
  if (platforms.includes("youtube")) {
    payload.youTubeOptions = {
      title: (videoTitle || cleanPost.split("\n")[0]).slice(0, 95) + (isVideo ? " #Shorts" : ""),
      visibility: "public",
      category: "28", // Science & Tech
    };
  }

  // Configure TikTok specific options
  if (platforms.includes("tiktok")) {
    payload.tikTokOptions = {
      privacy_level: "PUBLIC_TO_EVERYONE",
      disable_duet: false,
      disable_comment: false,
    };
  }

  // Configure Instagram specific options
  if (platforms.includes("instagram")) {
    payload.instagramOptions = {
      shareToFeed: true,
    };
  }

  if (scheduleDate) {
    payload.scheduleDate = scheduleDate;
  }

  try {
    const res = await axios.post(AYRSHARE_API_URL, payload, {
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      timeout: 30000,
    });

    return {
      success: true,
      provider: "ayrshare",
      id: res.data?.id,
      postIds: res.data?.postIds,
      status: res.data?.status,
      errors: res.data?.errors || [],
      raw: res.data,
    };
  } catch (err) {
    const errMsg = err.response?.data?.message || err.message;
    console.error("❌ Unified Social API broadcast error:", errMsg);
    throw new Error(`Unified Broadcast failed: ${errMsg}`);
  }
}

/**
 * Fallback to direct X and LinkedIn posting if Ayrshare is not configured
 */
async function fallbackNativePublish({ post, videoTitle, mediaUrls, isVideo }) {
  const { postTweet, postToLinkedIn } = require("./social_media");
  const results = { fallback: true, x: null, linkedIn: null };

  // 1. Post to X (truncate to 275 chars if needed)
  try {
    let xText = post.trim();
    if (xText.length > 280) {
      xText = xText.substring(0, 275) + "...";
    }
    results.x = await postTweet(xText);
    console.log(`✅ [Fallback] Published to X: ${results.x.tweetUrl}`);
  } catch (e) {
    results.x = { error: e.message };
  }

  // 2. Post to LinkedIn
  try {
    results.linkedIn = await postToLinkedIn(post, { postToOrg: true });
    console.log(`✅ [Fallback] Published to LinkedIn: ${results.linkedIn.postUrl}`);
  } catch (e) {
    results.linkedIn = { error: e.message };
  }

  return results;
}

module.exports = {
  checkUnifiedApiStatus,
  broadcastUnifiedPost,
};
