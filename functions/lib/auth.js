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

exports.requestWhatsAppOtp = functions.runWith({
  secrets: [
    "WHATSAPP_ACCESS_TOKEN",
    "WHATSAPP_PHONE_NUMBER_ID",
    "OTP_PEPPER",
  ],
}).https.onCall(async (data, context) => {
  requireAppCheck(context);
  const phoneNumber = normalizePhoneNumber(data && data.phoneNumber);
  if (!phoneNumber) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "A valid E.164 phone number is required.",
    );
  }
  await consumeRateLimit("otp-request-phone", phoneNumber, 5, 60 * 60 * 1000);
  await consumeRateLimit(
      "otp-request-app",
      context.app ? context.app.appId : "emulator",
      30,
      60 * 60 * 1000,
  );

  const accessToken = process.env.WHATSAPP_ACCESS_TOKEN;
  const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  if (!accessToken || !phoneNumberId) {
    console.error("WhatsApp OTP secrets are missing");
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Phone verification is not configured.",
    );
  }

  const otp = crypto.randomInt(100000, 1000000).toString();
  const otpRef = db.collection("whatsapp_otps").doc(stableHash(phoneNumber));
  await otpRef.set({
    phoneNumber,
    otpHash: otpDigest(phoneNumber, otp),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 5 * 60 * 1000),
    attempts: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  try {
    const response = await fetch(
        `https://graph.facebook.com/v20.0/${phoneNumberId}/messages`,
        {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            messaging_product: "whatsapp",
            recipient_type: "individual",
            to: phoneNumber.substring(1),
            type: "text",
            text: {
              preview_url: false,
              body: `Your Diaspora Nearby verification code is: ${otp}`,
            },
          }),
        },
    );
    if (!response.ok) {
      await otpRef.delete();
      console.error("WhatsApp rejected an OTP delivery request", response.status);
      throw new Error("delivery rejected");
    }
    return { success: true };
  } catch (error) {
    await otpRef.delete().catch(() => undefined);
    console.error("WhatsApp OTP delivery failed", error);
    throw new functions.https.HttpsError(
        "unavailable",
        "The verification code could not be delivered. Please try again.",
    );
  }
});

exports.verifyWhatsAppOtp = functions.runWith({
  secrets: ["OTP_PEPPER"],
}).https.onCall(async (data, context) => {
  requireAppCheck(context);
  const phoneNumber = normalizePhoneNumber(data && data.phoneNumber);
  const otp = data && String(data.otp || "");
  if (!phoneNumber || !/^\d{6}$/.test(otp)) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "A valid phone number and six-digit code are required.",
    );
  }

  await consumeRateLimit("otp-verify-phone", phoneNumber, 10, 15 * 60 * 1000);
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
