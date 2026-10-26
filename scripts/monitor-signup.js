/**
 * monitor-signup.js
 * Tool to verify and monitor new user signup in Diaspora Nearby.
 * Checks Firebase Auth, Firestore user profile, DSP point ledger, and community memberships.
 *
 * Usage:
 *   node scripts/monitor-signup.js                   (Audits most recent user)
 *   node scripts/monitor-signup.js <UID or phone>   (Audits specific user)
 *   node scripts/monitor-signup.js --watch           (Live monitor watching for new signups)
 */

const fs = require('fs');
const https = require('https');
const path = require('path');

const PROJECT_ID = 'diaspora-nearby-a3dac';

async function getAccessToken() {
  const cfgPath = path.join(process.env.USERPROFILE, '.config', 'configstore', 'firebase-tools.json');
  if (!fs.existsSync(cfgPath)) {
    throw new Error('firebase-tools.json not found in ' + cfgPath);
  }
  const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
  const rt = cfg.tokens && cfg.tokens.refresh_token;
  const scopes = cfg.tokens && cfg.tokens.scopes;
  const auth = require('C:/Users/Nemo CLAW/AppData/Roaming/npm/node_modules/firebase-tools/lib/auth');
  const tokenObj = await auth.getAccessToken(rt, scopes);
  return typeof tokenObj === 'string' ? tokenObj : tokenObj.access_token;
}

function httpsRequest(options, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const parsed = data ? JSON.parse(data) : {};
          resolve({ status: res.statusCode, data: parsed, raw: data });
        } catch (e) {
          resolve({ status: res.statusCode, data: null, raw: data });
        }
      });
    });
    req.on('error', reject);
    if (body) {
      req.write(typeof body === 'string' ? body : JSON.stringify(body));
    }
    req.end();
  });
}

function parseFirestoreValue(val) {
  if (!val) return null;
  if (val.stringValue !== undefined) return val.stringValue;
  if (val.integerValue !== undefined) return parseInt(val.integerValue, 10);
  if (val.doubleValue !== undefined) return parseFloat(val.doubleValue);
  if (val.booleanValue !== undefined) return val.booleanValue;
  if (val.timestampValue !== undefined) return val.timestampValue;
  if (val.nullValue !== undefined) return null;
  if (val.arrayValue) {
    return (val.arrayValue.values || []).map(parseFirestoreValue);
  }
  if (val.mapValue) {
    const obj = {};
    for (const [k, v] of Object.entries(val.mapValue.fields || {})) {
      obj[k] = parseFirestoreValue(v);
    }
    return obj;
  }
  return val;
}

function parseFirestoreDoc(doc) {
  if (!doc || !doc.fields) return null;
  const result = { id: doc.name.split('/').pop() };
  for (const [k, v] of Object.entries(doc.fields)) {
    result[k] = parseFirestoreValue(v);
  }
  return result;
}

async function getAuthUsers(token) {
  const res = await httpsRequest({
    hostname: 'identitytoolkit.googleapis.com',
    path: `/v1/projects/${PROJECT_ID}/accounts:query`,
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    }
  }, { maxResults: 50 });

  if (res.status !== 200) {
    throw new Error('Failed to query Auth users: ' + res.raw);
  }

  const users = (res.data.userInfo || []).map(u => ({
    uid: u.localId,
    phoneNumber: u.phoneNumber,
    email: u.email,
    createdAt: u.createdAt ? new Date(parseInt(u.createdAt, 10)).toISOString() : null,
    lastLoginAt: u.lastLoginAt ? new Date(parseInt(u.lastLoginAt, 10)).toISOString() : null,
    disabled: !!u.disabled
  }));

  users.sort((a, b) => (b.createdAt || '').localeCompare(a.createdAt || ''));
  return users;
}

async function getFirestoreDoc(token, docPath) {
  const res = await httpsRequest({
    hostname: 'firestore.googleapis.com',
    path: `/v1/projects/${PROJECT_ID}/databases/(default)/documents/${docPath}`,
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${token}`
    }
  });

  if (res.status === 404) return null;
  if (res.status !== 200) {
    throw new Error(`Failed to get Firestore doc ${docPath}: ${res.raw}`);
  }
  return parseFirestoreDoc(res.data);
}

async function queryFirestore(token, collectionId, whereClause, limit = 20) {
  const query = {
    structuredQuery: {
      from: [{ collectionId }],
      limit
    }
  };
  if (whereClause) {
    query.structuredQuery.where = whereClause;
  }

  const res = await httpsRequest({
    hostname: 'firestore.googleapis.com',
    path: `/v1/projects/${PROJECT_ID}/databases/(default)/documents:runQuery`,
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    }
  }, query);

  if (res.status !== 200) {
    throw new Error(`Firestore query failed on ${collectionId}: ${res.raw}`);
  }

  const items = [];
  if (Array.isArray(res.data)) {
    for (const r of res.data) {
      if (r.document) {
        items.push(parseFirestoreDoc(r.document));
      }
    }
  }
  return items;
}

async function listSubcollectionDocs(token, docPath, subcollectionId) {
  const res = await httpsRequest({
    hostname: 'firestore.googleapis.com',
    path: `/v1/projects/${PROJECT_ID}/databases/(default)/documents/${docPath}/${subcollectionId}`,
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${token}`
    }
  });
  if (res.status === 404) return [];
  if (res.status !== 200) return [];
  const docs = (res.data.documents || []).map(parseFirestoreDoc);
  return docs;
}

async function auditUser(token, targetUser) {
  console.log(`\n========================================`);
  console.log(`TARGET USER AUDIT: ${targetUser.uid} (${targetUser.phoneNumber || 'N/A'})`);
  console.log(`Auth Created: ${targetUser.createdAt}`);
  console.log(`========================================\n`);

  // 1. Check user profile
  console.log('1. Checking users/' + targetUser.uid + '...');
  const userProfile = await getFirestoreDoc(token, `users/${targetUser.uid}`);
  if (!userProfile) {
    console.log('   ⚠️ Document users/' + targetUser.uid + ' DOES NOT EXIST yet.');
    console.log('   (User verified OTP but has not submitted /profile-setup form yet).');
    return false;
  } else {
    console.log('   ✅ Profile Document Found:');
    console.log('      • Name: ' + (userProfile.firstName || '(none)') + ' ' + (userProfile.lastName || ''));
    console.log('      • Phone: ' + (userProfile.phoneNumber || targetUser.phoneNumber || 'N/A'));
    console.log('      • Origin Country: ' + userProfile.homeCountryCode);
    console.log('      • Host Country: ' + userProfile.hostCountryCode);
    console.log('      • State / City: ' + (userProfile.stateProvince || 'N/A') + ', ' + (userProfile.city || 'N/A'));
    console.log('      • Profile Picture: ' + (userProfile.profilePictureUrl ? 'Present' : 'None'));
    console.log('      • Smart Wallet Address: ' + (userProfile.walletAddress || 'Generating...'));
    console.log('      • Wallet Type: ' + (userProfile.walletType || 'N/A'));
    console.log('      • Created At: ' + userProfile.createdAt);
  }

  // 2. Check DSP ledger (user_points)
  console.log('\n2. Checking user_points/' + targetUser.uid + ' (DSP Points Ledger)...');
  const pointsDoc = await getFirestoreDoc(token, `user_points/${targetUser.uid}`);
  if (!pointsDoc) {
    console.log('   ⚠️ Document user_points/' + targetUser.uid + ' DOES NOT EXIST yet.');
  } else {
    const totalPts = pointsDoc.totalPoints ?? pointsDoc.total_points ?? 0;
    const availPts = pointsDoc.availablePoints ?? pointsDoc.available_points ?? 0;
    console.log('   ✅ Points Ledger Found:');
    console.log('      • Total Points: ' + totalPts);
    console.log('      • Available Points: ' + availPts);
    console.log('      • Staked Points: ' + (pointsDoc.stakedPoints ?? 0));
    console.log('      • Earned Points: ' + (pointsDoc.earnedPoints ?? 0));
    
    if (totalPts === 0) {
      console.log('      🎯 SUCCESS: New user initialized with 0 DSP (welcome bonus correctly deprecated).');
    } else if (totalPts >= 10000) {
      console.log('      🚨 ALERT: User has ' + totalPts + ' DSP! Deprecated welcome bonus was credited.');
    } else {
      console.log('      ℹ️ Total DSP: ' + totalPts);
    }
  }

  // 3. Check points transactions subcollection
  console.log('\n3. Checking user_points/' + targetUser.uid + '/transactions...');
  try {
    const txs = await listSubcollectionDocs(token, `user_points/${targetUser.uid}`, 'transactions');
    if (txs.length === 0) {
      console.log('   ✅ 0 initial transactions (clean ledger, no welcome bonus transaction).');
    } else {
      console.log(`   Found ${txs.length} transaction(s):`);
      txs.forEach(t => {
        console.log(`      • [${t.type || t.action || 'tx'}] ${t.points || t.amount || 0} DSP - ${t.description || t.reason || ''}`);
      });
    }
  } catch (e) {
    console.log('   Note on transactions:', e.message);
  }

  // 4. Check Proof of Humanity / Trust profile
  console.log('\n4. Checking Proof of Humanity status...');
  const trustDoc = await getFirestoreDoc(token, `trust_profiles/${targetUser.uid}`) ||
                   await getFirestoreDoc(token, `trust_scores/${targetUser.uid}`);
  if (trustDoc) {
    console.log('   ✅ Trust Profile Found:', trustDoc);
  } else {
    console.log('   ℹ️ PoH status is evaluated via 6 core milestones in TrustService.');
  }

  // 5. Check Community Memberships
  console.log('\n5. Checking Community Memberships for user ' + targetUser.uid + '...');
  try {
    const communities = await queryFirestore(token, 'communities', {
      fieldFilter: {
        field: { fieldPath: 'members' },
        op: 'ARRAY_CONTAINS',
        value: { stringValue: targetUser.uid }
      }
    }, 20);

    if (communities && communities.length > 0) {
      console.log(`   ✅ User successfully enrolled in ${communities.length} community chats:`);
      communities.forEach(c => {
        console.log(`      • [${c.type || 'community'}] "${c.name || c.id}" (Total Members: ${c.totalMembers || (c.members ? c.members.length : 0)})`);
      });
    } else {
      console.log('   ⚠️ No community memberships found where user UID is in members array.');
    }
  } catch (e) {
    console.log('   Community query note:', e.message);
  }

  console.log('\n========================================');
  console.log('AUDIT CHECK COMPLETE');
  console.log('========================================\n');
  return true;
}

async function main() {
  const arg = process.argv[2] ? process.argv[2].trim() : null;
  const isWatch = process.argv.includes('--watch') || arg === '--watch';
  const targetFilter = isWatch ? (process.argv[3] || null) : arg;

  console.log('Authenticating with Firebase management API...');
  const token = await getAccessToken();

  console.log('\n========================================');
  console.log('DIASPORA NEARBY - SIGNUP MONITOR & VERIFICATION');
  console.log('Target Project: ' + PROJECT_ID);
  console.log('Timestamp: ' + new Date().toISOString());
  console.log('Mode: ' + (isWatch ? 'CONTINUOUS WATCH' : 'SINGLE AUDIT'));
  console.log('========================================\n');

  if (isWatch) {
    console.log('👀 Watching for new user registrations (Ctrl+C to stop)...');
    let baselineUsers = await getAuthUsers(token);
    const baselineIds = new Set(baselineUsers.map(u => u.uid));
    console.log(`Baseline established (${baselineUsers.length} existing users). Waiting for new signup...`);

    while (true) {
      await new Promise(r => setTimeout(r, 4000));
      const currentUsers = await getAuthUsers(token);
      const newUsers = currentUsers.filter(u => !baselineIds.has(u.uid));
      if (newUsers.length > 0) {
        console.log(`\n🎉 DETECTED ${newUsers.length} NEW AUTH USER(S)!`);
        for (const nu of newUsers) {
          baselineIds.add(nu.uid);
          await auditUser(token, nu);
        }
      }
    }
  } else {
    const authUsers = await getAuthUsers(token);
    let targetUser = null;
    if (targetFilter) {
      targetUser = authUsers.find(u => 
        u.uid === targetFilter || 
        (u.phoneNumber && u.phoneNumber.includes(targetFilter)) ||
        (u.email && u.email.toLowerCase().includes(targetFilter.toLowerCase()))
      );
    } else {
      targetUser = authUsers[0];
    }

    console.log(`--- Top 5 Recent Auth Users ---`);
    authUsers.slice(0, 5).forEach((u, i) => {
      const isTarget = targetUser && targetUser.uid === u.uid;
      console.log(`${isTarget ? '👉 ' : '   '}[${i+1}] UID: ${u.uid} | Phone: ${u.phoneNumber || 'N/A'} | Created: ${u.createdAt}`);
    });

    if (!targetUser) {
      console.log('\n❌ No matching user found.');
      return;
    }

    await auditUser(token, targetUser);
  }
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
