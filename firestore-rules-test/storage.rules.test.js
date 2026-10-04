const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const { ref, uploadString, getBytes } = require("firebase/storage");

const PROJECT_ID = "diaspora-nearby-rules-test";
let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "..", "firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
    storage: {
      rules: fs.readFileSync(path.resolve(__dirname, "..", "storage.rules"), "utf8"),
      host: "127.0.0.1",
      port: 9199,
    },
  });
});

afterAll(async () => testEnv?.cleanup());

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().doc("chats/secure-chat").set({
      participants: ["member"],
      createdBy: "member",
    });
    await context.firestore().doc("events/event-1").set({
      creatorId: "event-owner",
    });
  });
});

describe("chat media isolation", () => {
  test("a participant can upload and read chat media", async () => {
    const storage = testEnv.authenticatedContext("member").storage();
    const imageRef = ref(storage, "chat_images/secure-chat/photo.jpg");
    await assertSucceeds(uploadString(imageRef, "image", "raw", {
      contentType: "image/jpeg",
    }));
    await assertSucceeds(getBytes(imageRef));
  });

  test("an authenticated outsider cannot read or upload chat media", async () => {
    const memberStorage = testEnv.authenticatedContext("member").storage();
    const memberRef = ref(memberStorage, "chat_images/secure-chat/photo.jpg");
    await uploadString(memberRef, "image", "raw", { contentType: "image/jpeg" });

    const outsiderStorage = testEnv.authenticatedContext("outsider").storage();
    const outsiderRef = ref(outsiderStorage, "chat_images/secure-chat/photo.jpg");
    await assertFails(getBytes(outsiderRef));
    await assertFails(uploadString(outsiderRef, "replacement", "raw", {
      contentType: "image/jpeg",
    }));
  });
});

describe("event image ownership", () => {
  test("only the event owner can upload the event image", async () => {
    const ownerStorage = testEnv.authenticatedContext("event-owner").storage();
    await assertSucceeds(uploadString(
      ref(ownerStorage, "event_images/event-1"),
      "image",
      "raw",
      { contentType: "image/jpeg" },
    ));

    const outsiderStorage = testEnv.authenticatedContext("outsider").storage();
    await assertFails(uploadString(
      ref(outsiderStorage, "event_images/event-1"),
      "image",
      "raw",
      { contentType: "image/jpeg" },
    ));
  });
});
