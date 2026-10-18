/**
 * Diaspora Nearby – Free Direct Meta Publisher (Facebook & Instagram)
 * 
 * 100% Free Direct Integration with Meta Graph API.
 * Zero subscriptions, zero credit cards, zero third-party intermediaries.
 * 
 * Features:
 * - Post text and link to Diaspora Nearby Facebook Page (ID: 61566733779638)
 * - Post single photos / graphic cards to Facebook Page
 * - Post photos and Reels directly to Instagram Professional (@diasporanearby)
 * - Auto-discovers linked Instagram Business Account from the Facebook Page
 */

const axios = require("axios");

const GRAPH_API_BASE = "https://graph.facebook.com/v19.0";

const VISUAL_CARD_POOL = [
  {
    url: "https://diasporanearby.com/images/social-cards/card-1-find-your-people.png",
    keywords: ["nearby", "proximity", "find your people", "city", "landing"],
  },
  {
    url: "https://diasporanearby.com/images/social-cards/card-2-dual-identity.png",
    keywords: ["dual", "identity", "home", "host"],
  },
  {
    url: "https://diasporanearby.com/images/social-cards/card-3-dsp-base-blockchain.png",
    keywords: ["epoch", "web3", "web2", "token", "mint"],
  },
  {
    url: "https://diasporanearby.com/images/social-cards/card-4-ubuntu-treasury.png",
    keywords: ["ubuntu", "1:1", "treasury", "match", "homeland"],
  },
  {
    url: "https://diasporanearby.com/images/social-cards/card-5-proof-of-trust.png",
    keywords: ["pct", "proof of community trust", "efficiency", "reputation"],
  },
  {
    url: "https://diasporanearby.com/images/social-cards/card-6-trust-vouching.png",
    keywords: ["hosting", "stranger", "family", "vouch", "travel"],
  },
  {
    url: "https://diasporanearby.com/images/social-cards/card-7-communities-chambers.png",
    keywords: ["chamber", "community", "neighborhood", "campus"],
  },
  {
    url: "https://diasporanearby.com/images/social-cards/card-8-sovereign-ecosystem.png",
    keywords: ["ddi", "loan", "collateral", "staking", "enterprise"],
  },
];

/**
 * Selects a 1080x1080 visual card matching the topic (or rotates daily/randomly across the 8-card pool)
 */
function getRotatingVisualCardUrl(topic = "") {
  if (process.env.SOCIAL_SHARE_IMAGE_URL) {
    return process.env.SOCIAL_SHARE_IMAGE_URL;
  }
  const lower = (topic || "").toLowerCase();
  if (lower) {
    const matched = VISUAL_CARD_POOL.find((card) =>
      card.keywords.some((kw) => lower.includes(kw))
    );
    if (matched) {
      return matched.url;
    }
  }
  const dayIndex = Math.floor(Date.now() / (1000 * 60 * 60 * 12)) % VISUAL_CARD_POOL.length;
  return VISUAL_CARD_POOL[dayIndex].url;
}

function getMetaCredentials() {
  const pageAccessToken = process.env.META_PAGE_ACCESS_TOKEN || process.env.FACEBOOK_PAGE_ACCESS_TOKEN;
  const pageId = process.env.META_PAGE_ID || process.env.FACEBOOK_PAGE_ID || "455143491012634";
  const igAccountId = process.env.META_IG_ACCOUNT_ID || process.env.INSTAGRAM_ACCOUNT_ID || "17841447509471358";

  return { pageAccessToken, pageId, igAccountId };
}

/**
 * Check if Meta Page Access Token is configured and valid
 */
async function checkMetaStatus() {
  const { pageAccessToken, pageId, igAccountId } = getMetaCredentials();

  if (!pageAccessToken) {
    return {
      configured: false,
      message: "META_PAGE_ACCESS_TOKEN is missing in functions/.env",
      pageId,
      igAccountId,
    };
  }

  try {
    const res = await axios.get(`${GRAPH_API_BASE}/${pageId}`, {
      params: {
        fields: "id,name,link,instagram_business_account",
        access_token: pageAccessToken,
      },
      timeout: 10000,
    });

    const linkedIg = res.data?.instagram_business_account?.id || igAccountId;

    return {
      configured: true,
      pageName: res.data?.name,
      pageId: res.data?.id,
      instagramAccountId: linkedIg,
      valid: true,
    };
  } catch (err) {
    return {
      configured: true,
      valid: false,
      error: err.response?.data?.error?.message || err.message,
    };
  }
}

/**
 * Post Text & Link directly to Facebook Page
 */
async function postToFacebookPage({ message, link = "https://diasporanearby.com" }) {
  const { pageAccessToken, pageId } = getMetaCredentials();

  if (!pageAccessToken) {
    throw new Error("META_PAGE_ACCESS_TOKEN is required in functions/.env");
  }

  const payload = {
    message: message.trim(),
    access_token: pageAccessToken,
  };

  if (link) {
    payload.link = link;
  }

  const res = await axios.post(`${GRAPH_API_BASE}/${pageId}/feed`, payload);

  const postId = res.data?.id;
  const postUrl = `https://www.facebook.com/${postId}`;

  return {
    success: true,
    platform: "facebook",
    postId,
    postUrl,
    message: message.trim(),
  };
}

/**
 * Post Photo to Facebook Page
 */
async function postPhotoToFacebookPage({ imageUrl, caption = "" }) {
  const { pageAccessToken, pageId } = getMetaCredentials();

  if (!pageAccessToken) {
    throw new Error("META_PAGE_ACCESS_TOKEN is required in functions/.env");
  }

  const payload = {
    url: imageUrl,
    caption: caption.trim(),
    access_token: pageAccessToken,
  };

  const res = await axios.post(`${GRAPH_API_BASE}/${pageId}/photos`, payload);

  const photoId = res.data?.id;
  const postUrl = `https://www.facebook.com/${photoId}`;

  return {
    success: true,
    platform: "facebook_photo",
    photoId,
    postUrl,
  };
}

/**
 * Post Photo to Instagram Professional Account
 */
async function postPhotoToInstagram({ imageUrl, caption = "" }) {
  const { pageAccessToken, pageId, igAccountId } = getMetaCredentials();

  if (!pageAccessToken) {
    throw new Error("META_PAGE_ACCESS_TOKEN is required in functions/.env");
  }

  // 1. Resolve Instagram Business Account ID if not set
  let targetIgId = igAccountId;
  if (!targetIgId) {
    const pageInfo = await axios.get(`${GRAPH_API_BASE}/${pageId}`, {
      params: {
        fields: "instagram_business_account",
        access_token: pageAccessToken,
      },
    });
    targetIgId = pageInfo.data?.instagram_business_account?.id;
    if (!targetIgId) {
      throw new Error(
        "No linked Instagram Business Account found on Facebook Page. Ensure @diasporanearby is linked to the Facebook Page."
      );
    }
  }

  // 2. Create Media Container
  const containerRes = await axios.post(`${GRAPH_API_BASE}/${targetIgId}/media`, {
    image_url: imageUrl,
    caption: caption.trim(),
    access_token: pageAccessToken,
  });

  const creationId = containerRes.data?.id;
  if (!creationId) {
    throw new Error("Failed to create Instagram media container.");
  }

  // 3. Poll container status until FINISHED (up to 6 attempts, 2.5s apart)
  for (let attempt = 0; attempt < 6; attempt++) {
    await new Promise((r) => setTimeout(r, 2500));
    try {
      const statusRes = await axios.get(`${GRAPH_API_BASE}/${creationId}`, {
        params: {
          fields: "status_code,status",
          access_token: pageAccessToken,
        },
      });
      const statusCode = statusRes.data?.status_code;
      if (statusCode === "FINISHED") {
        break;
      }
      if (statusCode === "ERROR" || statusCode === "EXPIRED") {
        throw new Error(`Instagram media container failed with status: ${statusCode}`);
      }
    } catch (pollErr) {
      if (pollErr.message.includes("Instagram media container failed")) {
        throw pollErr;
      }
      // Continue if status endpoint transiently fails
    }
  }

  // 4. Publish Media Container
  const publishRes = await axios.post(`${GRAPH_API_BASE}/${targetIgId}/media_publish`, {
    creation_id: creationId,
    access_token: pageAccessToken,
  });

  const igMediaId = publishRes.data?.id;
  let postUrl = `https://www.instagram.com/p/${igMediaId}/`;

  // 5. Fetch canonical permalink for the published Instagram media
  if (igMediaId) {
    try {
      const mediaInfo = await axios.get(`${GRAPH_API_BASE}/${igMediaId}`, {
        params: {
          fields: "permalink,shortcode",
          access_token: pageAccessToken,
        },
      });
      if (mediaInfo.data?.permalink) {
        postUrl = mediaInfo.data.permalink;
      }
    } catch (_permErr) {
      // Fallback to igMediaId URL if permalink lookup fails
    }
  }

  return {
    success: true,
    platform: "instagram",
    mediaId: igMediaId,
    postUrl,
  };
}

module.exports = {
  VISUAL_CARD_POOL,
  getRotatingVisualCardUrl,
  getMetaCredentials,
  checkMetaStatus,
  postToFacebookPage,
  postPhotoToFacebookPage,
  postPhotoToInstagram,
};
