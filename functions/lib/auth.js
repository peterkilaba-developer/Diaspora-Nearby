const { functions, admin, db } = require("./shared");
const {
  requireAppCheck,
  stableHash,
  consumeRateLimit,
} = require("./security");
const crypto = require("crypto");
const { parsePhoneNumberFromString } = require("libphonenumber-js");

function normalizePhoneNumber(value) {
  if (typeof value !== "string" || value.length > 32) return null;
  const parsed = parsePhoneNumberFromString(value);
  return parsed && parsed.isValid() ? parsed.number : null;
}

const TEST_PHONE_NUMBERS = new Set([
  "+16505551230", // Test user
  "+16505551231", // Test User B
  "+16505550100", // Standard NANP test number
  "+16505550101",
]);

function isTestPhoneNumber(phoneNumber) {
  if (!phoneNumber) return false;
  if (TEST_PHONE_NUMBERS.has(phoneNumber)) return true;
  if (process.env.TEST_WHATSAPP_NUMBERS) {
    const list = process.env.TEST_WHATSAPP_NUMBERS.split(",").map((s) => s.trim());
    if (list.includes(phoneNumber)) return true;
  }
  // Standard NANP fictitious phone numbers (e.g. +1-650-555-01xx)
  if (/^\+1\d{3}55501\d{2}$/.test(phoneNumber)) return true;
  return false;
}

function otpDigest(phoneNumber, otp) {
  const pepper = process.env.OTP_PEPPER;
  if (!pepper || pepper.length < 32) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Phone verification is not configured.",
    );
  }
  return crypto.createHmac("sha256", pepper)
      .update(`${phoneNumber}:${otp}`)
      .digest("hex");
}

function constantTimeEqual(left, right) {
  if (typeof left !== "string" || typeof right !== "string") return false;
  const leftBuffer = Buffer.from(left, "hex");
  const rightBuffer = Buffer.from(right, "hex");
  return leftBuffer.length === rightBuffer.length &&
    crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

/**
 * Deliver OTP via Meta WhatsApp Cloud API.
 * Supports Message Templates (required for business-initiated conversations
 * outside 24h window) with graceful fallback to freeform text if a conversation
 * window is open.
 */
async function deliverWhatsAppMessage({
  phoneNumberId,
  accessToken,
  recipientPhone,
  otp,
  templateName,
  templateLang,
}) {
  const url = `https://graph.facebook.com/v20.0/${phoneNumberId}/messages`;
  const headers = {
    "Authorization": `Bearer ${accessToken}`,
    "Content-Type": "application/json",
  };

  // 1. If template is configured, try sending template message
  if (templateName) {
    // Attempt 1A: Template with body parameter and copy-code / URL button parameter
    const payloadWithButton = {
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: recipientPhone,
      type: "template",
      template: {
        name: templateName,
        language: { code: templateLang || "en_US" },
        components: [
          {
            type: "body",
            parameters: [{ type: "text", text: otp }],
          },
          {
            type: "button",
            sub_type: "url",
            index: "0",
            parameters: [{ type: "text", text: otp }],
          },
        ],
      },
    };

    try {
      const response = await fetch(url, {
        method: "POST",
        headers,
        body: JSON.stringify(payloadWithButton),
      });

      if (response.ok) {
        return { ok: true, method: "template-button" };
      }

      const errText = await response.text();
      console.warn(
          `WhatsApp template with button delivery failed (${response.status}):`,
          errText,
      );

      // Attempt 1B: Template with body parameter only
      const payloadBodyOnly = {
        messaging_product: "whatsapp",
        recipient_type: "individual",
        to: recipientPhone,
        type: "template",
        template: {
          name: templateName,
          language: { code: templateLang || "en_US" },
          components: [
            {
              type: "body",
              parameters: [{ type: "text", text: otp }],
            },
          ],
        },
      };

      const responseBody = await fetch(url, {
        method: "POST",
        headers,
        body: JSON.stringify(payloadBodyOnly),
      });

      if (responseBody.ok) {
        return { ok: true, method: "template-body" };
      }

      const errBodyText = await responseBody.text();
      console.warn(
          `WhatsApp template body-only delivery failed (${responseBody.status}):`,
          errBodyText,
      );
    } catch (err) {
      console.warn("WhatsApp template fetch error:", err.message);
    }
  }

  // 2. Freeform text message (works within 24h window or in sandbox)
  try {
    const textResponse = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify({
        messaging_product: "whatsapp",
        recipient_type: "individual",
        to: recipientPhone,
        type: "text",
        text: {
          preview_url: false,
          body: `Your Diaspora Nearby verification code is: ${otp}`,
        },
      }),
    });

    if (textResponse.ok) {
      return { ok: true, method: "text" };
    }

    const textErr = await textResponse.text();
    return { ok: false, status: textResponse.status, errorText: textErr };
  } catch (err) {
    return { ok: false, status: 500, errorText: err.message };
  }
}

exports.requestWhatsAppOtp = functions.runWith({
  secrets: [
    "WHATSAPP_ACCESS_TOKEN",
    "WHATSAPP_PHONE_NUMBER_ID",
    "OTP_PEPPER",
  ],
}).https.onCall(async (data, context) => {
  const phoneNumber = normalizePhoneNumber(data && data.phoneNumber);
  if (!phoneNumber) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "A valid E.164 phone number is required.",
    );
  }
  if (!isTestPhoneNumber(phoneNumber)) {
    requireAppCheck(context);
  }
  await consumeRateLimit("otp-request-phone", phoneNumber, 5, 60 * 60 * 1000);
  await consumeRateLimit(
      "otp-request-app",
      context.app ? context.app.appId : "emulator",
      30,
      60 * 60 * 1000,
  );

  const otp = crypto.randomInt(100000, 1000000).toString();
  const otpRef = db.collection("whatsapp_otps").doc(stableHash(phoneNumber));
  await otpRef.set({
    phoneNumber,
    otpHash: otpDigest(phoneNumber, otp),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 5 * 60 * 1000),
    attempts: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const accessToken = process.env.WHATSAPP_ACCESS_TOKEN;
  const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  const templateName = process.env.WHATSAPP_TEMPLATE_NAME || "diaspora_auth_otp";
  const templateLang = process.env.WHATSAPP_TEMPLATE_LANG || "en_US";

  // Handle test accounts for App Store / Play Store / QA testing
  if (isTestPhoneNumber(phoneNumber)) {
    console.log(
        `[Test Mode] WhatsApp OTP for ${phoneNumber} is: ${otp} (test bypass: 123456)`,
    );
    // If WhatsApp secrets are configured, also attempt delivery and await it
    if (accessToken && phoneNumberId) {
      try {
        const delivery = await deliverWhatsAppMessage({
          phoneNumberId,
          accessToken,
          recipientPhone: phoneNumber.substring(1),
          otp,
          templateName,
          templateLang,
        });
        console.log(
            `[Test Mode] WhatsApp OTP delivery result for ${phoneNumber}:`,
            delivery,
        );
      } catch (e) {
        console.warn("[Test Mode] Delivery note:", e.message);
      }
    }
    return { success: true, testMode: true, testCode: "123456" };
  }

  if (!accessToken || !phoneNumberId) {
    console.error("WhatsApp OTP secrets are missing");
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Phone verification is not configured.",
    );
  }

  try {
    const delivery = await deliverWhatsAppMessage({
      phoneNumberId,
      accessToken,
      recipientPhone: phoneNumber.substring(1),
      otp,
      templateName,
      templateLang,
    });

    if (!delivery.ok) {
      await otpRef.delete().catch(() => undefined);
      console.error(
          `WhatsApp OTP delivery failed [HTTP ${delivery.status}]:`,
          delivery.errorText,
      );

      // Inspect specific Meta error patterns for clear actionable log messages
      let metaError = null;
      try {
        metaError = JSON.parse(delivery.errorText);
      } catch (_) {}

      const errCode = metaError && metaError.error ?
        metaError.error.code : null;

      if (delivery.status === 401 || errCode === 190) {
        console.error(
            "[WhatsApp Auth CRITICAL] Meta WhatsApp Access Token is expired or unauthorized (code 190). " +
            "Please rotate WHATSAPP_ACCESS_TOKEN in Secret Manager via 'firebase functions:secrets:set WHATSAPP_ACCESS_TOKEN'.",
        );
      } else if (errCode === 131047) {
        console.error(
            "[WhatsApp Auth CRITICAL] Meta rejected free-form text: More than 24 hours have elapsed since the user last responded (code 131047). " +
            "An approved WhatsApp Message Template is required for business-initiated verification. " +
            "Set WHATSAPP_TEMPLATE_NAME in environment/secrets.",
        );
      } else if (errCode === 131030) {
        console.error(
            `[WhatsApp Auth WARNING] Recipient ${phoneNumber} is not in the allowed test recipient list for this WhatsApp sandbox number. ` +
            "Add the phone number under WhatsApp -> API Setup in Meta Developer Console.",
        );
      }

      throw new Error(`delivery rejected: ${delivery.status}`);
    }

    console.log(
        `WhatsApp OTP delivered to ${phoneNumber} via ${delivery.method}`,
    );
    return { success: true };
  } catch (error) {
    await otpRef.delete().catch(() => undefined);
    console.error("WhatsApp OTP delivery failed:", error.message || error);
    throw new functions.https.HttpsError(
        "unavailable",
        "The verification code could not be delivered. Please try again.",
    );
  }
});

exports.verifyWhatsAppOtp = functions.runWith({
  secrets: ["OTP_PEPPER"],
}).https.onCall(async (data, context) => {
  const phoneNumber = normalizePhoneNumber(data && data.phoneNumber);
  const otp = data && String(data.otp || "");
  if (!phoneNumber || !/^\d{6}$/.test(otp)) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "A valid phone number and six-digit code are required.",
    );
  }
  if (!isTestPhoneNumber(phoneNumber)) {
    requireAppCheck(context);
  }

  await consumeRateLimit("otp-verify-phone", phoneNumber, 10, 15 * 60 * 1000);

  // If this is an authorized test phone number, allow fixed master code "123456" or legacy "000000"
  const isTest = isTestPhoneNumber(phoneNumber);
  const isMasterTestCode = isTest && (otp === "123456" || otp === "000000");

  if (!isMasterTestCode) {
    const otpRef = db.collection("whatsapp_otps").doc(stableHash(phoneNumber));
    const suppliedHash = otpDigest(phoneNumber, otp);
    const result = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(otpRef);
      if (!snapshot.exists) return "missing";
      const record = snapshot.data();
      if (!record.expiresAt || record.expiresAt.toMillis() < Date.now()) {
        transaction.delete(otpRef);
        return "expired";
      }
      if (Number(record.attempts || 0) >= 5) {
        transaction.delete(otpRef);
        return "exhausted";
      }
      if (!constantTimeEqual(record.otpHash, suppliedHash)) {
        transaction.update(otpRef, {
          attempts: admin.firestore.FieldValue.increment(1),
        });
        return "invalid";
      }
      transaction.delete(otpRef);
      return "valid";
    });

    if (result !== "valid") {
      const code = result === "expired" ? "deadline-exceeded" :
        result === "exhausted" ? "resource-exhausted" : "unauthenticated";
      throw new functions.https.HttpsError(
          code,
          result === "expired" ? "The verification code has expired." :
            result === "exhausted" ? "Too many failed attempts." :
              "The verification code is invalid.",
      );
    }
  }

  try {
    let userRecord;
    try {
      userRecord = await admin.auth().getUserByPhoneNumber(phoneNumber);
    } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;
      userRecord = await admin.auth().createUser({ phoneNumber });
    }
    const token = await admin.auth().createCustomToken(userRecord.uid);
    return { success: true, token };
  } catch (error) {
    console.error("Firebase token issuance failed", error);
    throw new functions.https.HttpsError(
        "internal",
        "Authentication could not be completed.",
    );
  }
});

/**
 * WhatsApp Cloud API Webhook
 * - GET: Responds to Meta verification challenge (hub.challenge)
 * - POST: Logs delivery statuses (sent, delivered, failed) and error codes
 */
exports.whatsappWebhook = functions.https.onRequest(async (req, res) => {
  if (req.method === "GET") {
    const mode = req.query["hub.mode"];
    const token = req.query["hub.verify_token"];
    const challenge = req.query["hub.challenge"];

    const EXPECTED_TOKEN =
        process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN || "diaspora_webhook_2026";
    if (mode === "subscribe" && token === EXPECTED_TOKEN) {
      console.log("[WhatsApp Webhook] Handshake verified successfully!");
      return res.status(200).send(challenge);
    }
    console.warn(
        "[WhatsApp Webhook] Handshake verification failed. Received token:",
        token,
    );
    return res.status(403).send("Forbidden");
  }

  if (req.method === "POST") {
    try {
      const body = req.body;
      console.log("[WhatsApp Webhook Event]:", JSON.stringify(body));

      if (body && body.entry) {
        for (const entry of body.entry) {
          if (entry.changes) {
            for (const change of entry.changes) {
              const value = change.value;
              if (value && value.statuses) {
                for (const status of value.statuses) {
                  console.log(
                      `[WhatsApp Status] ID: ${status.id}, Status: ${status.status}, Recipient: ${status.recipient_id}`,
                  );
                  if (status.errors && status.errors.length > 0) {
                    console.error(
                        `[WhatsApp Delivery FAILED] Code: ${status.errors[0].code}, Title: ${status.errors[0].title}, Details: ${status.errors[0].error_data ? JSON.stringify(status.errors[0].error_data) : ""}`,
                    );
                  }
                }
              }
            }
          }
        }
      }
      return res.status(200).send("EVENT_RECEIVED");
    } catch (e) {
      console.error("[WhatsApp Webhook Error]:", e.message);
      return res.status(200).send("EVENT_RECEIVED");
    }
  }

  res.status(405).send("Method Not Allowed");
});

