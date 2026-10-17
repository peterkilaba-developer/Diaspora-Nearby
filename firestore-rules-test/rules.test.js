const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const { deleteField } = require("firebase/firestore");

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
function dbFor(uid, claims = {}) {
  return uid
    ? testEnv.authenticatedContext(uid, claims).firestore()
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

  test("follower CANNOT promote their own chamber access index", async () => {
    const db = dbFor(followerUid);
    await assertFails(
      db.doc(`users/${followerUid}/userChats/${chatId}`).update({
        accessLevel: "member",
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

  test("userChat index grants message access for legacy chats without complete participants", async () => {
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

  test("userChat index grants a complete message delivery batch when lastMessage has valid type", async () => {
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
      type: "text",
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

  test("sparse legacy chat grants access through a userChat index when lastMessage has valid type", async () => {
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
          type: "text",
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
    const db = dbFor(adminUid, { admin: true });
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

  test("only the requester or a claim-backed admin can read a request", async () => {
    await seed((db) => db.doc("leadershipRequests/r1").set({
      userId: userUid,
      approved: false,
      status: "pending",
    }));
    await assertSucceeds(dbFor(userUid).doc("leadershipRequests/r1").get());
    await assertFails(dbFor(otherUid).doc("leadershipRequests/r1").get());
    await assertSucceeds(
      dbFor(adminUid, { admin: true }).doc("leadershipRequests/r1").get()
    );
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
    const db = dbFor(adminUid, { admin: true });
    await assertSucceeds(
      db.doc(`organizations/${orgId}`).update({
        name: "Renamed by admin",
        admins: [adminUid],
      })
    );
  });
});

// ─── Enterprise security regression tests ─────────────────────────────────

describe("profile completion", () => {
  const uid = "signup-user";
  const summary = {
    formatted_address: "Dar es Salaam, Tanzania",
    city: "Dar es Salaam", state: null, country: "Tanzania", country_code: "TZ",
  };
  const profile = {
    firstName: "Test", lastName: "User", profilePhoto: "https://example.com/photo.jpg",
    homeLocation: summary, hostLocation: summary, showCurrentLocationName: true,
  };

  test("owner can atomically complete and retry a profile with private locations", async () => {
    const db = dbFor(uid);
    for (let attempt = 0; attempt < 2; attempt++) {
      const batch = db.batch();
      batch.set(db.doc(`users/${uid}`), profile, { merge: true });
      batch.set(db.doc(`user_private/${uid}`), {
        phone: "+255123456789",
        homeLocation: { ...summary, place_id: "private-id", geometry: { location: { lat: -6.8, lng: 39.2 } } },
      }, { merge: true });
      await assertSucceeds(batch.commit());
    }
  });

  test("public summaries still reject precise location identifiers", async () => {
    await assertFails(dbFor(uid).doc(`users/${uid}`).set({
      ...profile, homeLocation: { ...summary, place_id: "" },
    }));
  });

  test.each(["businessProfile", "cityVisibilityForfeited"])(
    "explicit null %s is rejected even with otherwise valid signup data",
    async (field) => {
      await assertFails(dbFor(uid).doc(`users/${uid}`).set({
        ...profile, [field]: null,
      }));
    }
  );

  test("new users can choose hidden city without a forfeiture milestone", async () => {
    await assertSucceeds(dbFor(uid).doc(`users/${uid}`).set({
      ...profile, showCurrentLocationName: false,
    }));
  });

  test("signup update succeeds when getOrCreateSmartWallet has already created the user doc", async () => {
    await seed((db) => db.doc(`users/${uid}`).set({
      walletAddress: "0x1234567890abcdef1234567890abcdef12345678",
      walletType: "smart",
      walletSaltVersion: 2,
      walletDeploymentPending: true,
    }));
    const db = dbFor(uid);
    await assertSucceeds(db.doc(`users/${uid}`).set(profile, { merge: true }));
    await assertSucceeds(db.doc(`users/${uid}`).set({
      ...profile, showCurrentLocationName: false,
    }, { merge: true }));
  });

  test("merged write on legacy user doc fails if legacy place_id/geometry are retained, and succeeds when deleted", async () => {
    await seed((db) => db.doc(`users/${uid}`).set({
      firstName: "Legacy",
      lastName: "User",
      currentLocation: {
        ...summary,
        place_id: "legacy-current-id",
        geometry: { location: { lat: -6.8, lng: 39.2 } },
      },
      homeLocation: {
        ...summary,
        place_id: "legacy-home-id",
        geometry: { location: { lat: -6.8, lng: 39.2 } },
      },
      hostLocation: {
        ...summary,
        place_id: "",
        geometry: { location: { lat: -6.8, lng: 39.2 } },
      },
    }));
    const db = dbFor(uid);
    // Without deleting legacy keys, deep merge retains place_id/geometry/currentLocation and fails rules
    await assertFails(db.doc(`users/${uid}`).set(profile, { merge: true }));

    // With explicit FieldValue.delete() cleanup (matching ProfileRepository._cleanLegacyPublicFields), merged write succeeds
    await assertSucceeds(db.doc(`users/${uid}`).set({
      ...profile,
      currentLocation: deleteField(),
      homeLocation: {
        ...summary,
        place_id: deleteField(),
        geometry: deleteField(),
      },
      hostLocation: {
        ...summary,
        place_id: deleteField(),
        geometry: deleteField(),
      },
    }, { merge: true }));
  });

  test("another user cannot complete someone else's profile", async () => {
    await assertFails(dbFor("other-user").doc(`users/${uid}`).set(profile));
  });
});

describe("privilege escalation containment", () => {
  const uid = "regular-user";

  test("a user cannot create a profile that grants admin privileges", async () => {
    const db = dbFor(uid);
    await assertFails(db.doc(`users/${uid}`).set({
      displayName: "Attacker",
      isAdmin: true,
    }));
  });

  test("a user cannot promote an existing profile", async () => {
    await seed((db) => db.doc(`users/${uid}`).set({ displayName: "User" }));
    const db = dbFor(uid);
    await assertFails(db.doc(`users/${uid}`).update({ isAdmin: true }));
  });

  test("a Firestore isAdmin field does not confer platform admin rights", async () => {
    await seed(async (db) => {
      await db.doc(`users/${uid}`).set({ isAdmin: true });
      await db.doc("leadershipRequests/r-escalation").set({
        userId: "victim",
        approved: false,
        status: "pending",
      });
    });
    const db = dbFor(uid);
    await assertFails(db.doc("leadershipRequests/r-escalation").update({
      approved: true,
      status: "approved",
    }));
  });
});

describe("financial and trust state is server-authored", () => {
  const uid = "economy-user";

  test("a user cannot create an arbitrary points balance", async () => {
    const db = dbFor(uid);
    await assertFails(db.doc(`user_points/${uid}`).set({
      totalPoints: 1000000,
      availablePoints: 1000000,
    }));
  });

  test("a user cannot append a points transaction", async () => {
    const db = dbFor(uid);
    await assertFails(db.collection("points_transactions").add({
      userId: uid,
      points: 1000000,
      action: "self_award",
    }));
  });

  test("a user cannot manufacture trust-score or QR milestone state", async () => {
    const db = dbFor(uid);
    await assertFails(db.doc(`trust_scores/${uid}`).set({ trustScore: 100 }));
    await assertFails(db.doc(`trust_data/${uid}`).set({ poctScore: 100 }));
    await assertFails(db.collection("qr_exchanges").add({
      fromUid: uid,
      toUid: "victim",
    }));
  });
});

describe("chat index isolation", () => {
  test("a sender cannot overwrite another user's chat index", async () => {
    const db = dbFor("sender");
    await assertFails(db.doc("users/recipient/userChats/chat-1").set({
      chatId: "chat-1",
      unreadCount: 0,
    }));
  });
});

describe("trust ratings are identity-bound", () => {
  const fromUid = "rater";
  const toUid = "rated-user";

  beforeEach(async () => {
    await seed((db) => db.doc(`users/${toUid}`).set({ displayName: "Rated" }));
  });

  test("a deterministic, zero-stake rating can be created", async () => {
    await assertSucceeds(dbFor(fromUid).doc(`trust_ratings/${fromUid}_${toUid}`).set({
      fromUserId: fromUid,
      toUserId: toUid,
      score: 75,
      isFullTrust: false,
      stakedAmount: 0,
      remainingStake: 0,
      timestamp: "now",
    }));
  });

  test("random IDs, fake stake, and inconsistent full-trust flags are rejected", async () => {
    const base = {
      fromUserId: fromUid,
      toUserId: toUid,
      score: 95,
      isFullTrust: true,
      stakedAmount: 0,
      remainingStake: 0,
      timestamp: "now",
    };
    await assertFails(dbFor(fromUid).doc("trust_ratings/random").set(base));
    await assertFails(dbFor(fromUid).doc(`trust_ratings/${fromUid}_${toUid}`).set({
      ...base,
      stakedAmount: 1000,
      remainingStake: 1000,
    }));
    await assertFails(dbFor(fromUid).doc(`trust_ratings/${fromUid}_${toUid}`).set({
      ...base,
      isFullTrust: false,
    }));
  });
});

describe("event attendance is server-authored", () => {
  const creatorUid = "event-creator";

  beforeEach(async () => {
    await seed((db) => db.doc("events/event-1").set({
      creatorId: creatorUid,
      attendees: [],
      attendeeCount: 0,
      interested: [],
      interestedCount: 0,
      confirmedAttendees: [],
    }));
  });

  test("event creation accepts only the creator as the initial attendee", async () => {
    const db = dbFor(creatorUid);
    await assertSucceeds(db.doc("events/valid-event").set({
      creatorId: creatorUid,
      attendees: [creatorUid],
      attendeeCount: 1,
      interested: [],
      interestedCount: 0,
      confirmedAttendees: [],
      paidAttendeeIds: [],
      isPaid: false,
      maxAttendees: 100,
    }));
    await assertFails(db.doc("events/forged-event").set({
      creatorId: creatorUid,
      attendees: [creatorUid, "fake-attendee"],
      attendeeCount: 2,
      paidAttendeeIds: ["fake-attendee"],
      isPaid: true,
      maxAttendees: 100,
    }));
  });

  test("clients cannot write event attendance subcollections", async () => {
    await assertFails(
      dbFor(creatorUid).doc(`events/event-1/attendees/${creatorUid}`).set({
        userId: creatorUid,
      })
    );
  });

  test("even the event creator cannot forge attendance or confirmation", async () => {
    const db = dbFor(creatorUid);
    await assertFails(db.doc("events/event-1").update({
      attendees: [creatorUid],
      attendeeCount: 1,
    }));
    await assertFails(db.doc("events/event-1").update({
      confirmedAttendees: [creatorUid],
    }));
  });

  test("clients cannot create QR or event check-in challenges", async () => {
    const db = dbFor(creatorUid);
    await assertFails(db.doc("qr_handshake_challenges/fake").set({ used: false }));
    await assertFails(db.doc("event_checkin_challenges/fake").set({ used: false }));
  });
});

describe("listing engagement counters are server-authored", () => {
  const owner = "listing-owner";
  const viewer = "listing-viewer";

  beforeEach(async () => {
    await seed(async (db) => {
      await db.doc(`users/${owner}`).set({displayName: "Owner"});
      await db.doc(`users/${viewer}`).set({displayName: "Viewer"});
      await db.doc("marketplace_listings/existing").set({
        sellerId: owner,
        title: "Listing",
        viewCount: 0,
        savedCount: 0,
      });
    });
  });

  test("owner can create a zero-counter listing but cannot seed engagement", async () => {
    const db = dbFor(owner);
    await assertSucceeds(db.doc("marketplace_listings/valid").set({
      sellerId: owner,
      title: "Valid",
      viewCount: 0,
      savedCount: 0,
    }));
    await assertFails(db.doc("marketplace_listings/inflated").set({
      sellerId: owner,
      title: "Inflated",
      viewCount: 1000000,
      savedCount: 1000000,
    }));
  });

  test("neither owners nor viewers can mutate counters directly", async () => {
    await assertFails(
      dbFor(owner).doc("marketplace_listings/existing").update({viewCount: 1})
    );
    await assertFails(
      dbFor(viewer).doc("marketplace_listings/existing").update({savedCount: 1})
    );
    await assertFails(
      dbFor(viewer).doc(`marketplace_listings/existing/saved_by/${viewer}`).set({
        userId: viewer,
      })
    );
    await assertFails(
      dbFor(viewer).doc(`marketplace_listings/existing/views/${viewer}`).set({
        userId: viewer,
      })
    );
    await assertFails(
      dbFor(owner).doc("marketplace_listings/existing").update({reportCount: 99})
    );
    await assertFails(
      dbFor(viewer).doc(`marketplace_listings/existing/reports/${viewer}`).set({
        reason: "forged",
      })
    );
    await assertFails(
      dbFor(viewer).doc(`marketplace_listings/existing/interactions/${viewer}`).set({
        type: "contact_seller",
      })
    );
  });

  test("owner can still edit non-counter listing content", async () => {
    await assertSucceeds(
      dbFor(owner).doc("marketplace_listings/existing").update({title: "Updated"})
    );
  });
});

describe("legacy trust evidence is one record per user pair", () => {
  const fromUid = "voucher";
  const toUid = "vouched-user";

  beforeEach(async () => {
    await seed(async (db) => {
      await db.doc(`users/${fromUid}`).set({displayName: "Voucher"});
      await db.doc(`users/${toUid}`).set({displayName: "Target"});
    });
  });

  test("a deterministic zero-stake vouch succeeds", async () => {
    const id = `${fromUid}_${toUid}`;
    await assertSucceeds(dbFor(fromUid).doc(`vouches/${id}`).set({
      id,
      fromUserId: fromUid,
      toUserId: toUid,
      relationship: "colleague",
      stakeAmount: 0,
      createdAt: "2026-08-17T00:00:00.000Z",
    }));
  });

  test("random IDs, duplicate rewrites, and fake stake are rejected", async () => {
    const id = `${fromUid}_${toUid}`;
    const valid = {
      id,
      fromUserId: fromUid,
      toUserId: toUid,
      relationship: "friend",
      stakeAmount: 0,
      createdAt: "2026-08-17T00:00:00.000Z",
    };
    await assertFails(dbFor(fromUid).doc("vouches/random").set(valid));
    await assertFails(
      dbFor(fromUid).doc(`vouches/${id}`).set({...valid, stakeAmount: 1000})
    );
    await seed((db) => db.doc(`vouches/${id}`).set(valid));
    await assertFails(dbFor(fromUid).doc(`vouches/${id}`).set({...valid, relationship: "other"}));
  });

  test("clients cannot manufacture check-ins", async () => {
    await assertFails(dbFor(fromUid).doc("check_ins/fake").set({
      userId: fromUid,
      entityId: "event",
      type: "event",
    }));
  });
});

describe("system organization and GDP fields cannot be forged", () => {
  const uid = "org-founder";

  test("a client cannot create an official corridor chamber", async () => {
    await assertFails(dbFor(uid).doc("organizations/fake-chamber").set({
      superAdminId: uid,
      admins: [uid],
      members: [uid],
      kind: "corridor_chamber",
    }));
  });

  test("a regular organization admin cannot convert it or forge GDP", async () => {
    await seed((db) => db.doc("organizations/regular").set({
      superAdminId: uid,
      admins: [uid],
      members: [uid],
      kind: "business",
      name: "Regular",
    }));
    const ref = dbFor(uid).doc("organizations/regular");
    await assertSucceeds(ref.update({name: "Updated"}));
    await assertFails(ref.update({kind: "corridor_chamber"}));
    await assertFails(ref.update({gdpTotal: 999999999}));
  });
});

describe("chat previews cannot impersonate another participant", () => {
  const sender = "preview-sender";
  const peer = "preview-peer";

  beforeEach(async () => {
    await seed((db) => db.doc("chats/preview-chat").set({
      createdBy: sender,
      participants: [sender, peer],
      admins: [sender],
      memberCount: 2,
      lastMessage: {
        senderId: sender,
        content: "hello",
        type: "text",
        status: "sent",
      },
    }));
  });

  test("a participant can author their own preview but not another user's", async () => {
    const ref = dbFor(peer).doc("chats/preview-chat");
    await assertSucceeds(ref.update({
      lastMessage: {
        senderId: peer,
        content: "reply",
        type: "text",
        status: "sent",
      },
    }));
    await assertFails(ref.update({
      lastMessage: {
        senderId: sender,
        content: "forged",
        type: "text",
        status: "sent",
      },
    }));
  });

  test("a participant may advance only the preview delivery status", async () => {
    await assertSucceeds(dbFor(peer).doc("chats/preview-chat").update({
      "lastMessage.status": "delivered",
    }));
    await assertFails(dbFor(peer).doc("chats/preview-chat").update({
      "lastMessage.status": "forged-status",
    }));
  });
});

describe("flight bookings are server-authored", () => {
  test("clients cannot create or rewrite booking confirmations", async () => {
    const uid = "traveler";
    const ref = dbFor(uid).doc("flight_bookings/fake-order");
    await assertFails(ref.set({
      userId: uid,
      orderId: "fake-order",
      status: "confirmed",
    }));
    await seed((db) => db.doc("flight_bookings/real-order").set({
      userId: uid,
      orderId: "real-order",
      status: "confirmed",
    }));
    await assertFails(
      dbFor(uid).doc("flight_bookings/real-order").update({status: "refunded"})
    );
  });
});

describe("abuse reports are server-authored", () => {
  test("a client cannot create or rewrite a moderation report", async () => {
    const uid = "reporter";
    const ref = dbFor(uid).doc("reports/forged");
    await assertFails(ref.set({
      reporterId: uid,
      reportedUserId: "target",
      type: "user",
      status: "pending",
    }));
    await seed((db) => db.doc("reports/server-report").set({
      reporterId: uid,
      reportedUserId: "target",
      type: "user",
      status: "pending",
    }));
    await assertFails(
      dbFor(uid).doc("reports/server-report").update({status: "dismissed"})
    );
  });
});

describe("hosting lifecycle is server-authoritative", () => {
  const traveler = "hosting-traveler";
  const host = "hosting-host";

  beforeEach(async () => {
    await seed(async (db) => {
      await db.doc("hosting_requests/request-1").set({
        travelerId: traveler,
        interestedHostIds: [host],
        matchedHostId: host,
        communityId: "community-1",
        status: "matched",
      });
      await db.doc("hosting_sessions/request-1").set({
        requestId: "request-1",
        travelerId: traveler,
        hostId: host,
        status: "confirmed",
      });
    });
  });

  test("clients cannot create hosting requests or sessions", async () => {
    await assertFails(dbFor(traveler).doc("hosting_requests/forged").set({
      travelerId: traveler,
      interestedHostIds: [],
      communityId: "community-1",
      status: "pending",
    }));
    await assertFails(dbFor(traveler).doc("hosting_sessions/forged").set({
      requestId: "forged",
      travelerId: traveler,
      hostId: host,
      status: "settled",
    }));
  });

  test("neither participant can forge check-in or settlement", async () => {
    const ref = dbFor(traveler).doc("hosting_sessions/request-1");
    await assertFails(ref.update({status: "active", checkInTime: new Date()}));
    await assertFails(ref.update({status: "settled", travelerSettled: true}));
    await assertFails(
      dbFor(host).doc("hosting_sessions/request-1").update({hostSettled: true})
    );
  });

  test("clients cannot read or create hosting check-in challenges", async () => {
    await seed((db) => db.doc("hosting_checkin_challenges/challenge").set({
      sessionId: "request-1",
      hostId: host,
      used: false,
    }));
    const ref = dbFor(host).doc("hosting_checkin_challenges/challenge");
    await assertFails(ref.get());
    await assertFails(
      dbFor(host).doc("hosting_checkin_challenges/forged").set({
        sessionId: "request-1",
        hostId: host,
        used: false,
      })
    );
  });
});

describe("public intake collections are server-authoritative", () => {
  const uid = "intake-user";

  test.each([
    ["feedback", {userId: uid, content: "forged feedback"}],
    ["tester_signups", {email: "attacker@example.com", status: "pending"}],
    ["liquidity_interest", {email: "attacker@example.com", epoch: 1}],
    ["app_requests", {userId: uid, email: "attacker@example.com"}],
    ["referral_redemptions", {referrerId: "victim", refereeId: uid}],
    ["verified_solutions", {reporterId: uid, senderId: "victim"}],
  ])("clients cannot create %s records", async (collection, data) => {
    await assertFails(dbFor(uid).collection(collection).add(data));
    await assertFails(dbFor(null).collection(collection).add(data));
  });
});

describe("relationships and blocking are server-authoritative", () => {
  const owner = "relationship-owner";
  const peer = "relationship-peer";

  beforeEach(async () => {
    await seed(async (db) => {
      await db.doc(`users/${owner}`).set({firstName: "Owner"});
      await db.doc(`users/${peer}`).set({firstName: "Peer"});
      await db.doc(`users/${owner}/relationships/${peer}`).set({
        id: peer,
        type: "Friend",
        name: "Peer",
        status: "active",
      });
      await db.doc("relationship_requests/server-request").set({
        id: "server-request",
        fromUserId: owner,
        toUserId: peer,
        relationshipType: "Friend",
        status: "pending",
      });
    });
  });

  test("owners can read but no client can author relationship projections", async () => {
    const relationship = dbFor(owner).doc(
      `users/${owner}/relationships/${peer}`
    );
    await assertSucceeds(relationship.get());
    await assertFails(dbFor(peer).doc(relationship.path).get());
    await assertFails(relationship.update({type: "Father"}));
    await assertFails(
      dbFor(owner).doc(`users/${owner}/relationships/forged`).set({
        id: "forged",
        type: "Friend",
        status: "active",
      })
    );
  });

  test("participants can read but cannot mutate relationship requests", async () => {
    const request = dbFor(owner).doc("relationship_requests/server-request");
    await assertSucceeds(request.get());
    await assertSucceeds(
      dbFor(peer).doc("relationship_requests/server-request").get()
    );
    await assertFails(request.update({status: "accepted"}));
    await assertFails(
      dbFor(owner).doc("relationship_requests/forged").set({
        fromUserId: owner,
        toUserId: peer,
        status: "pending",
      })
    );
  });

  test("clients cannot forge block records or the private blocked list", async () => {
    await assertFails(
      dbFor(owner).doc(`user_blocks/${owner}/blocked/${peer}`).set({
        blockerId: owner,
        blockedId: peer,
      })
    );
    await seed((db) => db.doc(`user_private/${owner}`).set({phone: "+15555550100"}));
    await assertFails(
      dbFor(owner).doc(`user_private/${owner}`).update({blockedUsers: [peer]})
    );
  });

  test("owners can update ordinary private fields without changing blocks", async () => {
    await seed((db) => db.doc(`user_private/${owner}`).set({
      phone: "+15555550100",
      blockedUsers: [peer],
    }));
    await assertSucceeds(
      dbFor(owner).doc(`user_private/${owner}`).update({
        phone: "+15555550101",
      })
    );
  });
});

describe("direct chats honor server-authored blocks", () => {
  const first = "blocked-chat-first";
  const second = "blocked-chat-second";
  const chatId = "direct-server-chat";

  beforeEach(async () => {
    await seed(async (db) => {
      await db.doc(`chats/${chatId}`).set({
        id: chatId,
        type: "direct",
        createdBy: first,
        participants: [first, second],
        memberCount: 2,
      });
    });
  });

  test("clients cannot create any canonical chats", async () => {
    await assertFails(dbFor(first).doc("chats/direct-forged").set({
      id: "direct-forged",
      type: "direct",
      createdBy: first,
      participants: [first, second],
      admins: [first],
      memberCount: 2,
    }));
    await assertFails(dbFor(first).doc("chats/group-forged").set({
      id: "group-forged",
      type: "group",
      createdBy: first,
      participants: [first],
      admins: [first],
      memberCount: 1,
    }));
  });

  test("either direction of a block prevents new direct messages", async () => {
    await seed((db) => db.doc(`user_blocks/${first}/blocked/${second}`).set({
      blockerId: first,
      blockedId: second,
    }));
    await assertFails(
      dbFor(first).collection(`chats/${chatId}/messages`).add({
        senderId: first,
        text: "blocked outbound",
      })
    );
    await assertFails(
      dbFor(second).collection(`chats/${chatId}/messages`).add({
        senderId: second,
        text: "blocked inbound",
      })
    );
  });

  test("unblocked direct-chat participants can still message", async () => {
    await assertSucceeds(
      dbFor(first).collection(`chats/${chatId}/messages`).add({
        senderId: first,
        text: "hello",
      })
    );
  });
});

describe("communities are canonically provisioned", () => {
  const owner = "community-owner";
  const communityId = "home_country_us";

  beforeEach(async () => {
    await seed(async (db) => {
      await db.doc(`communities/${communityId}`).set({
        name: "United States Community",
        admins: [owner],
        members: [owner],
        memberCount: 1,
        totalMembers: 1,
        treasuryBalance: 100,
      });
    });
  });

  test("clients cannot squat canonical community identifiers", async () => {
    await assertFails(dbFor(owner).doc("communities/home_country_ca").set({
      name: "Forged community",
      admins: [owner],
      members: [owner],
      memberCount: 1,
      totalMembers: 1,
    }));
  });

  test("community admins can edit presentation but not membership or treasury", async () => {
    const ref = dbFor(owner).doc(`communities/${communityId}`);
    await assertSucceeds(ref.update({description: "Updated description"}));
    await assertFails(ref.update({members: [owner, "forged-member"], memberCount: 2}));
    await assertFails(ref.update({treasuryBalance: 1000000}));
    await assertFails(
      dbFor(owner).doc(`communities/${communityId}/members/${owner}`).set({
        joinedAt: Date.now(),
      })
    );
  });
});

describe("peer bookings are server-authoritative", () => {
  const guest = "peer-booking-guest";
  const host = "peer-booking-host";

  beforeEach(async () => {
    await seed((db) => db.doc("peer_bookings/server-booking").set({
      guestId: guest,
      hostId: host,
      listingId: "listing-1",
      status: "pending",
    }));
  });

  test("participants can read but cannot forge or transition bookings", async () => {
    await assertSucceeds(dbFor(guest).doc("peer_bookings/server-booking").get());
    await assertSucceeds(dbFor(host).doc("peer_bookings/server-booking").get());
    await assertFails(dbFor(guest).doc("peer_bookings/forged").set({
      guestId: guest,
      hostId: host,
      listingId: "listing-1",
      status: "pending",
    }));
    await assertFails(
      dbFor(host).doc("peer_bookings/server-booking").update({status: "completed"})
    );
  });

  test("availability slots are hidden from clients", async () => {
    await assertFails(dbFor(guest).doc("peer_booking_slots/forged").set({
      bookingId: "server-booking",
    }));
    await assertFails(dbFor(host).doc("peer_booking_slots/forged").get());
  });
});
