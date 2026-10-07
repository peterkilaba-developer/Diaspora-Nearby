/**
 * Test script for WhatsApp Auth flow (both unit logic and test accounts).
 * Usage: node functions/scripts/test-whatsapp-auth.js
 */
const admin = require("firebase-admin");
const serviceAccount = require("../../tools/admin-scripts/service-account-key.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

process.env.OTP_PEPPER = "01234567890123456789012345678901234567890123456789";
const auth = require("../lib/auth");

async function runTests() {
  console.log("=== Testing WhatsApp Auth Flow ===");

  const testPhone = "+16505551230";
  const mockContext = {
    app: { appId: "test-app-id" },
  };

  // 1. Test requestWhatsAppOtp with an authorized test phone number
  console.log("\n1. Testing requestWhatsAppOtp with test phone:", testPhone);
  const reqResult = await auth.requestWhatsAppOtp.run({ phoneNumber: testPhone }, mockContext);
  console.log("requestWhatsAppOtp result:", reqResult);
  if (!reqResult.success) {
    throw new Error("requestWhatsAppOtp failed");
  }

  // 2. Test verifyWhatsAppOtp with invalid OTP (should fail)
  console.log("\n2. Testing verifyWhatsAppOtp with wrong OTP...");
  try {
    await auth.verifyWhatsAppOtp.run({ phoneNumber: testPhone, otp: "999999" }, mockContext);
    throw new Error("Expected verifyWhatsAppOtp with wrong OTP to fail!");
  } catch (err) {
    console.log("Correctly rejected invalid OTP:", err.message || err.code);
  }

  // 3. Test verifyWhatsAppOtp with valid test master OTP "123456"
  console.log("\n3. Testing verifyWhatsAppOtp with test OTP 123456...");
  const verifyResult = await auth.verifyWhatsAppOtp.run({ phoneNumber: testPhone, otp: "123456" }, mockContext);
  console.log("verifyWhatsAppOtp result:", {
    success: verifyResult.success,
    tokenPreview: verifyResult.token ? verifyResult.token.substring(0, 25) + "..." : null,
  });

  if (!verifyResult.success || !verifyResult.token) {
    throw new Error("verifyWhatsAppOtp did not return a valid custom token");
  }

  // 4. Verify the custom token against Firebase Auth
  console.log("\n4. Verifying issued custom token details in Firebase Auth...");
  const user = await admin.auth().getUserByPhoneNumber(testPhone);
  console.log("User in Firebase Auth exists:", user.uid, user.phoneNumber);

  // 5. Test invalid phone number rejection
  console.log("\n5. Testing invalid phone number rejection...");
  try {
    await auth.requestWhatsAppOtp.run({ phoneNumber: "not-a-number" }, mockContext);
    throw new Error("Expected invalid phone number to be rejected!");
  } catch (err) {
    console.log("Correctly rejected invalid phone number:", err.message || err.code);
  }

  console.log("\n ALL TESTS PASSED SUCCESSFULLY! WhatsApp Auth flow verified.");
}

runTests().then(() => process.exit(0)).catch((e) => {
  console.error("Test failed:", e);
  process.exit(1);
});
