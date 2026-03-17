/**
 * One-time script: Set admin claim on a Firebase Auth user.
 * Usage: node scripts/set-admin.js
 */
const admin = require('firebase-admin');

// Initialize with default credentials (uses GOOGLE_APPLICATION_CREDENTIALS or gcloud auth)
admin.initializeApp();

async function setAdmin() {
    const db = admin.firestore();

    // Find all users and list them
    const usersSnap = await db.collection('users').get();
    console.log(`Found ${usersSnap.size} users:\n`);

    for (const doc of usersSnap.docs) {
        const data = doc.data();
        const phone = data.phoneNumber || data.phone || 'no phone';
        const name = data.fullName || data.name || 'unnamed';
        const isAdmin = data.isAdmin;
        console.log(`  UID: ${doc.id} | Name: ${name} | Phone: ${phone} | isAdmin: ${isAdmin}`);
    }

    if (usersSnap.empty) {
        console.log('No users found. Nothing to do.');
        return;
    }

    // Set the FIRST user as admin (or all users if only one)
    const firstUser = usersSnap.docs[0];
    const uid = firstUser.id;

    console.log(`\nSetting admin claim on user: ${uid}`);

    // Set Firebase Auth custom claim
    await admin.auth().setCustomUserClaims(uid, { admin: true });
    console.log('✓ Firebase Auth custom claim set');

    // Set Firestore isAdmin field
    await db.collection('users').doc(uid).update({ isAdmin: true });
    console.log('✓ Firestore isAdmin field set');

    console.log(`\nDone! User ${uid} is now an admin.`);
    console.log('Restart the app and try Reset Database again.');

    process.exit(0);
}

setAdmin().catch(err => {
    console.error('Error:', err);
    process.exit(1);
});
