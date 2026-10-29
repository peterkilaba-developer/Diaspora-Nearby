/**
 * Stripe Payments module.
 * Emergency Fund checkout and webhook handling.
 */
const { functions, admin, db, sendPushToUser } = require("./shared");
const { requireAuth, requireAppCheck, consumeRateLimit } = require("./security");
const { syncProfileMilestoneAndTrust } = require("./dsp");

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
exports.createEmergencyFundCheckout = functions
  .runWith({ secrets: ["STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET"] })
  .https.onCall(async (data, context) => {
  requireAppCheck(context);
  const userId = requireAuth(context);
  const [, authUser] = await Promise.all([
    consumeRateLimit("emergency-checkout", userId, 10, 60 * 60 * 1000),
    admin.auth().getUser(userId),
  ]);
  const email = authUser.email || null;
  const stripe = getStripe();
  const checkoutLockRef = db.collection('payment_checkout_locks').doc(userId);

  try {
    // Serialize checkout creation. Without this lock, parallel retries can
    // create several payable intents before the first webhook activates the
    // annual membership.
    await db.runTransaction(async (transaction) => {
      const membershipRef = db.collection('emergency_fund_memberships').doc(userId);
      const [membership, lock] = await Promise.all([
        transaction.get(membershipRef),
        transaction.get(checkoutLockRef),
      ]);
      const now = Date.now();
      const nextPayment = membership.exists && membership.data().nextPaymentDate;
      if (membership.exists && membership.data().status === 'active' &&
          nextPayment && nextPayment.toMillis() > now) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Your annual contribution is already active.',
        );
      }
      const lockedUntil = lock.exists && lock.data().lockedUntil;
      if (lockedUntil && lockedUntil.toMillis() > now) {
        throw new functions.https.HttpsError(
          'aborted',
          'A payment setup is already in progress.',
        );
      }
      transaction.set(checkoutLockRef, {
        lockedUntil: admin.firestore.Timestamp.fromMillis(now + 30 * 60 * 1000),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

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

    // 2. Create Ephemeral Key & PaymentIntent for $100 in parallel
    const [ephemeralKey, paymentIntent] = await Promise.all([
      stripe.ephemeralKeys.create(
        { customer: customerId },
        { apiVersion: '2024-12-18.acacia' }
      ),
      stripe.paymentIntents.create({
        amount: 10000, // $100.00 in cents
        currency: 'usd',
        customer: customerId,
        // Business name — appears on customer bank/card statements
        statement_descriptor: 'DIASPORA NEARBY',
        statement_descriptor_suffix: 'EMERGENCY FUND',
        description: 'Diaspora Nearby – Ubuntu Emergency Fund Annual Contribution',
        metadata: {
          userId: userId,
          product: 'emergency_fund_contribution',
          pctIncentive: '10',
        },
        automatic_payment_methods: { enabled: true },
      }),
    ]);
    await checkoutLockRef.set({ paymentIntentId: paymentIntent.id }, { merge: true });

    console.log(`[Stripe] PaymentIntent created for user ${userId}: ${paymentIntent.id}`);

    return {
      paymentIntentClientSecret: paymentIntent.client_secret,
      ephemeralKey: ephemeralKey.secret,
      customerId: customerId,
      publishableKey: process.env.STRIPE_PUBLISHABLE_KEY || '',
    };
  } catch (error) {
    if (!(error instanceof functions.https.HttpsError)) {
      await checkoutLockRef.delete().catch(() => undefined);
    }
    if (error instanceof functions.https.HttpsError) throw error;
    console.error(`[Stripe] Failed to create payment intent:`, error);
    throw new functions.https.HttpsError('internal', 'Payment setup failed.');
  }
});

/**
 * HTTP Endpoint: stripeEmergencyFundWebhook
 * Handles Stripe webhook events for emergency fund payments.
 * On successful payment:
 *   1. Activates the membership
 *   2. Updates staker status to 'contributed'
 *   3. Awards +10 PCT
 */
exports.stripeEmergencyFundWebhook = functions
  .runWith({ secrets: ["STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET"] })
  .https.onRequest(async (req, res) => {
  // Only accept POST
  if (req.method !== 'POST') {
    res.status(405).send('Method Not Allowed');
    return;
  }

  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
  let event;

  try {
    if (!webhookSecret) throw new Error('Webhook signing is not configured');
    const sig = req.headers['stripe-signature'];
    if (!sig) throw new Error('Missing Stripe signature');
    event = getStripe().webhooks.constructEvent(req.rawBody, sig, webhookSecret);
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
    const amountCents = Number(eventObj.amount || eventObj.amount_total);
    const paymentId = eventObj.payment_intent || eventObj.id;

    const currency = String(eventObj.currency || "").toLowerCase();
    const product = eventObj.metadata && eventObj.metadata.product;
    if (typeof paymentId !== "string" || paymentId.length > 255 ||
        amountCents !== 10000 || currency !== "usd" ||
        product !== "emergency_fund_contribution") {
      console.error(`[Stripe Webhook] Rejected invalid payment ${paymentId}`);
      res.status(400).send("Unexpected payment details");
      return;
    }

    console.log(`[Stripe Webhook] Payment completed for user ${userId} (${event.type})`);

    try {
      await db.runTransaction(async (transaction) => {
        const eventRef = db.collection('stripe_webhook_events').doc(event.id);
        const paymentRef = db.collection('stripe_processed_payments').doc(paymentId);
        const [eventSnapshot, paymentSnapshot] = await Promise.all([
          transaction.get(eventRef),
          transaction.get(paymentRef),
        ]);
        if (eventSnapshot.exists || paymentSnapshot.exists) return;

        const membershipRef = db.collection('emergency_fund_memberships').doc(userId);
        transaction.set(membershipRef, {
          status: 'active',
          isBetaAccess: false,
          paidAmount: amountCents / 100,
          paymentId,
          paidAt: admin.firestore.FieldValue.serverTimestamp(),
          nextPaymentDate: admin.firestore.Timestamp.fromDate(
            new Date(Date.now() + 365 * 24 * 60 * 60 * 1000)
          ),
        }, { merge: true });

        const stakerRef = db.collection('emergency_fund_stakers').doc(userId);
        transaction.set(stakerRef, {
          status: 'contributed',
          contributedAt: admin.firestore.FieldValue.serverTimestamp(),
          paymentId,
        }, { merge: true });

        for (const col of ['trust_data', 'trust_scores']) {
          const trustRef = db.collection(col).doc(userId);
          transaction.set(trustRef, {
            emergencyFundContributor: true,
            lastPctAwardReason: 'emergency_fund_contribution', lastPoctAwardReason: 'emergency_fund_contribution',
            lastPctAwardAt: admin.firestore.FieldValue.serverTimestamp(), lastPoctAwardAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        }
        transaction.create(paymentRef, {
          userId,
          eventId: event.id,
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        transaction.create(eventRef, {
          type: event.type,
          userId,
          paymentId,
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        transaction.delete(db.collection('payment_checkout_locks').doc(userId));
      });

      try {
        await syncProfileMilestoneAndTrust(userId);
      } catch (syncErr) {
        console.warn(`[Stripe Webhook] syncProfileMilestoneAndTrust warning: ${syncErr.message}`);
      }

      console.log(`[Stripe Webhook] ✅ User ${userId} membership activated, +10 PCT awarded`);
    } catch (error) {
      console.error(`[Stripe Webhook] Error processing payment for ${userId}:`, error);
      res.status(500).send('Processing error');
      return;
    }
  }

  res.status(200).json({ received: true });
});
