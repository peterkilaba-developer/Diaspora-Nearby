const { functions, admin, db } = require("./shared");
const crypto = require("crypto");

/**
 * Generate a 6 digit numeric OTP
 */
function generateOTP() {
    return Math.floor(100000 + Math.random() * 900000).toString();
}

/**
 * requestWhatsAppOtp
 * 
 * Takes an E.164 phone number, generates a 6-digit OTP, saves it to Firestore 
 * with a 5-minute expiration, and uses the WhatsApp Cloud API to send it.
 */
exports.requestWhatsAppOtp = functions.runWith({ secrets: ["WHATSAPP_ACCESS_TOKEN", "WHATSAPP_PHONE_NUMBER_ID"] }).https.onCall(async (data, context) => {
    // Optionally enforce App Check here if needed
    // if (context.app == undefined) {
    //     throw new functions.https.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    // }

    const phoneNumber = data.phoneNumber;
    if (!phoneNumber || !phoneNumber.startsWith("+")) {
        throw new functions.https.HttpsError("invalid-argument", "Valid E.164 phone number required.");
    }

    // Read secrets from environment variables (set via Firebase Secret Manager)
    const WHATSAPP_ACCESS_TOKEN = process.env.WHATSAPP_ACCESS_TOKEN;
    const WHATSAPP_PHONE_NUMBER_ID = process.env.WHATSAPP_PHONE_NUMBER_ID;

    if (!WHATSAPP_ACCESS_TOKEN || !WHATSAPP_PHONE_NUMBER_ID) {
        console.error("Missing WhatsApp secrets. Ensure WHATSAPP_ACCESS_TOKEN and WHATSAPP_PHONE_NUMBER_ID are set.");
        throw new functions.https.HttpsError("internal", "WhatsApp configuration missing.");
    }

    const otp = generateOTP();
    const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + 5 * 60 * 1000); // 5 minutes

    // Save to Firestore
    await db.collection("whatsapp_otps").doc(phoneNumber).set({
        otp: otp,
        expiresAt: expiresAt,
        attempts: 0
    });

    // Send via WhatsApp Cloud API
    // Note: In production, WhatsApp requires you to use an approved "Message Template" for business-initiated conversations.
    // We attempt an authentication template or text message here.
    
    // Strip the '+' for the WhatsApp API 'to' field
    const toPhone = phoneNumber.substring(1); 

    try {
        const response = await fetch(`https://graph.facebook.com/v20.0/${WHATSAPP_PHONE_NUMBER_ID}/messages`, {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${WHATSAPP_ACCESS_TOKEN}`,
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                messaging_product: "whatsapp",
                recipient_type: "individual",
                to: toPhone,
                type: "text",
                text: {
                    preview_url: false,
                    body: `Your Diaspora Nearby verification code is: ${otp}`
                }
            })
        });

        const result = await response.json();
        
        if (!response.ok) {
            console.error("WhatsApp API Error:", result);
            // --- TEMPORARY BYPASS ---
            // If the Meta token expires during testing, don't crash the app. 
            // Just pretend it succeeded so the user can enter the 000000 master code.
            console.warn("Swallowing WhatsApp error for testing so we can reach the OTP screen.");
            return { success: true };
        }

        console.log(`WhatsApp OTP sent to ${phoneNumber}`);
        return { success: true };

    } catch (e) {
        console.error("Error sending WhatsApp message:", e);
        // --- TEMPORARY BYPASS ---
        console.warn("Swallowing WhatsApp error for testing so we can reach the OTP screen.");
        return { success: true };
    }
});

/**
 * verifyWhatsAppOtp
 * 
 * Verifies the OTP provided by the user. If valid, generates a Firebase Custom Token
 * and returns it to the client to sign in.
 */
exports.verifyWhatsAppOtp = functions.https.onCall(async (data, context) => {
    const phoneNumber = data.phoneNumber;
    // We don't actually need to verify OTP if we sent "hello_world" for test, 
    // but we will verify it against Firestore anyway (the user won't receive the actual code yet until template is fixed).
    // For now we will accept "000000" as a master bypass for development since we are using hello_world.
    const otp = data.otp;

    if (!phoneNumber || !otp) {
        throw new functions.https.HttpsError("invalid-argument", "Phone number and OTP required.");
    }

    // --- TEMPORARY BYPASS ---
    // Because Meta only allows 'hello_world' out of the box, we can't send the real code via WhatsApp until an auth template is approved.
    // So if the user enters 000000, we let them through.
    let isValid = false;
    
    if (otp === "000000") {
        isValid = true;
    } else {
        const docRef = db.collection("whatsapp_otps").doc(phoneNumber);
        const doc = await docRef.get();

        if (!doc.exists) {
            throw new functions.https.HttpsError("not-found", "No pending verification found for this number.");
        }

        const record = doc.data();

        // Check expiration
        if (record.expiresAt.toMillis() < Date.now()) {
            await docRef.delete();
            throw new functions.https.HttpsError("deadline-exceeded", "Verification code has expired.");
        }

        // Check max attempts
        if (record.attempts >= 5) {
            await docRef.delete();
            throw new functions.https.HttpsError("resource-exhausted", "Too many failed attempts. Please request a new code.");
        }

        // Verify OTP
        if (record.otp !== otp) {
            await docRef.update({ attempts: admin.firestore.FieldValue.increment(1) });
            throw new functions.https.HttpsError("unauthenticated", "Invalid verification code.");
        }

        isValid = true;
        await docRef.delete();
    }

    if (!isValid) {
        throw new functions.https.HttpsError("unauthenticated", "Invalid verification code.");
    }

    try {
        // Mint a Custom Auth Token for this phone number
        let uid;
        try {
            const userRecord = await admin.auth().getUserByPhoneNumber(phoneNumber);
            uid = userRecord.uid;
        } catch (e) {
            if (e.code === 'auth/user-not-found') {
                // Create a new user with this phone number
                const newUser = await admin.auth().createUser({
                    phoneNumber: phoneNumber
                });
                uid = newUser.uid;
            } else {
                throw e;
            }
        }

        const customToken = await admin.auth().createCustomToken(uid);
        
        return { 
            success: true, 
            token: customToken 
        };
    } catch (e) {
        console.error("Error generating custom token:", e);
        throw new functions.https.HttpsError("internal", "Failed to generate authentication token.");
    }
});
// force redeploy 5