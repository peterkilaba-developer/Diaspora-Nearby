/**
 * Server-managed Diaspora Direct Investment loan applications.
 *
 * Host-community DDI loans are gated by membership and PCT before voting
 * opens. During testing, voting and discussion are live while funding remains
 * pending until TGE and token collateral capacity can be evaluated.
 */
const {functions, db} = require("./shared");
const {requireAppCheck} = require("./security");

const MINIMUM_PCT_SCORE = 91;
const MINIMUM_QUORUM = 10;
const REQUIRED_APPROVAL_PERCENT = 51;
const VOTING_WINDOW_MS = 10 * 24 * 60 * 60 * 1000;
const VALID_VERDICTS = new Set(["yay", "nay", "abstain"]);
const VALID_LOAN_TYPES = new Set([
  "Business Investment",
  "Real Estate Business",
  "Education & Skills Business",
  "Agriculture & Farming Business",
  "Healthcare Business",
  "Other Local Business",
  "Investments",
  "Education and Training",
]);
const VALID_REPAYMENT_PERIODS = new Set([
  "3 months",
  "6 months",
  "12 months",
  "18 months",
  "24 months",
]);

function requireAuth(context) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "Authentication is required for DDI activity.",
    );
  }
  return context.auth.uid;
}

function requiredText(value, label, maxLength) {
  const text = typeof value === "string" ? value.trim() : "";
  if (!text || text.length > maxLength) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        `${label} is required and must be ${maxLength} characters or fewer.`,
    );
  }
  return text;
}

function documentMemberIds(community) {
  const members = Array.isArray(community.members) ?
    community.members : community.memberIds;
  return Array.isArray(members) ? members : [];
}

function isEligiblePhysicalCommunity(user, community, userId, communityId) {
  const memberships = Array.isArray(user.communityMemberships) ?
    user.communityMemberships : [];
  
  const isMember = memberships.includes(communityId) || 
                   documentMemberIds(community).includes(userId);
  return isMember;
}

function assertEligiblePhysicalCommunity(user, community, userId, communityId) {
  if (!isEligiblePhysicalCommunity(user, community, userId, communityId)) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "You must be a member of the selected community (Home or Host location) to initiate a DDI loan application.",
    );
  }
}

function discussionDetails(applicationId, businessName, communityId) {
  return {
    chatId: `ddi_discussion_${applicationId}`,
    name: `DDI Loan Discussion: ${businessName}`,
    communityId,
  };
}

function votingTally(voting) {
  return {
    yayCount: Number(voting.yayCount || 0),
    nayCount: Number(voting.nayCount || 0),
    abstainCount: Number(voting.abstainCount || 0),
    totalVotes: Number(voting.totalVotes || 0),
  };
}

function adjustTally(voting, previousVerdict, verdict) {
  const tally = votingTally(voting);
  const fields = {
    yay: "yayCount",
    nay: "nayCount",
    abstain: "abstainCount",
  };
  if (previousVerdict && fields[previousVerdict]) {
    tally[fields[previousVerdict]] -= 1;
    tally.totalVotes -= 1;
  }
  tally[fields[verdict]] += 1;
  tally.totalVotes += 1;
  return tally;
}

function resolveVotingOutcome(voting) {
  const tally = votingTally(voting);
  const quorumMet = tally.totalVotes >= MINIMUM_QUORUM;
  const approvalRate = tally.totalVotes === 0 ?
    0 : (tally.yayCount / tally.totalVotes) * 100;
  const approved = quorumMet && approvalRate >= REQUIRED_APPROVAL_PERCENT;
  return {
    ...tally,
    quorumMet,
    approvalRate,
    approved,
    outcome: approved ? "approved" : "rejected",
    status: approved ?
      "approved_pending_tge_collateral" : "rejected_by_community_vote",
  };
}

/**
 * Accepts a gated host-community business loan application and immediately
 * opens the public discussion and ten-day community vote.
 */
exports.submitDdiLoanApplication = functions.https.onCall(
    async (data, context) => {
      requireAppCheck(context);
      const applicantId = requireAuth(context);
      const input = data || {};
      const communityId = requiredText(input.communityId, "Community", 200);
      const fullLegalName = requiredText(
          input.fullLegalName,
          "Full legal name",
          160,
      );
      const purpose = requiredText(input.purpose, "Investment purpose", 2000);
      const businessName = requiredText(input.businessName, "Business name", 200);
      const businessDescription = requiredText(
          input.businessDescription,
          "Business description",
          3000,
      );
      const repaymentPlan = requiredText(
          input.repaymentPlan,
          "Repayment plan",
          2000,
      );
      const requestedAmount = Number(input.requestedAmount);
      const loanType = input.loanType;
      const repaymentPeriod = input.repaymentPeriod;

      if (!Number.isSafeInteger(requestedAmount) || requestedAmount <= 0) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Requested amount must be a positive whole number.",
        );
      }
      if (!VALID_LOAN_TYPES.has(loanType)) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Select a supported loan type.",
        );
      }
      if (!VALID_REPAYMENT_PERIODS.has(repaymentPeriod)) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Select a supported repayment period.",
        );
      }
      if (input.confirmsLocalInvestment !== true && input.confirmsHostBusiness !== true) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "Confirm that the loan will be used locally in the selected community.",
        );
      }

      const applicationRef = db.collection("ddi_loan_applications").doc();
      const discussion = discussionDetails(
          applicationRef.id,
          businessName,
          communityId,
      );
      const userRef = db.collection("users").doc(applicantId);
      const trustRef = db.collection("trust_data").doc(applicantId);
      const userPointsRef = db.collection("user_points").doc(applicantId);
      const communityRef = db.collection("communities").doc(communityId);
      const chatRef = db.collection("chats").doc(discussion.chatId);
      const discoverableRef = db.collection("discoverableChats")
          .doc(discussion.chatId);
      const userChatRef = userRef.collection("userChats").doc(discussion.chatId);
      const initialMessageRef = chatRef.collection("messages")
          .doc("application_created");

      return db.runTransaction(async (transaction) => {
        const [userSnap, trustSnap, userPointsSnap, communitySnap] =
            await Promise.all([
              transaction.get(userRef),
              transaction.get(trustRef),
              transaction.get(userPointsRef),
              transaction.get(communityRef),
            ]);
        if (!userSnap.exists) {
          throw new functions.https.HttpsError(
              "failed-precondition",
              "Complete your profile before submitting a DDI application.",
          );
        }
        if (!communitySnap.exists) {
          throw new functions.https.HttpsError(
              "not-found",
              "The selected community could not be found.",
          );
        }

        const user = userSnap.data();
        const community = communitySnap.data();
        assertEligiblePhysicalCommunity(user, community, applicantId, communityId);

        const trustData = trustSnap.exists ? trustSnap.data() : {};
        const pctScore = Number(trustData.trustScore || 0);
        if (!Number.isFinite(pctScore) || pctScore < MINIMUM_PCT_SCORE) {
          const shownScore = Number.isFinite(pctScore) ? pctScore : 0;
          throw new functions.https.HttpsError(
              "failed-precondition",
              `A PCT score of ${MINIMUM_PCT_SCORE}+ is required to apply. ` +
              `Your current score is ${shownScore}.`,
          );
        }

        // Enforce 7 Proof of Humanity (PoH) Genesis Milestones + 100+ Days Active
        const familyOk = Number(trustData.uniqueFamilyCount || 0) >= 10;
        const friendOk = Number(trustData.uniqueFriendCount || 0) >= 10;
        const qrOk = Number(trustData.uniqueQrCount || 0) >= 10;
        const verifyOk = Number(trustData.uniqueVerificationCount || 0) >= 10;
        const milestones = Array.isArray(trustData.awardedQualificationMilestones) ? trustData.awardedQualificationMilestones : [];
        const profileOk = milestones.includes("profile_complete") || milestones.includes("profileComplete") || milestones.includes("Profile");
        const emergencyFundOk = trustData.emergencyFundContributor === true ||
          trustData.isEmergencyFundContributor === true ||
          milestones.includes("emergency_fund") ||
          milestones.includes("UbuntuEmergencyFund") ||
          milestones.includes("EmergencyFund");

        let daysActive = 0;
        if (user && user.createdAt) {
          const created = user.createdAt.toDate ? user.createdAt.toDate() : new Date(user.createdAt);
          daysActive = Math.floor((Date.now() - created.getTime()) / (1000 * 60 * 60 * 24));
        }

        const isGenesisComplete = familyOk && friendOk && qrOk && verifyOk && profileOk && emergencyFundOk;
        const isSeniorityMet = daysActive >= 100;
        const isDdiEligible = trustData.isDdiEligible === true || (isGenesisComplete && isSeniorityMet && pctScore >= MINIMUM_PCT_SCORE);

        if (!isDdiEligible) {
          throw new functions.https.HttpsError(
              "failed-precondition",
              `Applying for a DDI loan requires completing all 7 Proof of Humanity (PoH) Milestones ` +
              `and being an active member for 100+ days (Your current active days: ${daysActive}).`,
          );
        }

        // 10% Token Collateral Check (Option A)
        const userPointsData = userPointsSnap.exists ? userPointsSnap.data() : {};
        const availableBalance = Number(
            userPointsData.availablePoints || userPointsData.points || 0,
        );
        const requiredCollateral = Math.ceil(requestedAmount * 0.10);
        if (availableBalance < requiredCollateral) {
          throw new functions.https.HttpsError(
              "failed-precondition",
              `Insufficient token balance for 10% collateral requirement. ` +
              `You need at least ${requiredCollateral} $DIASPORA balance as collateral ` +
              `for a ${requestedAmount} $DIASPORA loan request. (Your current balance: ${availableBalance}).`,
          );
        }

        const now = Date.now();
        const closesAt = now + VOTING_WINDOW_MS;
        const voting = {
          status: "open",
          openedAt: now,
          closesAt,
          minimumQuorum: MINIMUM_QUORUM,
          requiredApprovalPercent: REQUIRED_APPROVAL_PERCENT,
          yayCount: 0,
          nayCount: 0,
          abstainCount: 0,
          totalVotes: 0,
        };
        const metadata = {
          isDdiDiscussion: true,
          managedBy: "platform",
          ddiApplicationId: applicationRef.id,
          votingCommunityId: communityId,
        };
        const publicDescription =
              `Public discussion for ${businessName}'s DDI ` +
              `loan application in the ${community.name} community.`;
        const lastMessage = {
          id: "application_created",
          content: "DDI application submitted. Community discussion and voting are open.",
          timestamp: now,
          senderId: "system",
          senderName: "DDI",
          type: "system",
          status: "sent",
        };

        transaction.create(applicationRef, {
          applicantId,
          communityId,
          communityName: community.name || "",
          discussionChatId: discussion.chatId,
          fullLegalName,
          loanType,
          requestedAmount,
          collateralAmount: requiredCollateral,
          collateralPercentage: 10,
          collateralStatus: "locked",
          repaymentMechanism: "open_market_buyback_to_treasury",
          currency: "DIASPORA",
          purpose,
          businessName,
          businessDescription,
          repaymentPeriod,
          repaymentPlan,
          status: "voting_open",
          fundingStatus: "pending_tge_and_token_capacity",
          eligibilityStatus: "qualified_for_community_vote",
          voting,
          gates: {
            minimumPctScore: MINIMUM_PCT_SCORE,
            applicantPctScore: pctScore,
            pctPassed: true,
            eligibleCommunityMemberPassed: true,
            localInvestmentConfirmed: true,
            collateralRequired: requiredCollateral,
            collateralPassed: true,
            tokenCollateralCapacityReview: "required_after_tge",
          },
          createdAt: now,
          updatedAt: now,
        });
        transaction.create(chatRef, {
          id: discussion.chatId,
          type: "group",
          isPublic: true,
          communityId,
          locationType: community.locationType,
          name: discussion.name,
          description: publicDescription,
          category: "Business & Entrepreneurship",
          participants: [applicantId],
          memberCount: 1,
          admins: [],
          metadata,
          createdAt: now,
          updatedAt: now,
          lastMessage,
        });
        transaction.create(discoverableRef, {
          id: discussion.chatId,
          type: "group",
          isPublic: true,
          communityId,
          locationType: community.locationType,
          name: discussion.name,
          description: publicDescription,
          category: "Business & Entrepreneurship",
          memberCount: 1,
          metadata,
          createdAt: now,
        });
        transaction.create(initialMessageRef, {
          ...lastMessage,
          chatId: discussion.chatId,
          content:
            `Public discussion opened for ${businessName}. The applicant ` +
            `requested ${requestedAmount} $DIASPORA for a community ` +
            "business. Cast Yay, Nay, or Abstain from the DDI Loans screen.",
        });
        transaction.set(userChatRef, {
          chatId: discussion.chatId,
          updatedAt: now,
          addedAt: now,
          lastRead: now,
          pinned: false,
          isDeleted: false,
        }, {merge: true});

        return {
          applicationId: applicationRef.id,
          discussionChatId: discussion.chatId,
          status: "voting_open",
          pctScore,
          closesAt,
        };
      });
    },
);

/**
 * Adds a current member of the application's host community to its
 * platform-managed public discussion chat.
 */
exports.joinDdiDiscussion = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const userId = requireAuth(context);
  const chatId = requiredText(data && data.chatId, "Discussion chat", 240);
  if (!chatId.startsWith("ddi_discussion_")) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "A DDI discussion chat ID is required.",
    );
  }

  const chatRef = db.collection("chats").doc(chatId);
  const userRef = db.collection("users").doc(userId);
  const userChatRef = userRef.collection("userChats").doc(chatId);
  return db.runTransaction(async (transaction) => {
    const [chatSnap, userSnap] = await Promise.all([
      transaction.get(chatRef),
      transaction.get(userRef),
    ]);
    const chat = chatSnap.exists ? chatSnap.data() : null;
    if (!chat || chat.isPublic !== true ||
        chat.metadata?.isDdiDiscussion !== true) {
      throw new functions.https.HttpsError(
          "not-found",
          "DDI discussion not found.",
      );
    }
    if (!userSnap.exists) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Complete your profile before joining this discussion.",
      );
    }

    const communityRef = db.collection("communities").doc(chat.communityId);
    const communitySnap = await transaction.get(communityRef);
    if (!communitySnap.exists) {
      throw new functions.https.HttpsError(
          "not-found",
          "The community could not be found.",
      );
    }
    assertEligiblePhysicalCommunity(
        userSnap.data(),
        communitySnap.data(),
        userId,
        chat.communityId,
    );

    const participants = Array.isArray(chat.participants) ?
      [...chat.participants] : [];
    const alreadyJoined = participants.includes(userId);
    if (!alreadyJoined) participants.push(userId);
    const now = Date.now();
    transaction.update(chatRef, {
      participants,
      memberCount: participants.length,
      updatedAt: now,
    });
    transaction.set(db.collection("discoverableChats").doc(chatId), {
      memberCount: participants.length,
    }, {merge: true});
    transaction.set(userChatRef, {
      chatId,
      updatedAt: now,
      addedAt: now,
      lastRead: now,
      pinned: false,
      isDeleted: false,
    }, {merge: true});
    return {chatId, joined: !alreadyJoined};
  });
});

/**
 * Records or updates one community member's vote on an active loan request.
 */
exports.castDdiLoanVote = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const voterId = requireAuth(context);
  const applicationId = requiredText(
      data && data.applicationId,
      "Application",
      240,
  );
  const verdict = data && data.verdict;
  if (!VALID_VERDICTS.has(verdict)) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Vote must be yay, nay, or abstain.",
    );
  }

  const applicationRef = db.collection("ddi_loan_applications")
      .doc(applicationId);
  const voterRef = db.collection("users").doc(voterId);
  const voteRef = db.collection("ddi_loan_votes")
      .doc(`${applicationId}_${voterId}`);
  return db.runTransaction(async (transaction) => {
    const [applicationSnap, voterSnap, voteSnap] = await Promise.all([
      transaction.get(applicationRef),
      transaction.get(voterRef),
      transaction.get(voteRef),
    ]);
    if (!applicationSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Application not found.");
    }
    if (!voterSnap.exists) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Complete your profile before voting.",
      );
    }
    const application = applicationSnap.data();
    const communityRef = db.collection("communities").doc(application.communityId);
    const communitySnap = await transaction.get(communityRef);
    if (!communitySnap.exists) {
      throw new functions.https.HttpsError("not-found", "Community not found.");
    }
    assertEligiblePhysicalCommunity(
        voterSnap.data(),
        communitySnap.data(),
        voterId,
        application.communityId,
    );

    const voting = application.voting || {};
    if (voting.status !== "open") {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Voting is no longer open for this application.",
      );
    }
    if (Date.now() > Number(voting.closesAt || 0)) {
      const resolved = resolveVotingOutcome(voting);
      transaction.update(applicationRef, {
        status: resolved.status,
        "voting.status": "closed",
        "voting.outcome": resolved.outcome,
        "voting.quorumMet": resolved.quorumMet,
        "voting.approvalRate": resolved.approvalRate,
        resolvedAt: Date.now(),
        updatedAt: Date.now(),
      });
      return {closed: true, outcome: resolved.outcome, tally: resolved};
    }

    const priorVerdict = voteSnap.exists ? voteSnap.data().verdict : null;
    const tally = adjustTally(voting, priorVerdict, verdict);
    const now = Date.now();
    transaction.set(voteRef, {
      applicationId,
      communityId: application.communityId,
      voterId,
      verdict,
      createdAt: voteSnap.exists ? voteSnap.data().createdAt || now : now,
      updatedAt: now,
    });
    transaction.update(applicationRef, {
      "voting.yayCount": tally.yayCount,
      "voting.nayCount": tally.nayCount,
      "voting.abstainCount": tally.abstainCount,
      "voting.totalVotes": tally.totalVotes,
      updatedAt: now,
    });
    return {closed: false, verdict, tally};
  });
});

/**
 * Closes a vote once its ten-day window has elapsed and records its outcome.
 */
exports.resolveDdiLoanVoting = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const userId = requireAuth(context);
  const applicationId = requiredText(
      data && data.applicationId,
      "Application",
      240,
  );
  const applicationRef = db.collection("ddi_loan_applications")
      .doc(applicationId);
  const userRef = db.collection("users").doc(userId);
  return db.runTransaction(async (transaction) => {
    const [applicationSnap, userSnap] = await Promise.all([
      transaction.get(applicationRef),
      transaction.get(userRef),
    ]);
    if (!applicationSnap.exists || !userSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Application not found.");
    }
    const application = applicationSnap.data();
    const communityRef = db.collection("communities").doc(application.communityId);
    const communitySnap = await transaction.get(communityRef);
    if (!communitySnap.exists) {
      throw new functions.https.HttpsError("not-found", "Community not found.");
    }
    assertEligiblePhysicalCommunity(
        userSnap.data(),
        communitySnap.data(),
        userId,
        application.communityId,
    );

    const voting = application.voting || {};
    if (voting.status !== "open") {
      return {closed: true, outcome: voting.outcome || null};
    }
    if (Date.now() <= Number(voting.closesAt || 0)) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Voting remains open until the ten-day window ends.",
      );
    }

    const resolved = resolveVotingOutcome(voting);
    const now = Date.now();
    let cascadeInfo = null;
    if (resolved.approved) {
      try {
        cascadeInfo = await calculateHierarchicalCascade(
            application.communityId,
            application.requestedAmount,
        );
      } catch (_) {}
    }

    transaction.update(applicationRef, {
      status: resolved.status,
      fundingStatus: resolved.approved ?
        "pending_tge_and_token_capacity" : "not_approved",
      fundingCascade: cascadeInfo,
      "voting.status": "closed",
      "voting.outcome": resolved.outcome,
      "voting.quorumMet": resolved.quorumMet,
      "voting.approvalRate": resolved.approvalRate,
      resolvedAt: now,
      updatedAt: now,
    });
    return {
      closed: true,
      outcome: resolved.outcome,
      tally: resolved,
      fundingCascade: cascadeInfo,
    };
  });
});

/**
 * Calculates the upward cascading treasury breakdown for funding a DDI loan.
 * Cascade order:
 *  1. Local Town DDI Treasury
 *  2. State Reserve Treasury (backstop to Town)
 *  3. Country DDI Treasury (sovereign DDI pool)
 *  4. Global Reserve (final global backstop)
 *
 * Note: Continental Sovereign Bond Treasuries are 100% dedicated to
 * Funding the Sovereign Bond Engine and do not participate in DDI loan cascades.
 */
async function calculateHierarchicalCascade(communityId, requestedAmount) {
  const cascadeTiers = [];
  let remainingNeeded = Number(requestedAmount) || 0;

  // 1. Fetch initial community
  let commSnap = null;
  if (communityId && communityId !== "global_community") {
    commSnap = await db.collection("communities").doc(communityId).get();
  }
  const commData = commSnap && commSnap.exists ? commSnap.data() : null;

  // Build hierarchy list
  const tierPlan = [];
  if (commData) {
    const locType = commData.locationType || (communityId.includes("_home_") ? "home" : "host");
    const city = commData.city || commData.name;
    const state = commData.state || commData.stateProvince;
    const country = commData.country || commData.homeCountryCode || commData.countryCode;

    // Tier 1: Town DDI
    if (commData.type === "city" || commData.type === "town") {
      tierPlan.push({
        tier: "town_ddi",
        name: `${commData.name || city} DDI Treasury`,
        communityId: communityId,
        type: "town",
      });
    }

    // Tier 2: State Reserve
    if (state) {
      const stateId = `${locType}_state_${state.toLowerCase().replace(/[^a-z0-9]/g, "_")}`;
      tierPlan.push({
        tier: "state_reserve",
        name: `${state} Reserve Treasury`,
        communityId: stateId,
        type: "state_reserve",
      });
    }

    // Tier 3: Country DDI
    if (country) {
      const countryId = `${locType}_country_${country.toLowerCase().replace(/[^a-z0-9]/g, "_")}`;
      tierPlan.push({
        tier: "country_ddi",
        name: `${country} DDI Treasury`,
        communityId: countryId,
        type: "country",
      });
    }
  }

  // Query balances for each tier and allocate
  let totalAvailable = 0;
  for (const item of tierPlan) {
    let balance = 0;
    try {
      const doc = await db.collection("communities").doc(item.communityId).get();
      if (doc.exists) {
        const d = doc.data();
        balance = Number(d.treasuryBalance || d.dspBalance || d.points || 0);
      }
    } catch (_) {}

    totalAvailable += balance;
    const allocated = Math.min(remainingNeeded, balance);
    remainingNeeded -= allocated;

    cascadeTiers.push({
      tier: item.tier,
      name: item.name,
      communityId: item.communityId,
      type: item.type,
      availableBalance: balance,
      allocatedAmount: allocated,
    });
  }

  return {
    requestedAmount: Number(requestedAmount),
    totalAvailableAcrossHierarchy: totalAvailable,
    isFullyFunded: remainingNeeded <= 0,
    shortfall: Math.max(0, remainingNeeded),
    cascadeBreakdown: cascadeTiers,
  };
}

/**
 * getDdiFundingCascade — Callable function to evaluate upward cascading
 * liquidity for a DDI loan application or community.
 */
exports.getDdiFundingCascade = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  requireAuth(context);
  const input = data || {};
  let communityId = input.communityId;
  let requestedAmount = Number(input.requestedAmount || 0);

  if (input.applicationId) {
    const appDoc = await db.collection("ddi_loan_applications").doc(input.applicationId).get();
    if (appDoc.exists) {
      const appData = appDoc.data();
      communityId = communityId || appData.communityId;
      requestedAmount = requestedAmount || Number(appData.requestedAmount || 0);
    }
  }

  if (!communityId) {
    throw new functions.https.HttpsError("invalid-argument", "communityId or applicationId is required.");
  }

  return calculateHierarchicalCascade(communityId, requestedAmount);
});

exports.calculateHierarchicalCascade = calculateHierarchicalCascade;

