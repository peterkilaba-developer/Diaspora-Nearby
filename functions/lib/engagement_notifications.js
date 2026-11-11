/**
 * Engagement push notifications.
 *
 * Server-side Firestore triggers + schedulers that turn engagement-worthy
 * actions into a push notification AND an entry in the in-app Notifications
 * hub (`users/{uid}/notifications`). These replace the old client-side
 * snapshot listeners, which only fired while the app was open in the
 * foreground — so recipients with a closed/backgrounded app never heard about
 * relationship requests, bookings, hosting offers, event changes, etc.
 *
 * Every send goes through `notifyUser`, which is idempotent per `dedupKey`
 * (safe under trigger retries), respects `notificationsEnabled === false`,
 * and prunes dead FCM tokens.
 */
const { functions, db, notifyUser, notifyUsers, sendPushToTopic } = require("./shared");

const MAX_BROADCAST = 500;
const DAY_MS = 24 * 60 * 60 * 1000;

// ─── Helpers ────────────────────────────────────────────────────────────────

function validId(value) {
  return typeof value === "string" && /^[A-Za-z0-9_-]{1,256}$/.test(value);
}

function displayName(profile, fallback = "A member") {
  if (!profile) return fallback;
  const explicit = String(profile.fullName || profile.displayName || "").trim();
  const composed = [profile.firstName, profile.lastName]
    .map((part) => String(part || "").trim())
    .filter(Boolean)
    .join(" ");
  return (explicit || composed || fallback).slice(0, 100);
}

function firstName(profile, fallback = "Someone") {
  if (!profile) return fallback;
  const first = String(profile.firstName || "").trim();
  return (first || displayName(profile, fallback).split(" ")[0] || fallback).slice(0, 60);
}

async function getProfile(uid) {
  if (!validId(uid)) return null;
  try {
    const snap = await db.collection("users").doc(uid).get();
    return snap.exists ? snap.data() : null;
  } catch (_) {
    return null;
  }
}

async function getCommunity(communityId) {
  if (!validId(communityId)) return null;
  const snap = await db.collection("communities").doc(communityId).get();
  return snap.exists ? snap.data() : null;
}

function communityMemberIds(community) {
  if (!community) return [];
  return [...new Set([
    ...(Array.isArray(community.members) ? community.members : []),
    ...(Array.isArray(community.memberIds) ? community.memberIds : []),
  ].filter(validId))];
}

function asList(value) {
  return Array.isArray(value) ? value.filter(validId) : [];
}

function added(beforeList, afterList) {
  const before = new Set(asList(beforeList));
  return asList(afterList).filter((id) => !before.has(id));
}

function toMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value === "number") return value;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function formatDate(value) {
  const ms = toMillis(value);
  if (!ms) return "";
  return new Date(ms).toLocaleDateString("en-US", {
    month: "short", day: "numeric", timeZone: "UTC",
  });
}

function formatDateRange(start, end) {
  const a = formatDate(start);
  const b = formatDate(end);
  if (a && b) return `${a} – ${b}`;
  return a || b;
}

function utcDateKey(ms) {
  return new Date(ms).toISOString().slice(0, 10);
}

function citySlug(city) {
  return String(city || "")
    .toLowerCase()
    .replace(/\s+/g, "_")
    .replace(/[^a-z0-9_]/g, "");
}

function capitalize(text) {
  const value = String(text || "");
  return value ? value.charAt(0).toUpperCase() + value.slice(1) : value;
}

function eventWhen(event) {
  const date = String(event.startDate || "").slice(0, 10);
  const time = String(event.startTime || "").slice(0, 5);
  if (!date) return "";
  const pretty = formatDate(`${date}T00:00:00Z`);
  return time && time !== "00:00" ? `${pretty} at ${time}` : pretty;
}

function eventCreator(event) {
  return event.creatorId || event.createdBy || null;
}

function isEventVisible(event) {
  return event && event.status !== "hidden" && event.status !== "cancelled" &&
    event.status !== "deleted";
}

// ─── 1. Relationship requests ───────────────────────────────────────────────

exports.onRelationshipRequestNotify = functions.firestore
  .document("relationship_requests/{requestId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;
    const after = change.after.data();
    const before = change.before.exists ? change.before.data() : null;
    const requestId = context.params.requestId;
    const relType = String(after.relationshipType || "relative");

    // New (or re-opened) pending request → recipient.
    if (after.status === "pending" && (!before || before.status !== "pending")) {
      const fromName = after.fromUserName || "Someone";
      const stamp = toMillis(after.timestamp) || Date.now();
      await notifyUser(after.toUserId, {
        type: "relationship_request",
        title: "New relationship request",
        body: `${fromName} wants to add you as their ${relType.toLowerCase()}. Tap to review.`,
        targetUserId: after.fromUserId,
        dedupKey: `relationship_request_${requestId}_${stamp}`,
        additionalData: {
          fromUserId: after.fromUserId,
          fromUserName: fromName,
          relationshipType: relType,
          requestId,
        },
        inApp: {
          type: "relationshipRequest",
          actionRequired: true,
          payload: { fromUserId: after.fromUserId, requestId },
        },
      });
    }

    // Accepted → original sender.
    if (after.status === "accepted" && before && before.status === "pending") {
      const toName = after.toUserName || "Your connection";
      await notifyUser(after.fromUserId, {
        type: "relationship_accepted",
        title: "Relationship accepted 🎉",
        body: `${toName} accepted your ${relType.toLowerCase()} request. Tap to start chatting!`,
        targetUserId: after.toUserId,
        dedupKey: `relationship_accepted_${requestId}`,
        additionalData: { chatId: after.chatId || "", requestId },
        inApp: {
          type: "relationshipAccepted",
          payload: { chatId: after.chatId || "", requestId },
        },
      });
    }
    return null;
  });

// ─── 2. Emergency-fund proxy requests ───────────────────────────────────────

exports.onProxyRequestNotify = functions.firestore
  .document("proxy_requests/{requestId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;
    const after = change.after.data();
    const before = change.before.exists ? change.before.data() : null;
    const requestId = context.params.requestId;

    if (after.status === "pending" && (!before || before.status !== "pending")) {
      const stamp = toMillis(after.createdAt) || Date.now();
      await notifyUser(after.toUserId, {
        type: "proxy_request",
        title: "Emergency Fund proxy request",
        body: `${after.fromUserName || "A member"} asked you to be their Emergency Fund proxy. Tap to respond.`,
        targetUserId: after.fromUserId,
        dedupKey: `proxy_request_${requestId}_${stamp}`,
        additionalData: { requestId, fromUserId: after.fromUserId },
        inApp: { type: "proxyRequest", actionRequired: true, payload: { requestId } },
      });
    }

    if (before && before.status === "pending" &&
        (after.status === "accepted" || after.status === "rejected")) {
      const proxyName = displayName(await getProfile(after.toUserId), "Your proxy");
      const accepted = after.status === "accepted";
      await notifyUser(after.fromUserId, {
        type: "proxy_response",
        title: accepted ? "Proxy request accepted" : "Proxy request declined",
        body: accepted ?
          `${proxyName} agreed to be your Emergency Fund proxy. Complete your membership to stay covered.` :
          `${proxyName} declined your Emergency Fund proxy request. You can choose someone else.`,
        targetUserId: after.toUserId,
        route: "/dsp/emergency-fund",
        dedupKey: `proxy_response_${requestId}_${after.status}_${toMillis(after.respondedAt) || ""}`,
        inApp: { type: "system" },
      });
    }
    return null;
  });

// ─── 3. Hosting requests (traveler ↔ potential hosts) ───────────────────────

exports.onHostingRequestNotify = functions.firestore
  .document("hosting_requests/{requestId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;
    const after = change.after.data();
    const before = change.before.exists ? change.before.data() : null;
    const requestId = context.params.requestId;
    const communityName = after.communityName || "your community";
    const travelerName = after.travelerName || "A traveler";

    // New request → every other member of the community is a potential host.
    if (!before && after.status === "pending") {
      const community = await getCommunity(after.communityId);
      const recipients = communityMemberIds(community)
        .filter((uid) => uid !== after.travelerId);
      const when = formatDateRange(after.arrivalDate, after.departureDate);
      const guests = Number(after.guestCount || 1);
      await notifyUsers(recipients, () => ({
        type: "hosting_request_new",
        title: `${travelerName} needs a host in ${communityName}`,
        body: `${when ? `${when} · ` : ""}${guests} guest${guests === 1 ? "" : "s"}. ` +
          "Offer to host and grow your trust score.",
        targetUserId: after.travelerId,
        route: `/hosting/request/${requestId}`,
        dedupKey: `hosting_request_new_${requestId}`,
        additionalData: { requestId, communityId: after.communityId || "" },
        androidCollapseKey: "hosting_request_new",
        apnsThreadId: "hosting_request_new",
        inApp: { type: "system", payload: { requestId } },
      }), { max: MAX_BROADCAST });
    }

    // New host interest → traveler.
    if (before) {
      const newHosts = added(before.interestedHostIds, after.interestedHostIds)
        .filter((uid) => uid !== after.travelerId)
        .slice(0, 10);
      const total = asList(after.interestedHostIds).length;
      for (const hostId of newHosts) {
        const hostName = displayName(await getProfile(hostId), "A host");
        const others = total - 1;
        await notifyUser(after.travelerId, {
          type: "hosting_interest",
          title: `${hostName} wants to host you!`,
          body: others > 0 ?
            `${hostName} and ${others} other${others > 1 ? "s" : ""} offered to host you in ${communityName}. Tap to review.` :
            `${hostName} offered to host you in ${communityName}. Tap to review.`,
          targetUserId: hostId,
          route: `/hosting/request/${requestId}`,
          dedupKey: `hosting_interest_${requestId}_${hostId}`,
          additionalData: { requestId, hostId, hostName },
          inApp: {
            type: "hostingInterest",
            actionRequired: true,
            payload: { requestId, hostId, hostName },
          },
        });
      }
    }
    return null;
  });

// ─── 4. Hosting sessions (selected host, end-of-stay, settlement) ──────────

exports.onHostingSessionNotify = functions.firestore
  .document("hosting_sessions/{sessionId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;
    const after = change.after.data();
    const before = change.before.exists ? change.before.data() : null;
    const sessionId = context.params.sessionId;
    const chatId = after.chatId || "";
    const communityName = after.communityName || "the community";
    const travelerName = after.travelerName || "The traveler";
    const hostName = after.hostName || "Your host";
    const type = chatId ? "hosting_session_chat" : "hosting_session";
    const baseData = { chatId, sessionId };

    if (!before) {
      await notifyUser(after.hostId, {
        type,
        title: "You've been selected as host! 🏡",
        body: `${travelerName} chose you as their host in ${communityName}. Tap to view the arrangement.`,
        targetUserId: after.travelerId,
        dedupKey: `host_selected_${sessionId}`,
        additionalData: baseData,
        inApp: {
          type: "hostingSelected",
          actionRequired: true,
          payload: { ...baseData, travelerId: after.travelerId || "" },
        },
      });
      return null;
    }

    if (before.status === after.status) return null;
    const otherOf = (uid) => (uid === after.hostId ? after.travelerId : after.hostId);
    const nameOf = (uid) => (uid === after.hostId ? hostName : travelerName);

    if (after.status === "active") {
      await notifyUser(after.hostId, {
        type,
        title: "Check-in confirmed ✅",
        body: `${travelerName}'s stay in ${communityName} has started. Make them feel at home!`,
        targetUserId: after.travelerId,
        dedupKey: `session_${sessionId}_active`,
        additionalData: baseData,
        inApp: { type: "hostingSessionEvent", payload: { ...baseData, status: "active" } },
      });
    } else if (after.status === "endRequested" && validId(after.endRequestedBy)) {
      const recipient = otherOf(after.endRequestedBy);
      await notifyUser(recipient, {
        type,
        title: "Confirm end of stay",
        body: `${nameOf(after.endRequestedBy)} asked to end the hosting session in ${communityName}. Tap to confirm.`,
        targetUserId: after.endRequestedBy,
        dedupKey: `session_${sessionId}_endRequested_${toMillis(after.endRequestedAt) || ""}`,
        additionalData: baseData,
        inApp: {
          type: "hostingSessionEvent",
          actionRequired: true,
          payload: { ...baseData, status: "endRequested" },
        },
      });
    } else if (after.status === "settled") {
      await Promise.all([after.hostId, after.travelerId].filter(validId).map((uid) => notifyUser(uid, {
        type,
        title: "Stay complete 🎉",
        body: uid === after.hostId ?
          `Thanks for hosting ${travelerName} in ${communityName}! Your trust score just grew.` :
          `Your stay with ${hostName} in ${communityName} is complete. Your trust score just grew.`,
        targetUserId: otherOf(uid),
        dedupKey: `session_${sessionId}_settled`,
        additionalData: baseData,
        inApp: { type: "hostingSessionEvent", payload: { ...baseData, status: "settled" } },
      })));
    } else if (after.status === "cancelled") {
      const recipients = validId(after.cancelledBy) ?
        [otherOf(after.cancelledBy)] : [after.hostId, after.travelerId];
      await Promise.all(recipients.filter(validId).map((uid) => notifyUser(uid, {
        type,
        title: "Hosting arrangement cancelled",
        body: `The hosting arrangement in ${communityName} between ${travelerName} and ${hostName} was cancelled.`,
        targetUserId: otherOf(uid),
        dedupKey: `session_${sessionId}_cancelled`,
        additionalData: baseData,
        inApp: { type: "hostingSessionEvent", payload: { ...baseData, status: "cancelled" } },
      })));
    }
    return null;
  });

// ─── 5. Peer stay / car bookings ────────────────────────────────────────────

exports.onPeerBookingNotify = functions.firestore
  .document("peer_bookings/{bookingId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;
    const after = change.after.data();
    const before = change.before.exists ? change.before.data() : null;
    const bookingId = context.params.bookingId;
    const listingTitle = after.listingTitle || "your listing";
    const dates = formatDateRange(after.startDate, after.endDate);
    const chatId = after.chatId || "";
    const data = { bookingId, chatId, listingId: after.listingId || "" };

    if (!before && after.status === "pending") {
      await notifyUser(after.hostId, {
        type: "travel_booking_request",
        title: "New booking request",
        body: `${after.guestName || "A guest"} wants to book ${listingTitle}${dates ? ` (${dates})` : ""}. Tap to respond.`,
        targetUserId: after.guestId,
        dedupKey: `booking_request_${bookingId}`,
        additionalData: data,
        inApp: {
          type: "travelBookingRequest",
          actionRequired: true,
          payload: { ...data, guestId: after.guestId || "" },
        },
      });
      return null;
    }
    if (!before || before.status === after.status) return null;

    const hostName = after.hostName || "The host";
    const guestName = after.guestName || "The guest";
    switch (after.status) {
      case "confirmed":
        await notifyUser(after.guestId, {
          type: "travel_booking_confirmed",
          title: "Booking confirmed! 🎉",
          body: `${hostName} confirmed your booking for ${listingTitle}${dates ? ` (${dates})` : ""}.`,
          targetUserId: after.hostId,
          dedupKey: `booking_${bookingId}_confirmed`,
          additionalData: data,
          inApp: { type: "travelBookingConfirmed", payload: data },
        });
        break;
      case "rejected":
      case "declined":
        await notifyUser(after.guestId, {
          type: "travel_booking_declined",
          title: "Booking declined",
          body: `${hostName} couldn't accept your booking for ${listingTitle}. Explore other stays nearby.`,
          targetUserId: after.hostId,
          dedupKey: `booking_${bookingId}_declined`,
          additionalData: data,
          inApp: { type: "travelBookingDeclined", payload: data },
        });
        break;
      case "cancelled": {
        const recipients = after.cancelledBy === after.guestId ? [after.hostId] :
          after.cancelledBy === after.hostId ? [after.guestId] : [after.hostId, after.guestId];
        await Promise.all(recipients.filter(validId).map((uid) => notifyUser(uid, {
          type: "travel_booking_cancelled",
          title: "Booking cancelled",
          body: uid === after.hostId ?
            `${guestName} cancelled their booking for ${listingTitle}${dates ? ` (${dates})` : ""}.` :
            `Your booking for ${listingTitle}${dates ? ` (${dates})` : ""} was cancelled.`,
          targetUserId: uid === after.hostId ? after.guestId : after.hostId,
          dedupKey: `booking_${bookingId}_cancelled`,
          additionalData: data,
          inApp: { type: "travelBookingCancelled", payload: data },
        })));
        break;
      }
      case "completed":
        await notifyUser(after.guestId, {
          type: "travel_booking_completed",
          title: "How was your stay?",
          body: `Your booking at ${listingTitle} is complete. Thanks for staying with ${hostName}!`,
          targetUserId: after.hostId,
          dedupKey: `booking_${bookingId}_completed`,
          additionalData: data,
          inApp: { type: "system", payload: data },
          route: chatId ? `/chats/${chatId}` : "/dsp/travel/stays",
        });
        break;
    }
    return null;
  });

// ─── 6. Events (invites, nearby, changes, RSVPs) ────────────────────────────

async function notifyEventInvitees(eventId, event, inviteeIds) {
  const creatorId = eventCreator(event);
  const recipients = inviteeIds.filter((uid) => uid !== creatorId);
  if (!recipients.length) return;
  const creatorName = displayName(await getProfile(creatorId), "Someone");
  const when = eventWhen(event);
  await notifyUsers(recipients, () => ({
    type: "event_new",
    title: `You're invited: ${event.title || "an event"}`,
    body: `${creatorName} invited you${when ? ` · ${when}` : ""}${event.location ? ` · ${event.location}` : ""}. Tap to RSVP.`,
    targetUserId: creatorId || "",
    dedupKey: `event_invite_${eventId}`,
    additionalData: { eventId },
    inApp: { type: "eventNew", actionRequired: true, payload: { eventId } },
  }), { max: MAX_BROADCAST });
}

exports.onEventNotify = functions.firestore
  .document("events/{eventId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;
    const after = change.after.data();
    const before = change.before.exists ? change.before.data() : null;
    const eventId = context.params.eventId;
    const creatorId = eventCreator(after);
    const title = after.title || "An event";

    if (!before) {
      if (!isEventVisible(after)) return null;
      await notifyEventInvitees(eventId, after, asList(after.invitedUserIds));

      // Public upcoming event → "new event near you" for the host city topic.
      const isPublic = after.isPrivate !== true && after.attendingPermission !== "private";
      const slug = citySlug(after.hostCity || after.venueCity);
      const startsToday = String(after.startDate || "") >= utcDateKey(Date.now() - DAY_MS);
      if (isPublic && slug && startsToday) {
        const when = eventWhen(after);
        await sendPushToTopic(`city_${slug}`, {
          type: "event_new",
          title: `New event in ${after.hostCity || after.venueCity}: ${title}`,
          body: `${when ? `${when} · ` : ""}${after.location || after.venueName || "Tap for details"}`,
          additionalData: { eventId, creatorId: creatorId || "" },
          androidCollapseKey: `event_new_${slug}`,
          apnsThreadId: "event_new",
        });
      }
      return null;
    }

    // Newly invited users.
    const newInvitees = added(before.invitedUserIds, after.invitedUserIds);
    if (newInvitees.length && isEventVisible(after)) {
      await notifyEventInvitees(eventId, after, newInvitees);
    }

    const attendees = asList(after.attendees).filter((uid) => uid !== creatorId);

    // Cancelled → everyone who RSVP'd.
    if (after.status === "cancelled" && before.status !== "cancelled") {
      await notifyUsers(attendees, () => ({
        type: "event_cancelled",
        title: "Event cancelled",
        body: `"${title}" has been cancelled by the organizer.`,
        targetUserId: creatorId || "",
        dedupKey: `event_cancelled_${eventId}`,
        additionalData: { eventId },
        inApp: { type: "eventCancelled", payload: { eventId } },
      }), { max: MAX_BROADCAST });
      return null;
    }

    // Time / place changed → everyone who RSVP'd.
    const watched = ["startDate", "startTime", "location", "venueName", "venueAddress"];
    const changed = watched.filter((key) => String(before[key] || "") !== String(after[key] || ""));
    if (changed.length && isEventVisible(after)) {
      const version = watched.map((key) => String(after[key] || "")).join("|");
      const when = eventWhen(after);
      const timeChanged = changed.some((key) => key.startsWith("start"));
      await notifyUsers(attendees, () => ({
        type: "event_update",
        title: `Event updated: ${title}`,
        body: timeChanged && when ?
          `New time: ${when}${after.location ? ` · ${after.location}` : ""}.` :
          `New location: ${after.location || after.venueName || after.venueAddress || "see details"}.`,
        targetUserId: creatorId || "",
        dedupKey: `event_update_${eventId}_${version}`,
        additionalData: { eventId },
        inApp: { type: "eventUpdate", payload: { eventId } },
      }), { max: MAX_BROADCAST });
    }

    // New RSVPs → organizer.
    if (validId(creatorId)) {
      const newAttendees = added(before.attendees, after.attendees)
        .filter((uid) => uid !== creatorId);
      if (newAttendees.length === 1) {
        const name = displayName(await getProfile(newAttendees[0]), "Someone");
        await notifyUser(creatorId, {
          type: "event_new_attendee",
          title: `${name} is going to ${title}`,
          body: `${asList(after.attendees).length} people are now attending. Tap to see who's coming.`,
          targetUserId: newAttendees[0],
          dedupKey: `event_attendee_${eventId}_${newAttendees[0]}`,
          additionalData: { eventId },
          androidCollapseKey: `event_attendee_${eventId}`,
          androidTag: `event_attendee_${eventId}`,
          apnsThreadId: `event_attendee_${eventId}`,
          inApp: { type: "eventNewAttendee", payload: { eventId } },
        });
      } else if (newAttendees.length > 1) {
        await notifyUser(creatorId, {
          type: "event_new_attendee",
          title: `${newAttendees.length} new people are going to ${title}`,
          body: `${asList(after.attendees).length} people are now attending. Tap to see who's coming.`,
          dedupKey: `event_attendee_${eventId}_${newAttendees.sort().join("_").slice(0, 400)}`,
          additionalData: { eventId },
          androidCollapseKey: `event_attendee_${eventId}`,
          androidTag: `event_attendee_${eventId}`,
          apnsThreadId: `event_attendee_${eventId}`,
          inApp: { type: "eventNewAttendee", payload: { eventId } },
        });
      }
    }
    return null;
  });

/**
 * Day-before event reminders for attendees, plus a nudge to "interested"
 * users who haven't RSVP'd yet. Runs daily; dedup keys prevent repeats.
 */
exports.eventReminderCron = functions
  .runWith({ timeoutSeconds: 300, memory: "256MB" })
  .pubsub.schedule("every day 15:00")
  .timeZone("UTC")
  .onRun(async () => {
    const tomorrow = utcDateKey(Date.now() + DAY_MS);
    const snap = await db.collection("events")
      .where("startDate", "==", tomorrow)
      .limit(500)
      .get();
    let sent = 0;
    for (const doc of snap.docs) {
      const event = doc.data();
      if (!isEventVisible(event)) continue;
      const creatorId = eventCreator(event);
      const title = event.title || "Your event";
      const when = eventWhen(event);
      const attendees = asList(event.attendees).filter((uid) => uid !== creatorId);
      const attendeeSet = new Set(attendees);
      const interested = asList(event.interested)
        .filter((uid) => uid !== creatorId && !attendeeSet.has(uid));

      sent += await notifyUsers(attendees, () => ({
        type: "event_reminder",
        title: `Tomorrow: ${title}`,
        body: `${when ? `${when} · ` : ""}${event.location || event.venueName || "Tap for details"}. ` +
          "Don't forget to check in to earn DSP!",
        dedupKey: `event_reminder_${doc.id}_${tomorrow}`,
        additionalData: { eventId: doc.id },
        inApp: { type: "eventReminder", payload: { eventId: doc.id } },
      }));
      sent += await notifyUsers(interested, () => ({
        type: "event_reminder",
        title: `${title} is tomorrow`,
        body: `You showed interest${when ? ` · ${when}` : ""}. RSVP now to save your spot.`,
        dedupKey: `event_interest_reminder_${doc.id}_${tomorrow}`,
        additionalData: { eventId: doc.id },
        inApp: { type: "eventReminder", payload: { eventId: doc.id } },
      }));
    }
    console.log(`[eventReminderCron] ${snap.size} events, ${sent} reminders sent`);
    return null;
  });

// ─── 7. Governance (candidacy announcements, election outcomes) ─────────────

const ROLE_NAMES = {
  president: "President",
  treasurer: "Treasurer",
  secretary: "Secretary",
  council_member: "Council Member",
};

exports.onGovernanceNotify = functions.firestore
  .document("governance/{unitId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    const unitId = context.params.unitId;
    if (unitId === "global_community" || !validId(after.communityId)) return null;
    const community = await getCommunity(after.communityId);
    if (!community) return null;
    const communityName = community.name || community.displayName || "your community";
    const members = communityMemberIds(community);
    const memberSet = new Set(members);

    // New candidates → community members. Candidacy is validated server-side
    // (nominateForGovernanceRole), but governance docs are client-writable, so
    // re-check eligibility + membership before broadcasting.
    const beforeCandidates = before.roleCandidates || {};
    const afterCandidates = after.roleCandidates || {};
    for (const role of Object.keys(ROLE_NAMES)) {
      const newOnes = added(beforeCandidates[role], afterCandidates[role]).slice(0, 3);
      for (const candidateId of newOnes) {
        const [profile, trustSnap] = await Promise.all([
          getProfile(candidateId),
          db.collection("trust_data").doc(candidateId).get(),
        ]);
        const memberships = profile && Array.isArray(profile.communityMemberships) ?
          profile.communityMemberships : [];
        const isMember = memberSet.has(candidateId) || memberships.includes(after.communityId);
        if (!profile || !isMember || !trustSnap.exists ||
            trustSnap.data().isCouncilEligible !== true) {
          continue;
        }
        const name = displayName(profile, "A member");
        await notifyUsers(members.filter((uid) => uid !== candidateId), () => ({
          type: "election_started",
          title: `🗳️ New candidate in ${communityName}`,
          body: `${name} is running for ${ROLE_NAMES[role]}. Cast your vote: Yay, Nay or Abstain.`,
          targetUserId: candidateId,
          route: `/communities/${after.communityId}`,
          dedupKey: `governance_candidate_${unitId}_${role}_${candidateId}`,
          additionalData: { communityId: after.communityId, unitId, candidateId, role },
          androidCollapseKey: `governance_${unitId}`,
          apnsThreadId: `governance_${unitId}`,
          inApp: {
            type: "electionStarted",
            actionRequired: true,
            payload: { communityId: after.communityId, unitId, candidateId, role },
          },
        }), { max: MAX_BROADCAST });
      }
    }

    // Council changes → the affected member.
    const roles = after.councilRoles || {};
    for (const uid of added(before.councilMembers, after.councilMembers)) {
      const roleName = ROLE_NAMES[roles[uid]] || "Council Member";
      await notifyUser(uid, {
        type: "election_results",
        title: `🎉 You've been elected ${roleName}`,
        body: `The ${communityName} community voted you in as ${roleName}. Congratulations, leader!`,
        route: `/communities/${after.communityId}`,
        dedupKey: `governance_elected_${unitId}_${uid}_${roles[uid] || ""}`,
        additionalData: { communityId: after.communityId, unitId },
        inApp: { type: "electionResults", payload: { communityId: after.communityId, unitId } },
      });
    }
    for (const uid of added(after.councilMembers, before.councilMembers)) {
      await notifyUser(uid, {
        type: "election_results",
        title: "Council seat update",
        body: `Your council seat in ${communityName} is now open. You can run again once you're eligible.`,
        route: `/communities/${after.communityId}`,
        dedupKey: `governance_removed_${unitId}_${uid}_${toMillis(after.updatedAt) || ""}`,
        additionalData: { communityId: after.communityId, unitId },
        inApp: { type: "electionResults", payload: { communityId: after.communityId, unitId } },
      });
    }
    return null;
  });

// ─── 8. DDI community loans ─────────────────────────────────────────────────

exports.onDdiApplicationNotify = functions.firestore
  .document("ddi_loan_applications/{applicationId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;
    const after = change.after.data();
    const before = change.before.exists ? change.before.data() : null;
    const applicationId = context.params.applicationId;
    const chatRoute = after.discussionChatId ? `/chats/${after.discussionChatId}` : "/notifications";
    const business = after.businessName || "A local business";
    const amount = Number(after.requestedAmount || 0).toLocaleString("en-US");

    if (!before && after.voting && after.voting.status === "open") {
      const community = await getCommunity(after.communityId);
      const recipients = communityMemberIds(community).filter((uid) => uid !== after.applicantId);
      const closes = formatDate(after.voting.closesAt);
      await notifyUsers(recipients, () => ({
        type: "ddi_vote_open",
        title: "🗳️ Vote on a community loan",
        body: `${business} is requesting ${amount} $DIASPORA in ${after.communityName || "your community"}.` +
          `${closes ? ` Voting closes ${closes}.` : ""}`,
        targetUserId: after.applicantId,
        route: chatRoute,
        dedupKey: `ddi_vote_open_${applicationId}`,
        additionalData: { applicationId, chatId: after.discussionChatId || "" },
        androidCollapseKey: "ddi_vote_open",
        apnsThreadId: "ddi_vote_open",
        inApp: { type: "system", actionRequired: true, payload: { applicationId } },
      }), { max: MAX_BROADCAST });
      return null;
    }

    const wasOpen = before && before.voting && before.voting.status === "open";
    const nowClosed = after.voting && after.voting.status === "closed";
    if (wasOpen && nowClosed) {
      const approved = String(after.status || "").includes("approved") ||
        after.voting.outcome === "approved";
      await notifyUser(after.applicantId, {
        type: "ddi_vote_result",
        title: approved ? "🎉 Your loan was approved by the community" : "Community vote closed",
        body: approved ?
          `${after.communityName || "Your community"} approved ${business}'s ${amount} $DIASPORA request.` :
          `${business}'s loan request didn't pass this time. Review the discussion for feedback.`,
        route: chatRoute,
        dedupKey: `ddi_vote_result_${applicationId}`,
        additionalData: { applicationId, chatId: after.discussionChatId || "" },
        inApp: { type: "system", payload: { applicationId } },
      });
    }
    return null;
  });

// ─── 9. Emergency fund claim status ─────────────────────────────────────────

exports.onEmergencyClaimNotify = functions.firestore
  .document("emergency_fund_claims/{claimId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists || !change.before.exists) return null;
    const after = change.after.data();
    const before = change.before.data();
    if (before.status === after.status || !validId(after.userId)) return null;
    const claimId = context.params.claimId;
    const beneficiary = after.beneficiaryName || "your beneficiary";
    const copy = {
      approved: ["Emergency claim approved 💚",
        `Your claim for ${beneficiary} was approved. Funds are on the way.`],
      paid: ["Emergency support sent 💚",
        `${Number(after.payoutAmountDiaspora || 0).toLocaleString("en-US")} $DIASPORA was sent for ${beneficiary}. The community has your back.`],
      rejected: ["Emergency claim update",
        "Your emergency claim could not be approved. Tap for details."],
    }[after.status];
    if (!copy) return null;
    await notifyUser(after.userId, {
      type: "emergency_claim_update",
      title: copy[0],
      body: copy[1],
      route: "/dsp/emergency-fund",
      dedupKey: `emergency_claim_${claimId}_${after.status}`,
      additionalData: { claimId, status: after.status },
      inApp: { type: "system", payload: { claimId } },
    });
    return null;
  });

// ─── 10. Daily streak protection ────────────────────────────────────────────

/**
 * Nudges users whose daily check-in streak is about to break. A streak
 * survives up to 48h between check-ins; we remind ~40h after the last one.
 * Hourly, with a 1h window + dedup key, so each lapse is nudged once.
 */
exports.streakReminderCron = functions
  .runWith({ timeoutSeconds: 300, memory: "256MB" })
  .pubsub.schedule("every 60 minutes")
  .onRun(async () => {
    const now = Date.now();
    const from = new Date(now - 41 * 60 * 60 * 1000).toISOString();
    const to = new Date(now - 40 * 60 * 60 * 1000).toISOString();
    const snap = await db.collection("user_points")
      .where("lastCheckInDate", ">=", from)
      .where("lastCheckInDate", "<", to)
      .limit(2000)
      .get();
    const candidates = snap.docs.filter((doc) => Number(doc.data().currentStreak || 0) >= 2);
    let sent = 0;
    for (let i = 0; i < candidates.length; i += 25) {
      const results = await Promise.all(candidates.slice(i, i + 25).map((doc) => {
        const streak = Number(doc.data().currentStreak || 0);
        const next = streak < 10 ? 10 : (streak < 100 ? 100 : null);
        const bonus = next === 10 ? "1,000" : (next === 100 ? "10,000" : null);
        return notifyUser(doc.id, {
          type: "streak_reminder",
          title: `🔥 Keep your ${streak}-day streak alive`,
          body: bonus ?
            `Open Diaspora Nearby today — ${next - streak} more day${next - streak === 1 ? "" : "s"} to a ${bonus} DSP bonus.` :
            "Open Diaspora Nearby today to keep your streak going.",
          route: "/dsp/points",
          dedupKey: `streak_${doc.id}_${doc.data().lastCheckInDate}`,
          androidCollapseKey: "streak_reminder",
          apnsThreadId: "streak_reminder",
          inApp: false,
        }).catch(() => false);
      }));
      sent += results.filter(Boolean).length;
    }
    console.log(`[streakReminderCron] ${candidates.length} at-risk streaks, ${sent} nudges sent`);
    return null;
  });

// ─── Inline helpers used by existing callables / triggers ──────────────────

/** Someone vouched (rated) the user for the first time. */
async function notifyTrustVouch(fromUserId, toUserId, fromUserName) {
  const name = fromUserName || displayName(await getProfile(fromUserId), "A peer");
  return notifyUser(toUserId, {
    type: "trust_peer_vouched",
    title: "🤝 New trust vouch",
    body: `${name} vouched for you. You both earned 1,000 DSP!`,
    targetUserId: fromUserId,
    dedupKey: `trust_vouch_${fromUserId}_${toUserId}`,
    additionalData: { fromUserId },
    inApp: { type: "trustPeerVouched", payload: { fromUserId } },
  });
}

/** A peer verified the user's profile fields for the first time. */
async function notifyFieldVerification(fromUserId, toUserId) {
  const name = displayName(await getProfile(fromUserId), "A peer");
  return notifyUser(toUserId, {
    type: "trust_peer_verified",
    title: "✅ Profile verified by a peer",
    body: `${name} verified your profile details. +1,000 DSP and a stronger trust score!`,
    targetUserId: fromUserId,
    dedupKey: `trust_verify_${fromUserId}_${toUserId}`,
    additionalData: { fromUserId },
    inApp: { type: "trustPeerVerified", payload: { fromUserId } },
  });
}

/** In-person QR handshake completed — tell the QR owner (the scanner knows). */
async function notifyQrConnection(scannerUid, peerUid) {
  const name = displayName(await getProfile(scannerUid), "A member");
  return notifyUser(peerUid, {
    type: "trust_qr_connected",
    title: "🤝 New in-person connection",
    body: `You and ${name} connected by QR. +1,000 DSP each!`,
    targetUserId: scannerUid,
    dedupKey: `qr_connected_${[scannerUid, peerUid].sort().join("_")}`,
    additionalData: { fromUserId: scannerUid },
    inApp: { type: "system", payload: { fromUserId: scannerUid } },
    route: `/profile/${scannerUid}`,
  });
}

/** A chat message was marked as a verified solution. */
async function notifySolutionVerified(reporterId, senderId, chatId, messageId) {
  const name = firstName(await getProfile(reporterId), "Someone");
  return notifyUser(senderId, {
    type: "solution_verified",
    title: "💡 Your answer helped someone",
    body: `${name} marked your message as a verified solution. +1,000 DSP!`,
    targetUserId: reporterId,
    route: `/chats/${chatId}`,
    dedupKey: `solution_verified_${reporterId}_${chatId}_${messageId}`.slice(0, 500),
    additionalData: { chatId, messageId },
    inApp: { type: "system", payload: { chatId } },
  });
}

/** An attendee checked in at the host's event (host earns DSP). */
async function notifyEventCheckIn(hostUid, attendeeUid, eventId) {
  const [attendee, eventSnap] = await Promise.all([
    getProfile(attendeeUid),
    db.collection("events").doc(eventId).get(),
  ]);
  const title = eventSnap.exists ? eventSnap.data().title || "your event" : "your event";
  return notifyUser(hostUid, {
    type: "event_checkin",
    title: `📍 ${displayName(attendee, "An attendee")} checked in`,
    body: `New verified check-in at ${title}. +1,000 DSP host reward!`,
    targetUserId: attendeeUid,
    route: `/events/${eventId}`,
    dedupKey: `event_checkin_${eventId}_${attendeeUid}`,
    additionalData: { eventId },
    androidCollapseKey: `event_checkin_${eventId}`,
    androidTag: `event_checkin_${eventId}`,
    apnsThreadId: `event_checkin_${eventId}`,
    inApp: { type: "eventNewAttendee", payload: { eventId } },
  });
}

/** A new member joined using the user's referral code. */
async function notifyReferralJoined(referrerId, refereeId) {
  const name = displayName(await getProfile(refereeId), "Someone new");
  return notifyUser(referrerId, {
    type: "referral_joined",
    title: `🎉 ${name} joined with your invite`,
    body: "+1,000 DSP earned! Say hi and help them settle in.",
    targetUserId: refereeId,
    route: `/profile/${refereeId}`,
    dedupKey: `referral_joined_${referrerId}_${refereeId}`,
    additionalData: { fromUserId: refereeId },
    inApp: { type: "system", payload: { fromUserId: refereeId } },
  });
}

/** A group admin invited the user to a group chat. */
async function notifyGroupInvitation(inviterUid, targetUid, chatId, chatName) {
  const name = displayName(await getProfile(inviterUid), "Someone");
  const group = String(chatName || "a group").slice(0, 150);
  return notifyUser(targetUid, {
    type: "group_invitation",
    title: name,
    body: `invited you to join "${group}"`,
    targetUserId: inviterUid,
    dedupKey: `group_invite_${chatId}_${targetUid}_${Math.floor(Date.now() / DAY_MS)}`,
    additionalData: { chatId, senderId: inviterUid, senderName: name,
      content: `invited you to join "${group}"` },
    inApp: { type: "groupInvitation", actionRequired: true, payload: { chatId } },
  });
}

exports.notifyTrustVouch = notifyTrustVouch;
exports.notifyFieldVerification = notifyFieldVerification;
exports.notifyQrConnection = notifyQrConnection;
exports.notifySolutionVerified = notifySolutionVerified;
exports.notifyEventCheckIn = notifyEventCheckIn;
exports.notifyReferralJoined = notifyReferralJoined;
exports.notifyGroupInvitation = notifyGroupInvitation;
exports._test = { citySlug, eventWhen, formatDateRange, added, displayName, capitalize };
