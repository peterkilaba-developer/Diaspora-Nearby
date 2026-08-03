/**
 * Server-managed governance mutations.
 * Structural council updates are performed with the Admin SDK so clients
 * cannot appoint or remove leaders by writing governance documents directly.
 */
const {functions, admin, db} = require("./shared");

const VALID_ROLES = new Set([
  "president",
  "treasurer",
  "secretary",
  "council_member",
]);

function requireAuth(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be signed in.",
    );
  }
  return context.auth.uid;
}

function validateRole(role) {
  if (typeof role !== "string" || !VALID_ROLES.has(role)) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Invalid governance role.",
    );
  }
}

function tallyVotes(snapshot) {
  let yay = 0;
  let nay = 0;
  let abstain = 0;
  snapshot.docs.forEach((doc) => {
    switch (doc.data().verdict) {
      case "yay":
        yay += 1;
        break;
      case "nay":
        nay += 1;
        break;
      case "abstain":
        abstain += 1;
        break;
      default:
        break;
    }
  });
  return {
    yay,
    nay,
    abstain,
    total: yay + nay + abstain,
    decisive: yay + nay,
  };
}

/**
 * Registers the authenticated, qualified user for a council role.
 */
exports.nominateForGovernanceRole = functions.https.onCall(
    async (data, context) => {
      const userId = requireAuth(context);
      const {unitId, role} = data || {};
      if (typeof unitId !== "string" || unitId.length === 0) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "A governance unit is required.",
        );
      }
      validateRole(role);

      const trustSnap = await db.collection("trust_data").doc(userId).get();
      if (!trustSnap.exists || trustSnap.data().isCouncilEligible !== true) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "You do not meet the candidacy eligibility requirements.",
        );
      }

      const unitRef = db.collection("governance").doc(unitId);
      await db.runTransaction(async (transaction) => {
        const unitSnap = await transaction.get(unitRef);
        if (!unitSnap.exists) {
          throw new functions.https.HttpsError(
              "not-found",
              "Governance unit not found.",
          );
        }

        const unit = unitSnap.data();
        const candidates = {...(unit.roleCandidates || {})};
        const alreadyRunning = Object.values(candidates)
            .some((ids) => Array.isArray(ids) && ids.includes(userId));
        if (alreadyRunning) {
          throw new functions.https.HttpsError(
              "already-exists",
              "You are already running for a council role.",
          );
        }

        candidates[role] = [...(candidates[role] || []), userId];
        const updates = {
          roleCandidates: candidates,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        if (unit.isActiveElection !== true) {
          updates.isActiveElection = true;
          updates.electionEndTime =
            Date.now() + (365 * 100 * 24 * 60 * 60 * 1000);
        }
        transaction.update(unitRef, updates);
      });

      return {success: true};
    },
);

async function getVoteTally(unitId, candidateId, role) {
  const snapshot = await db.collection("governance_votes")
      .where("unitId", "==", unitId)
      .where("candidateId", "==", candidateId)
      .where("role", "==", role)
      .get();
  return tallyVotes(snapshot);
}

/**
 * Reconciles council state after a vote using persisted vote documents.
 */
exports.evaluateGovernanceVote = functions.https.onCall(
    async (data, context) => {
      requireAuth(context);
      const {unitId, candidateId, role} = data || {};
      if (typeof unitId !== "string" || typeof candidateId !== "string") {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Governance unit and candidate are required.",
        );
      }
      validateRole(role);

      const unitRef = db.collection("governance").doc(unitId);
      const unitSnap = await unitRef.get();
      if (!unitSnap.exists) {
        throw new functions.https.HttpsError(
            "not-found",
            "Governance unit not found.",
        );
      }

      const unit = unitSnap.data();
      const roleCandidates = unit.roleCandidates || {};
      const currentCouncil = Array.isArray(unit.councilMembers) ?
        unit.councilMembers : [];
      const isRegisteredCandidate =
        Array.isArray(roleCandidates[role]) &&
        roleCandidates[role].includes(candidateId);
      const isExistingCouncilMember = currentCouncil.includes(candidateId);
      if (!isRegisteredCandidate && !isExistingCouncilMember) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "Votes can only be evaluated for registered candidates.",
        );
      }

      const communityId = unit.communityId;
      const communityRef = communityId ?
        db.collection("communities").doc(communityId) : null;
      const communitySnap = communityRef ? await communityRef.get() : null;
      const totalMembers = communitySnap && communitySnap.exists ?
        Number(communitySnap.data().memberCount || 0) : 0;
      if (totalMembers < 4) {
        return {promoted: false, removedMembers: []};
      }

      const tally = await getVoteTally(unitId, candidateId, role);
      const quorumTarget = Math.ceil(totalMembers * 0.5);
      const wins = tally.total >= quorumTarget &&
        tally.decisive > 0 &&
        (tally.yay / tally.decisive) > 0.5;

      const removals = [];
      for (const memberId of currentCouncil) {
        const memberRole = (unit.councilRoles || {})[memberId];
        if (!memberRole) continue;
        // Continuous position in leadership is tracked by PCT (trust slider score),
        // not actual votes (which are only used to elect candidates into office).
        const trustSnap = await db.collection("trust_data").doc(memberId).get();
        const isEligibleByTrustSlider =
          trustSnap.exists && trustSnap.data().isCouncilEligible === true;
        if (!isEligibleByTrustSlider) {
          removals.push({userId: memberId, role: memberRole});
        }
      }

      let promoted = false;
      await db.runTransaction(async (transaction) => {
        const latestSnap = await transaction.get(unitRef);
        if (!latestSnap.exists) {
          throw new functions.https.HttpsError(
              "not-found",
              "Governance unit not found.",
          );
        }
        const latest = latestSnap.data();
        const members = Array.isArray(latest.councilMembers) ?
          [...latest.councilMembers] : [];
        const roles = {...(latest.councilRoles || {})};
        const latestCommunitySnap = communityRef ?
          await transaction.get(communityRef) : null;
        const admins = latestCommunitySnap && latestCommunitySnap.exists &&
          Array.isArray(latestCommunitySnap.data().admins) ?
          [...latestCommunitySnap.data().admins] : [];

        if (wins && !members.includes(candidateId)) {
          members.push(candidateId);
          roles[candidateId] = role;
          promoted = true;
          if (!admins.includes(candidateId)) admins.push(candidateId);
        }

        removals.forEach(({userId}) => {
          const index = members.indexOf(userId);
          if (index >= 0) members.splice(index, 1);
          delete roles[userId];
          const adminIndex = admins.indexOf(userId);
          if (adminIndex >= 0) admins.splice(adminIndex, 1);
        });

        transaction.update(unitRef, {
          councilMembers: members,
          councilRoles: roles,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        if (latestCommunitySnap && latestCommunitySnap.exists &&
            (promoted || removals.length > 0)) {
          transaction.update(communityRef, {admins});
        }
      });

      return {promoted, removedMembers: removals, tally};
    },
);
