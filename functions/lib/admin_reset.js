/**
 * Admin Database Reset module.
 */
const { functions, admin, db } = require("./shared");

/**
 * ==================================================================
 * 6. ADMIN DATABASE RESET
 * ==================================================================
 */

exports.hardResetDatabase = functions
  .runWith({
    timeoutSeconds: 540,
    memory: '512MB'
  })
  .https.onCall(async (data, context) => {

    // 1. Verify Authentication
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'User must be authenticated to call this function.'
      );
    }

    const callerId = context.auth.uid;
    console.log(`[Admin Reset] Request from user: ${callerId}`);

    // 2. Verify Admin Status (Firestore doc + Auth custom claims fallback)
    // Prevents chicken-and-egg: resetting DB clears isAdmin from user doc
    const callerDoc = await db.collection('users').doc(callerId).get();
    let isCallerAdmin = callerDoc.exists && callerDoc.data().isAdmin === true;

    if (!isCallerAdmin) {
      try {
        const userRecord = await admin.auth().getUser(callerId);
        isCallerAdmin = userRecord.customClaims && userRecord.customClaims.admin === true;
        if (isCallerAdmin && callerDoc.exists) {
          await db.collection('users').doc(callerId).update({ isAdmin: true });
          console.log(`[Admin Reset] Self-healed isAdmin on user doc for ${callerId}`);
        }
      } catch (e) {
        console.log(`[Admin Reset] Custom claims check failed: ${e.message}`);
      }
    }

    if (!isCallerAdmin) {
      console.log(`[Admin Reset] REJECTED: User ${callerId} is not an admin`);
      throw new functions.https.HttpsError(
        'permission-denied',
        'Only administrators can reset the database.'
      );
    }

    console.log(`[Admin Reset] AUTHORIZED: User ${callerId} is admin`);

    // 3. Parse Request
    const resetTargets = data.resetTargets || [];
    const currentUserId = data.currentUserId || callerId;

    console.log(`[Admin Reset] Targets: ${resetTargets.join(', ')}`);
    console.log(`[Admin Reset] Preserving user: ${currentUserId}`);

    const results = {
      success: [],
      failed: []
    };

    /**
     * Helper to delete a collection recursively
     * If excludeDocId is provided, we list documents and delete them individually (except the excluded one),
     * which is slower but safe.
     * If excludeDocId is NOT provided, we nuke the whole collection path efficiently.
     */
    async function deleteCollection(collectionPath, excludeDocId = null) {
      try {
        const collectionRef = db.collection(collectionPath);

        // CASE 1: Full Delete (Faster, simpler)
        if (!excludeDocId) {
          console.log(`[Admin Reset] Recursively deleting entire collection: ${collectionPath}`);
          await db.recursiveDelete(collectionRef);
          return { success: true };
        }

        // CASE 2: Selective Delete (Must preserve one document)
        console.log(`[Admin Reset] Selective delete on ${collectionPath} (preserving ${excludeDocId})`);
        const snapshot = await collectionRef.get(); // Limitation: Reads all docs first. Good for thousands, bad for millions.

        if (snapshot.empty) {
          return { success: true };
        }

        const promises = [];
        const batchSize = 10; // Concurrency limit for recursiveDelete calls
        let currentBatch = [];

        for (const doc of snapshot.docs) {
          if (doc.id === excludeDocId) {
            console.log(`[Admin Reset] Preserving ${collectionPath}/${doc.id}`);
            continue;
          }

          // Add delete promise to batch
          const p = db.recursiveDelete(doc.ref);
          currentBatch.push(p);

          // Execute batch if full
          if (currentBatch.length >= batchSize) {
            await Promise.all(currentBatch);
            currentBatch = [];
          }
        }

        // Execute remaining
        if (currentBatch.length > 0) {
          await Promise.all(currentBatch);
        }

        return { success: true };

      } catch (error) {
        console.error(`[Admin Reset] Error deleting ${collectionPath}:`, error);
        return { success: false, error: error.message };
      }
    }

    /**
     * Helper to process a target with multiple collections
     */
    async function processTarget(targetName, collections) {
      try {
        // Process collections in parallel within a target
        await Promise.all(collections.map(async ({ path, exclude }) => {
          const excludeId = exclude ? currentUserId : null;
          const result = await deleteCollection(path, excludeId);

          if (!result.success) {
            throw new Error(`Failed to delete ${path}: ${result.error}`);
          }
        }));
        results.success.push(targetName);
      } catch (error) {
        console.error(`[Admin Reset] Target ${targetName} failed:`, error);
        results.failed.push({ target: targetName, error: error.message });
      }
    }

    // 4. Process All Targets in Parallel
    await Promise.all(resetTargets.map(async (target) => {
      switch (target) {
        case 'users':
          await processTarget('users', [
            { path: 'users', exclude: true },
            { path: 'trust_data', exclude: true },
            { path: 'id_verification_requests', exclude: false },
            { path: 'interest_registrations', exclude: false },
            { path: 'qr_exchanges', exclude: false },
            { path: 'vouches', exclude: false },
            { path: 'trust_ratings', exclude: false },
            { path: 'field_verifications', exclude: false },
            { path: 'relationship_requests', exclude: false },
            { path: 'proximity_history', exclude: false },
            { path: 'proximity-notifications', exclude: false }
          ]);
          break;

        case 'communities':
          await processTarget('communities', [
            { path: 'communities', exclude: false },
            { path: 'governance', exclude: false },
            { path: 'governance_votes', exclude: false },
            { path: 'governance_history', exclude: false }
          ]);
          break;

        case 'events':
          await processTarget('events', [
            { path: 'events', exclude: false },
            { path: 'check_ins', exclude: false }
          ]);
          break;

        case 'organizations':
          await processTarget('organizations', [
            { path: 'organizations', exclude: false }
          ]);
          break;

        case 'radio':
          await processTarget('radio', [
            { path: 'radio_station_health', exclude: false } // Fixed name
          ]);
          break;

        case 'chats':
          // Delete Firestore chat collections (top-level)
          await processTarget('chats', [
            { path: 'chats', exclude: false },
            { path: 'reports', exclude: false },
            { path: 'discoverableChats', exclude: false }
          ]);
          // Delete userChats subcollections under each user
          try {
            const usersSnap = await db.collection('users').get();
            const userChatDeletes = usersSnap.docs.map(async (userDoc) => {
              const userChatsRef = db.collection('users').doc(userDoc.id).collection('userChats');
              const userChatsSnap = await userChatsRef.get();
              if (!userChatsSnap.empty) {
                await db.recursiveDelete(userChatsRef);
                console.log(`[Admin Reset] Deleted userChats for user ${userDoc.id}`);
              }
            });
            await Promise.all(userChatDeletes);
            results.success.push('userChats');
            console.log('[Admin Reset] Deleted all userChats subcollections');
          } catch (error) {
            console.error('[Admin Reset] Error deleting userChats:', error);
            results.failed.push({ target: 'userChats', error: error.message });
          }
          break;

        case 'points':
          await processTarget('points', [
            { path: 'points_transactions', exclude: false },
            { path: 'referral_codes', exclude: false },
            { path: 'system_stats', exclude: false },
            { path: 'user_points', exclude: false }
          ]);
          break;

        case 'storage':
          // Delete Firebase Storage files
          try {
            const bucket = admin.storage().bucket();
            const folders = [
              'profile_photos/',
              'community_headers/',
              'chat_voices/',
              'chat_images/',
              'chat_videos/',
              'chat_documents/',
              'event_images/'
            ];

            await Promise.all(folders.map(async (folder) => {
              await bucket.deleteFiles({ prefix: folder });
              console.log(`[Admin Reset] Deleted files in ${folder}`);
            }));

            results.success.push('storage');
          } catch (error) {
            console.error('[Admin Reset] Error deleting storage:', error);
            results.failed.push({ target: 'storage', error: error.message });
          }
          break;

        case 'feedback':
          await processTarget('feedback', [
            { path: 'feedback', exclude: false }
          ]);
          break;

        case 'proximity':
          await processTarget('proximity', [
            { path: 'proximity_history', exclude: false },
            { path: 'proximity-notifications', exclude: false }
          ]);
          break;

        case 'corridors':
          await processTarget('corridors', [
            { path: 'corridors', exclude: false }
          ]);
          break;

        case 'hosting':
          await processTarget('hosting', [
            { path: 'hosting_requests', exclude: false },
            { path: 'hosting_sessions', exclude: false }
          ]);
          break;

        case 'marketplace':
          await processTarget('marketplace', [
            { path: 'marketplace_listings', exclude: false }
          ]);
          // Delete saved_listings subcollections under each user
          try {
            const usersSnapMkt = await db.collection('users').get();
            const savedListingDeletes = usersSnapMkt.docs.map(async (userDoc) => {
              const savedRef = db.collection('users').doc(userDoc.id).collection('saved_listings');
              const savedSnap = await savedRef.get();
              if (!savedSnap.empty) {
                await db.recursiveDelete(savedRef);
                console.log(`[Admin Reset] Deleted saved_listings for user ${userDoc.id}`);
              }
            });
            await Promise.all(savedListingDeletes);
            console.log('[Admin Reset] Deleted all saved_listings subcollections');
          } catch (error) {
            console.error('[Admin Reset] Error deleting saved_listings:', error);
            results.failed.push({ target: 'saved_listings', error: error.message });
          }
          break;

        case 'peer_listings':
          await processTarget('peer_listings', [
            { path: 'peer_listings', exclude: false },
            { path: 'peer_bookings', exclude: false }
          ]);
          break;

        case 'trust':
          await processTarget('trust', [
            { path: 'trust_data', exclude: false },
            { path: 'trust_ratings', exclude: false },
            { path: 'vouches', exclude: false },
            { path: 'field_verifications', exclude: false }
          ]);
          break;

        default:
          console.log(`[Admin Reset] Unknown target: ${target}`);
          results.failed.push({ target, error: 'Unknown target' });
      }
    }));

    console.log(`[Admin Reset] COMPLETE. Success: ${results.success.length}, Failed: ${results.failed.length}`);

    return {
      success: results.success,
      failed: results.failed
    };
  });

/**
 * ==================================================================
 * 7. SET ADMIN CLAIM
 * ==================================================================
 * Sets Firebase Auth custom claims + Firestore isAdmin flag.
 * Bootstrap: If no admin exists yet, the caller becomes the first admin.
 * After bootstrap: Only existing admins can grant admin to others.
 */
exports.setAdminClaim = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated.');
  }

  const callerId = context.auth.uid;
  const targetUid = data.targetUid || callerId; // Default: grant to self

  // Check if ANY admin exists (for bootstrap)
  const callerRecord = await admin.auth().getUser(callerId);
  const callerIsAdmin = callerRecord.customClaims && callerRecord.customClaims.admin === true;

  // Also check Firestore
  const callerDoc = await db.collection('users').doc(callerId).get();
  const callerIsAdminFirestore = callerDoc.exists && callerDoc.data().isAdmin === true;

  if (!callerIsAdmin && !callerIsAdminFirestore) {
    // Bootstrap mode: Check if ANY user has admin claim. If not, allow first admin.
    const allUsers = await db.collection('users').where('isAdmin', '==', true).limit(1).get();
    if (!allUsers.empty) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Only existing admins can grant admin privileges.'
      );
    }
    console.log(`[Admin] Bootstrap mode: No admins exist. Granting to ${callerId}`);
  }

  // Set custom claim on target
  await admin.auth().setCustomUserClaims(targetUid, { admin: true });

  // Set isAdmin on Firestore user doc
  const targetDoc = db.collection('users').doc(targetUid);
  const targetSnapshot = await targetDoc.get();
  if (targetSnapshot.exists) {
    await targetDoc.update({ isAdmin: true });
  }

  // If bootstrapping, also set on caller
  if (targetUid !== callerId && !callerIsAdmin) {
    await admin.auth().setCustomUserClaims(callerId, { admin: true });
    if (callerDoc.exists) {
      await db.collection('users').doc(callerId).update({ isAdmin: true });
    }
  }

  console.log(`[Admin] Admin claim set for user ${targetUid} by ${callerId}`);
  return { success: true, targetUid };
});
