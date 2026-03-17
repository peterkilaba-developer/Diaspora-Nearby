/**
 * Stripe Payments module.
 * Emergency Fund checkout and webhook handling.
 */
const { functions, admin, db, sendPushToUser } = require("./shared");

/**
 * ==================================================================
 * STRIPE – EMERGENCY FUND CONTRIBUTION ($100)
 * ==================================================================
 */

// Lazy-init Stripe to avoid errors during deploy analysis
let _stripe = null;
function getStripe() {
  if (!_stripe) {
    _stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);
  }
  return _stripe;
}
const STRIPE_PRICE_ID = process.env.STRIPE_PRICE_ID || 'price_1T6tvlI1F9UMWfaW1rahjlAV';

/**
 * Callable: createEmergencyFundCheckout
 * Creates a Stripe PaymentIntent for the $100 annual contribution.
 * Returns clientSecret + ephemeralKey + customerId for the in-app Payment Sheet.
 */
exports.createEmergencyFundCheckout = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const userId = context.auth.uid;
  const email = data.email || null;
  const stripe = getStripe();

  try {
    // 1. Create or retrieve Stripe Customer
    let customerId;
    const userDoc = await db.collection('stripe_customers').doc(userId).get();

    if (userDoc.exists && userDoc.data().customerId) {
      customerId = userDoc.data().customerId;
    } else {
      const customer = await stripe.customers.create({
        email: email,
        metadata: { firebaseUid: userId },
      });
      customerId = customer.id;
      await db.collection('stripe_customers').doc(userId).set({
        customerId: customerId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // 2. Create Ephemeral Key for the customer
    const ephemeralKey = await stripe.ephemeralKeys.create(
      { customer: customerId },
      { apiVersion: '2024-12-18.acacia' }
    );

    // 3. Create PaymentIntent for $100
    const paymentIntent = await stripe.paymentIntents.create({
      amount: 10000, // $100.00 in cents
      currency: 'usd',
      customer: customerId,
      // Business name — appears on customer bank/card statements
      statement_descriptor: 'DIASPORA NEARBY',
      statement_descriptor_suffix: 'EMERGENCY FUND',
      description: 'Diaspora Nearby – Community Emergency Fund Annual Contribution',
      metadata: {
        userId: userId,
        product: 'emergency_fund_contribution',
        poctIncentive: '10',
      },
      automatic_payment_methods: { enabled: true },
    });

    console.log(`[Stripe] PaymentIntent created for user ${userId}: ${paymentIntent.id}`);

    return {
      paymentIntentClientSecret: paymentIntent.client_secret,
      ephemeralKey: ephemeralKey.secret,
      customerId: customerId,
      publishableKey: process.env.STRIPE_PUBLISHABLE_KEY || '',
    };
  } catch (error) {
    console.error(`[Stripe] Failed to create payment intent:`, error);
    throw new functions.https.HttpsError('internal', `Stripe error: ${error.message}`);
  }
});

/**
 * HTTP Endpoint: stripeEmergencyFundWebhook
 * Handles Stripe webhook events for emergency fund payments.
 * On successful payment:
 *   1. Activates the membership
 *   2. Updates staker status to 'contributed'
 *   3. Awards +10 PoCT
 */
exports.stripeEmergencyFundWebhook = functions.https.onRequest(async (req, res) => {
  // Only accept POST
  if (req.method !== 'POST') {
    res.status(405).send('Method Not Allowed');
    return;
  }

  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
  let event;

  try {
    if (webhookSecret) {
      // Verify webhook signature (production)
      const sig = req.headers['stripe-signature'];
      event = getStripe().webhooks.constructEvent(req.rawBody, sig, webhookSecret);
    } else {
      // No secret configured — parse directly (test mode)
      event = req.body;
      console.warn('[Stripe Webhook] No STRIPE_WEBHOOK_SECRET set — skipping signature verification.');
    }
  } catch (err) {
    console.error(`[Stripe Webhook] Signature verification failed:`, err.message);
    res.status(400).send(`Webhook Error: ${err.message}`);
    return;
  }

  // Handle payment events
  if (event.type === 'checkout.session.completed' || event.type === 'payment_intent.succeeded') {
    const eventObj = event.data.object;
    // Get userId from metadata (PaymentIntent) or client_reference_id (Checkout Session)
    const userId = (eventObj.metadata && eventObj.metadata.userId)
      || eventObj.client_reference_id;

    if (!userId) {
      console.error('[Stripe Webhook] No userId found in event');
      res.status(400).send('Missing userId');
      return;
    }

    // Determine amount and paymentId based on event type
    const amountCents = eventObj.amount || eventObj.amount_total || 10000;
    const paymentId = eventObj.id || eventObj.payment_intent;

    console.log(`[Stripe Webhook] Payment completed for user ${userId} (${event.type})`);

    try {
      const batch = db.batch();

      // 1. Activate membership
      const membershipRef = db.collection('emergency_fund_memberships').doc(userId);
      batch.set(membershipRef, {
        status: 'active',
        isBetaAccess: false,
        paidAmount: amountCents / 100, // cents → dollars
        paymentId: paymentId,
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
        nextPaymentDate: admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + 365 * 24 * 60 * 60 * 1000)
        ),
      }, { merge: true });

      // 2. Update staker status
      const stakerRef = db.collection('emergency_fund_stakers').doc(userId);
      batch.set(stakerRef, {
        status: 'contributed',
        contributedAt: admin.firestore.FieldValue.serverTimestamp(),
        paymentId: paymentId,
      }, { merge: true });

      // 3. Award +10 PoCT incentive
      const trustRef = db.collection('trust_scores').doc(userId);
      const trustDoc = await trustRef.get();
      const currentPoct = trustDoc.exists ? (trustDoc.data().poct || 0) : 0;
      batch.set(trustRef, {
        poct: currentPoct + 10,
        lastPoctAwardReason: 'emergency_fund_contribution',
        lastPoctAwardAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      await batch.commit();

      console.log(`[Stripe Webhook] ✅ User ${userId} membership activated, +10 PoCT awarded`);
    } catch (error) {
      console.error(`[Stripe Webhook] Error processing payment for ${userId}:`, error);
      res.status(500).send(`Processing error: ${error.message}`);
      return;
    }
  }

  res.status(200).json({ received: true });
});
