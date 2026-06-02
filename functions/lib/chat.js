/**
 * Chat Notifications module.
 */
const { functions, admin, db, sendPushToUser } = require("./shared");


/**
 * ==================================================================
 * 3. CHAT NOTIFICATIONS (Migrated to Firestore)
 * ==================================================================
 */

exports.onDirectMessageCreated = functions.firestore
  .document('chats/{chatId}/messages/{messageId}')
  .onCreate(async (snapshot, context) => {
    const message = snapshot.data();
    const chatId = context.params.chatId;
    const senderId = message.senderId;

    if (!senderId) {
      console.log(`[Chat] Message ${context.params.messageId} has no senderId, skipping`);
      return null;
    }

    // [FIX] Fetch the chat document with retry logic.
    // When a new DM is created, the chat document and first message may be
    // written in separate batch commits. The Cloud Function trigger can fire
    // before the chat document batch is fully propagated.
    let chatDoc = await db.collection('chats').doc(chatId).get();

    if (!chatDoc.exists) {
      console.log(`[Chat] Chat document not found for ${chatId}, retrying in 1.5s...`);
      await new Promise(r => setTimeout(r, 1500));
      chatDoc = await db.collection('chats').doc(chatId).get();
    }

    if (!chatDoc.exists) {
      console.log(`[Chat] Chat document still not found for ${chatId} after retry, skipping`);
      return null;
    }

    let chatData = chatDoc.data();
    let participants = chatData.participants || [];

    // [FIX] Retry if participants are missing (race condition with batch writes)
    if (!Array.isArray(participants) || participants.length === 0) {
      console.log(`[Chat] No participants for ${chatId}, retrying in 1s...`);
      await new Promise(r => setTimeout(r, 1000));
      const retryDoc = await db.collection('chats').doc(chatId).get();
      if (retryDoc.exists) {
        chatData = retryDoc.data();
        participants = chatData.participants || [];
      }
    }

    if (!Array.isArray(participants) || participants.length === 0) {
      console.log(`[Chat] No participants found for chat ${chatId} after retry`);
      return null;
    }

    // STRICT SENDER FILTERING & DEDUPLICATION
    let recipients = participants.filter(uid => String(uid) !== String(senderId));
    recipients = [...new Set(recipients)]; // Deduplicate

    console.log(`[Chat] MsgID: ${context.params.messageId} | Sender: ${senderId} | Recipients: ${recipients.join(', ')}`);

    // Community detection using all chatId patterns (matches Flutter client)
    const isCommunity = chatData.type === 'community' ||
      chatId.startsWith('chat_') ||
      chatId.startsWith('home_') ||
      chatId.startsWith('host_') ||
      chatId.startsWith('past_') ||
      chatId === 'global_community';
    const isChamber = chatData.metadata && chatData.metadata.isChamber === true;
    const isDdiDiscussion = chatData.metadata &&
      chatData.metadata.isDdiDiscussion === true;

    const promises = recipients.map(async (recipientId) => {
      const mentions = Array.isArray(message.mentions) ? message.mentions : [];
      const isMentioned = mentions.includes(recipientId);

      // Check Mute Status from Firestore userChats subcollection
      let isManuallyMuted = false;
      try {
        const muteDoc = await db
          .collection('users')
          .doc(recipientId)
          .collection('userChats')
          .doc(chatId)
          .get();
        if (muteDoc.exists) {
          const muteData = muteDoc.data();
          isManuallyMuted = muteData.muted === true || muteData.isMuted === true;
        }
      } catch (e) {
        console.log(`[Chat] Error checking mute for ${recipientId}: ${e.message}`);
      }

      // Routing Logic
      let shouldNotify = false;

      if (isMentioned) {
        // [OVERRIDE] Mentions always notify
        shouldNotify = true;
      } else if (isManuallyMuted) {
        // [RESPECT] Manual mute takes precedence if not mentioned
        shouldNotify = false;
      } else if (isCommunity || isChamber || isDdiDiscussion) {
        // [DEFAULT] Community-governed traffic is muted by default
        shouldNotify = false;
      } else {
        // [DEFAULT] Direct messages and Private Groups notify by default
        shouldNotify = true;
      }

      if (!shouldNotify) {
        const reason = isManuallyMuted ?
          "manually muted" : "community-managed default mute";
        console.log(`[Chat] Skipping notification for ${recipientId} in ${chatId} (${reason})`);
        return null;
      }

      let title = message.senderName || "New Message";
      if (isMentioned) {
        title = `📢 Mentioned by ${message.senderName || "someone"}`;
      }
      let body = message.content;

      if (message.type === 'image') body = "📷 sent a photo";
      if (message.type === 'video') body = "🎥 sent a video";
      if (message.type === 'audio') body = "🎤 sent a voice message";
      if (message.type === 'audio_file') body = "🎵 sent an audio file";
      if (message.type === 'location') body = "📍 sent a location";
      if (message.type === 'document') body = "📄 sent a document";

      // Ensure we don't crash if body is empty
      if (!body) body = "Sent a message";

      await sendPushToUser(recipientId, {
        title: title,
        body: body,
        type: "chat_message",
        targetUserId: senderId, // Open chat with sender
        city: "", // Not relevant for chat
        additionalData: { chatId: chatId }
      });
    });

    await Promise.all(promises);
    return null;
  });
