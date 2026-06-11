const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");

const PROJECT_ID = "diaspora-nearby-rules-test";

jest.setTimeout(30000);

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(
        path.resolve(__dirname, "..", "firestore.rules"),
        "utf8"
      ),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

// Helpers
function dbFor(uid) {
  return uid
    ? testEnv.authenticatedContext(uid).firestore()
    : testEnv.unauthenticatedContext().firestore();
}

function adminDb() {
  return testEnv.withSecurityRulesDisabled((ctx) => ctx.firestore());
}

async function seed(setup) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setup(ctx.firestore());
  });
}

// ─── Chamber chat posting ──────────────────────────────────────────────────

describe("Chamber chat posting (subtype == 'corridor_chamber')", () => {
  const chatId = "chamber-tz-uk";
  const memberUid = "member-1";
  const followerUid = "follower-1";
  const outsiderUid = "outsider-1";

  beforeEach(async () => {
    await seed(async (db) => {
      await db.doc(`chats/${chatId}`).set({
        subtype: "corridor_chamber",
        participants: [memberUid, followerUid],
      });
      await db.doc(`users/${memberUid}/userChats/${chatId}`).set({
        accessLevel: "member",
      });
      await db.doc(`users/${followerUid}/userChats/${chatId}`).set({
        accessLevel: "follower",
      });
    });
  });

  test("member CAN post in chamber chat", async () => {
    const db = dbFor(memberUid);
    await assertSucceeds(
      db.collection(`chats/${chatId}/messages`).add({
        senderId: memberUid,
        text: "hello",
      })
    );
  });

  test("follower CANNOT post in chamber chat", async () => {
    const db = dbFor(followerUid);
    await assertFails(
      db.collection(`chats/${chatId}/messages`).add({
        senderId: followerUid,
        text: "hello",
      })
    );
  });

  test("non-participant cannot post even if authenticated", async () => {
    const db = dbFor(outsiderUid);
    await assertFails(
      db.collection(`chats/${chatId}/messages`).add({
        senderId: outsiderUid,
        text: "hello",
      })
    );
  });
});

describe("Non-chamber chat posting (legacy rule)", () => {
  const chatId = "regular-chat";
  const uid = "user-1";
  const legacyUid = "legacy-user";
  const outsiderUid = "outsider";

  beforeEach(async () => {
    await seed(async (db) => {
      await db.doc(`chats/${chatId}`).set({
        subtype: "direct",
        participants: [uid],
      });
    });
  });

  test("participant CAN post in non-chamber chat without accessLevel", async () => {
    const db = dbFor(uid);
    await assertSucceeds(
      db.collection(`chats/${chatId}/messages`).add({
        senderId: uid,
        text: "hi",
      })
    );
  });

  test("legacy userChat owner CAN post when participants is incomplete", async () => {
    await seed(async (db) => {
      await db.doc(`users/${legacyUid}/userChats/${chatId}`).set({
        chatId,
      });
    });

    const db = dbFor(legacyUid);
    await assertSucceeds(
      db.collection(`chats/${chatId}/messages`).add({
        senderId: legacyUid,
        text: "legacy direct chat",
      })
    );
  });

  test("legacy user CAN commit the complete message delivery batch", async () => {
    await seed(async (db) => {
      await db.doc(`users/${legacyUid}/userChats/${chatId}`).set({
        chatId,
      });
    });

    const db = dbFor(legacyUid);
    const messageRef = db.collection(`chats/${chatId}/messages`).doc();
    const lastMessage = {
      id: messageRef.id,
      senderId: legacyUid,
      content: "batch message",
      timestamp: 1,
    };
    const batch = db.batch();

    batch.set(messageRef, {
      senderId: legacyUid,
      content: "batch message",
      timestamp: 1,
    });
    batch.set(
      db.doc(`chats/${chatId}`),
      { lastMessage, updatedAt: 1 },
      { merge: true }
    );
    batch.set(
      db.doc(`users/${legacyUid}/userChats/${chatId}`),
      { chatId, lastMessage, updatedAt: 1 },
      { merge: true }
    );

    await assertSucceeds(batch.commit());
  });

  test("legacy sparse chat CAN commit when participants and subtype are missing", async () => {
    await seed(async (db) => {
      await db.doc(`chats/${chatId}`).set({
        name: "Legacy direct chat",
      });
      await db.doc(`users/${legacyUid}/userChats/${chatId}`).set({
        chatId,
      });
    });

    const db = dbFor(legacyUid);
    const messageRef = db.collection(`chats/${chatId}/messages`).doc();
    const batch = db.batch();

    batch.set(messageRef, {
      senderId: legacyUid,
      content: "sparse batch message",
      timestamp: 1,
    });
    batch.set(
      db.doc(`chats/${chatId}`),
      {
        lastMessage: {
          id: messageRef.id,
          senderId: legacyUid,
          content: "sparse batch message",
          timestamp: 1,
        },
        updatedAt: 1,
      },
      { merge: true }
    );
    batch.set(
      db.doc(`users/${legacyUid}/userChats/${chatId}`),
      { chatId, updatedAt: 1 },
      { merge: true }
    );

    await assertSucceeds(batch.commit());
  });

  test("outsider without participant or userChat record CANNOT post", async () => {
    const db = dbFor(outsiderUid);
    await assertFails(
      db.collection(`chats/${chatId}/messages`).add({
        senderId: outsiderUid,
        text: "no access",
      })
    );
  });

  test("outsider CANNOT spoof another chat's last message", async () => {
    const db = dbFor(outsiderUid);
    await assertFails(
      db.doc(`chats/${chatId}`).set(
        {
          lastMessage: {
            senderId: outsiderUid,
            content: "spoofed",
            timestamp: 1,
          },
          updatedAt: 1,
        },
        { merge: true }
      )
    );
  });
});

// ─── Leadership requests ───────────────────────────────────────────────────

describe("/leadershipRequests", () => {
  const userUid = "user-1";
  const otherUid = "user-2";
  const adminUid = "admin-1";

  beforeEach(async () => {
    await seed(async (db) => {
      await db.doc(`users/${adminUid}`).set({ isAdmin: true });
    });
  });

  test("user CAN create their OWN pending request", async () => {
    const db = dbFor(userUid);
    await assertSucceeds(
      db.collection("leadershipRequests").add({
        userId: userUid,
        approved: false,
        status: "pending",
        chamberId: "tz-uk",
      })
    );
  });

  test("user CANNOT create a request impersonating another user", async () => {
    const db = dbFor(userUid);
    await assertFails(
      db.collection("leadershipRequests").add({
        userId: otherUid,
        approved: false,
        status: "pending",
      })
    );
  });

  test("user CANNOT create an already-approved request", async () => {
    const db = dbFor(userUid);
    await assertFails(
      db.collection("leadershipRequests").add({
        userId: userUid,
        approved: true,
        status: "pending",
      })
    );
  });

  test("user CANNOT update their own request (no role-shopping)", async () => {
    await seed(async (db) => {
      await db.doc("leadershipRequests/r1").set({
        userId: userUid,
        approved: false,
        status: "pending",
      });
    });
    const db = dbFor(userUid);
    await assertFails(
      db.doc("leadershipRequests/r1").update({ chamberId: "different" })
    );
  });

  test("admin CAN flip approved → true", async () => {
    await seed(async (db) => {
      await db.doc("leadershipRequests/r1").set({
        userId: userUid,
        approved: false,
        status: "pending",
      });
    });
    const db = dbFor(adminUid);
    await assertSucceeds(
      db.doc("leadershipRequests/r1").update({
        approved: true,
        status: "approved",
      })
    );
  });

  test("user CAN withdraw their OWN pending request", async () => {
    await seed(async (db) => {
      await db.doc("leadershipRequests/r1").set({
        userId: userUid,
        approved: false,
        status: "pending",
      });
    });
    const db = dbFor(userUid);
    await assertSucceeds(db.doc("leadershipRequests/r1").delete());
  });

  test("user CANNOT delete another user's request", async () => {
    await seed(async (db) => {
      await db.doc("leadershipRequests/r1").set({
        userId: otherUid,
        approved: false,
        status: "pending",
      });
    });
    const db = dbFor(userUid);
    await assertFails(db.doc("leadershipRequests/r1").delete());
  });
});

// ─── Emergency fund ledger ─────────────────────────────────────────────────

describe("/emergency_fund_ledger", () => {
  beforeEach(async () => {
    await seed(async (db) => {
      await db.doc("emergency_fund_ledger/entry-1").set({
        amount: 100,
        userId: "u-1",
      });
    });
  });

  test("authenticated user CAN read ledger entries (transparency)", async () => {
    const db = dbFor("any-user");
    await assertSucceeds(db.doc("emergency_fund_ledger/entry-1").get());
  });

  test("unauthenticated user CANNOT read", async () => {
    const db = dbFor(null);
    await assertFails(db.doc("emergency_fund_ledger/entry-1").get());
  });

  test("authenticated user CANNOT write — server-only", async () => {
    const db = dbFor("any-user");
    await assertFails(
      db.collection("emergency_fund_ledger").add({ amount: 999 })
    );
  });
});

// ─── Corridor chamber organization update ──────────────────────────────────

describe("organizations/{orgId} (kind == 'corridor_chamber')", () => {
  const orgId = "chamber-tz-uk";
  const userUid = "user-1";
  const adminUid = "admin-1";

  beforeEach(async () => {
    await seed(async (db) => {
      await db.doc(`users/${adminUid}`).set({ isAdmin: true });
      await db.doc(`organizations/${orgId}`).set({
        kind: "corridor_chamber",
        name: "TZ-UK Chamber",
        members: [],
        followers: [],
        memberCount: 0,
        admins: [],
      });
    });
  });

  test("non-admin CAN self-add to followers", async () => {
    const db = dbFor(userUid);
    await assertSucceeds(
      db.doc(`organizations/${orgId}`).update({
        followers: [userUid],
      })
    );
  });

  test("non-admin CAN self-add to members + bump memberCount", async () => {
    const db = dbFor(userUid);
    await assertSucceeds(
      db.doc(`organizations/${orgId}`).update({
        members: [userUid],
        memberCount: 1,
        updatedAt: new Date(),
      })
    );
  });

  test("non-admin CANNOT rewrite admins array", async () => {
    const db = dbFor(userUid);
    await assertFails(
      db.doc(`organizations/${orgId}`).update({
        admins: [userUid],
      })
    );
  });

  test("non-admin CANNOT rename the chamber", async () => {
    const db = dbFor(userUid);
    await assertFails(
      db.doc(`organizations/${orgId}`).update({
        name: "Hijacked",
      })
    );
  });

  test("platform admin CAN do substantive edits", async () => {
    const db = dbFor(adminUid);
    await assertSucceeds(
      db.doc(`organizations/${orgId}`).update({
        name: "Renamed by admin",
        admins: [adminUid],
      })
    );
  });
});
