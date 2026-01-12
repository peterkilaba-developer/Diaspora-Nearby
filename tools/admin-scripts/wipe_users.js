const admin = require('firebase-admin');

// Service Account Key Path
// UPDATE THIS PATH to point to your downloaded service account JSON file
const serviceAccount = require('./service-account-key.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: "https://diaspora-nearby-a3dac-default-rtdb.firebaseio.com"
});

const db = admin.firestore();
const rtdb = admin.database();

// ---------------------------------------------------------
// Helper: Delete RTDB Node
async function deleteRtdbNode(path) {
  try {
    await rtdb.ref(path).remove();
    console.log(`Cleared RTDB node: ${path}`);
  } catch (error) {
    console.error(`Error clearing RTDB node ${path}:`, error);
  }
}
// ---------------------------------------------------------
// Helper: Delete all documents in a collection
async function deleteCollection(collectionPath, batchSize) {
  const collectionRef = db.collection(collectionPath);
  const query = collectionRef.orderBy('__name__').limit(batchSize);

  return new Promise((resolve, reject) => {
    deleteQueryBatch(db, query, resolve).catch(reject);
  });
}

async function deleteQueryBatch(db, query, resolve) {
  const snapshot = await query.get();

  const batchSize = snapshot.size;
  if (batchSize === 0) {
    // When there are no documents left, we are done
    resolve();
    return;
  }

  const batch = db.batch();
  snapshot.docs.forEach((doc) => {
    batch.delete(doc.ref);
  });
  await batch.commit();

  // Recurse on the next process tick, to avoid
  // exploding the stack.
  process.nextTick(() => {
    deleteQueryBatch(db, query, resolve);
  });
}
// ---------------------------------------------------------

async function wipeAllUsers(nextPageToken) {
  // PART 1: Wipe Auth Users and their direct data match
  const listUsersResult = await admin.auth().listUsers(1000, nextPageToken);

  const users = listUsersResult.users;
  if (users.length > 0) {
    console.log(`Found ${users.length} Auth users... Deleting auth + data...`);
    const deletePromises = users.map(async (user) => {
      try {
        await db.collection('users').doc(user.uid).delete();
        await db.collection('user_points').doc(user.uid).delete();
        await admin.auth().deleteUser(user.uid);
        console.log(`Deleted user: ${user.uid}`);
      } catch (error) {
        console.error(`Error deleting user ${user.uid}:`, error);
      }
    });
    await Promise.all(deletePromises);

    // Recurse for Auth
    if (listUsersResult.pageToken) {
      await wipeAllUsers(listUsersResult.pageToken);
      return; // Don't proceed to orphan wipe until auth is done
    }
  } else {
    console.log('No Auth users found.');
  }

  // PART 2: Sweep Orphaned Data (Run once after Auth clear)
  if (!nextPageToken) {
    console.log('--- Starting Orphaned Data Sweep ---');
    console.log('Clearing users collection...');
    await deleteCollection('users', 500);

    console.log('Clearing user_points collection...');
    await deleteCollection('user_points', 500);

    console.log('Clearing points_transactions collection...');
    await deleteCollection('points_transactions', 500);

    console.log('Clearing proximity-notifications collection...');
    await deleteCollection('proximity-notifications', 500);

    console.log('Clearing referral_codes collection...');
    await deleteCollection('referral_codes', 500);

    console.log('Clearing radio_station_health collection...');
    await deleteCollection('radio_station_health', 500);

    console.log('--- Starting RTDB Wipe ---');
    await deleteRtdbNode('chats');
    await deleteRtdbNode('userChats');
    await deleteRtdbNode('messages');
    await deleteRtdbNode('lastRead'); // [NEW] From screenshot
    await deleteRtdbNode('onlineStatus');

    console.log('Orphaned data sweep + RTDB wipe complete.');
  }
}

// Start the process
wipeAllUsers()
  .then(() => {
    console.log('Done.');
    process.exit(0);
  })
  .catch((error) => {
    console.error('Fatal Error:', error);
    process.exit(1);
  });
