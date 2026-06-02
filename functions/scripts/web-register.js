const { initializeApp } = require("firebase/app");
const { getFirestore, doc, setDoc } = require("firebase/firestore");
const { getAuth, createUserWithEmailAndPassword } = require("firebase/auth");

const firebaseConfig = {
  apiKey: 'AIzaSyACyPyqHcgciP31rKqPTuS5jXAtyqpNkdU',
  projectId: 'diaspora-nearby-a3dac',
  databaseURL: 'https://diaspora-nearby-a3dac-default-rtdb.firebaseio.com',
};

const app = initializeApp(firebaseConfig);
const db = getFirestore(app);
const auth = getAuth(app);

async function main() {
    console.log("Authenticating...");
    try {
        await createUserWithEmailAndPassword(auth, "dummy_admin_3@diaspora.local", "password123");
        console.log("Logged in dummy user. Writing governance docs...");

        await setDoc(doc(db, "governance", "founders"), {
            id: "founders",
            label: "Founders & Core Team",
            type: "system_treasury",
            walletAddress: "0x721b98484afff3bF4314933a7cB0e324499FbC24",
            walletType: "smart",
            salt: "treasury:founders",
        }, { merge: true });
        console.log("Founders ✅");
        
        await setDoc(doc(db, "governance", "liquidity"), {
            id: "liquidity",
            label: "Liquidity Treasury",
            type: "system_treasury",
            walletAddress: "0x02Bd59A63d6e8Fc31Fda8b117ceb4A4f24265CaD",
            walletType: "smart",
            salt: "treasury:investors",
        }, { merge: true });
        console.log("Liquidity ✅");

        console.log("Done!");
        process.exit(0);
    } catch(err) {
        console.error("Failed:", err);
        process.exit(1);
    }
}
main();
