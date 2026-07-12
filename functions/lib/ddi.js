/**
 * Server-managed Diaspora Direct Investment loan applications.
 *
 * Host-community DDI loans are gated by membership and PoCT before voting
 * opens. During testing, voting and discussion are live while funding remains
 * pending until TGE and token collateral capacity can be evaluated.
 */
const {functions, db} = require("./shared");

const MINIMUM_POCT_SCORE = 91;
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

function isHostCommunityMember(user, community, userId, communityId) {
  const memberships = Array.isArray(user.communityMemberships) ?
    user.communityMemberships : [];
  return community.locationType === "host" &&
    (memberships.includes(communityId) ||
      documentMemberIds(community).includes(userId));
}

function assertHostCommunityMember(user, community, userId, communityId) {
  if (community.locationType !== "host") {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "DDI loans are available only through your host community.",
    );
  }
  if (!isHostCommunityMember(user, community, userId, communityId)) {
    throw new functions.https.HttpsError(
        "permission-denied",
        "You must be a member of this host community to participate.",
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
            "Select a supported host-community business loan type.",
        );
      }
      if (!VALID_REPAYMENT_PERIODS.has(repaymentPeriod)) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Select a supported repayment period.",
        );
      }
      if (input.confirmsHostBusiness !== true) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "Confirm that the business operates in the selected host community.",
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
      const communityRef = db.collection("communities").doc(communityId);
      const chatRef = db.collection("chats").doc(discussion.chatId);
      const discoverableRef = db.collection("discoverableChats")
          .doc(discussion.chatId);
      const userChatRef = userRef.collection("userChats").doc(discussion.chatId);
      const initialMessageRef = chatRef.collection("messages")
          .doc("application_created");

      return db.runTransaction(async (transaction) => {
        const [userSnap, trustSnap, communitySnap] = await Promise.all([
          transaction.get(userRef),
          transaction.get(trustRef),
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
        assertHostCommunityMember(user, community, applicantId, communityId);

        const trustData = trustSnap.exists ? trustSnap.data() : {};
        const poctScore = Number(trustData.trustScore || 0);
        if (!Number.isFinite(poctScore) || poctScore < MINIMUM_POCT_SCORE) {
          const shownScore = Number.isFinite(poctScore) ? poctScore : 0;
          throw new functions.https.HttpsError(
              "failed-precondition",
              `A PoCT score of ${MINIMUM_POCT_SCORE}+ is required to apply. ` +
              `Your current score is ${shownScore}.`,
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
          `Public discussion for ${businessName}'s host-community DDI ` +
          `application in ${community.name || "this community"}.`;
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
            minimumPoctScore: MINIMUM_POCT_SCORE,
            applicantPoctScore: poctScore,
            poctPassed: true,
            hostCommunityMemberPassed: true,
            hostBusinessConfirmed: true,
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
          locationType: "host",
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
          locationType: "host",
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
            `requested ${requestedAmount} $DIASPORA for a host-community ` +
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
          poctScore,
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
          "The host community could not be found.",
      );
    }
    assertHostCommunityMember(
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
    assertHostCommunityMember(
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
    assertHostCommunityMember(
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
    transaction.update(applicationRef, {
      status: resolved.status,
      fundingStatus: resolved.approved ?
        "pending_tge_and_token_capacity" : "not_approved",
      "voting.status": "closed",
      "voting.outcome": resolved.outcome,
      "voting.quorumMet": resolved.quorumMet,
      "voting.approvalRate": resolved.approvalRate,
      resolvedAt: now,
      updatedAt: now,
    });
    return {closed: true, outcome: resolved.outcome, tally: resolved};
  });
});
