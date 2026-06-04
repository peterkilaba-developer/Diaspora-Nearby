const admin = require('firebase-admin');

// Initialize with service account key
const serviceAccount = require('../tools/admin-scripts/service-account-key.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function seedMockElection(unitId) {
    console.log(`Seeding mock election for ${unitId}...`);

    const unitRef = db.collection('governance').doc(unitId);
    const unitDoc = await unitRef.get();

    const now = Date.now();
    const endTime = now + (7 * 24 * 60 * 60 * 1000);

    if (!unitDoc.exists) {
        console.log('Unit missing, creating...');
        await unitRef.set({
            id: unitId,
            name: 'ARUSHA',
            level: 'local',
            type: 'town',
            isActiveElection: true,
            electionEndTime: endTime,
            councilMembers: [],
            signers: [],
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
    } else {
        console.log('Unit exists, updating...');
        await unitRef.update({
            isActiveElection: true,
            electionEndTime: endTime,
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
    }

    // 2. Ensure mock candidates exist
    // We'll check the trust_data collection for users in TZ
    const candidatesSnapshot = await db.collection('trust_data')
        .where('isCouncilEligible', '==', true)
        .limit(20)
        .get();

    console.log(`Found ${candidatesSnapshot.size} eligible candidates.`);

    if (candidatesSnapshot.size < 20) {
        const needed = 20 - candidatesSnapshot.size;
        console.log(`Creating ${needed} mock candidates...`);

        for (let i = 0; i < needed; i++) {
            const mockId = `mock-pillar-${i}-${now % 1000}`;
            const batch = db.batch();

            // User Points
            batch.set(db.collection('user_points').doc(mockId), {
                userId: mockId,
                totalPoints: 150000 + (i * 5000),
                availablePoints: 50000,
                trustScore: 85 + i,
                currentStreak: 10,
                dailyMessageCount: 5,
                lastUpdated: admin.firestore.Timestamp.now(),
                signupDate: admin.firestore.Timestamp.fromDate(new Date(now - 400 * 24 * 60 * 60 * 1000)),
            });

            // User Profile
            batch.set(db.collection('users').doc(mockId), {
                uid: mockId,
                firstName: `Mock`,
                lastName: `Pillar ${i + 1}`,
                displayName: `Mock Pillar ${i + 1}`,
                homeCountryCode: 'TZ',
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Trust Data
            batch.set(db.collection('trust_data').doc(mockId), {
                uid: mockId,
                lastUpdated: admin.firestore.Timestamp.now(),
                trustScore: 85 + i,
                isVerified: true,
                isCouncilEligible: true,
                uniqueFamilyCount: 10,
                uniqueQrCount: 10,
                uniqueVouchCount: 10,
                uniqueVerificationCount: 10,
                awardedQualificationMilestones: [
                    'family_10', 'qr_10', 'vouch_10', 'verify_10', 'profile_complete'
                ],
            });

            await batch.commit();
        }
    }
}

seedMockElection('city_tz_no-state_arusha').then(() => {
    console.log('Mock election cycle activated successfully.');
    process.exit(0);
}).catch(err => {
    console.error('Error seeding mock election:', err);
    process.exit(1);
});
