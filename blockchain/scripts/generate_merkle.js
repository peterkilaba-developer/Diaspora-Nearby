const { MerkleTree } = require("merkletreejs");
const keccak256 = require("keccak256");
const fs = require("fs");

/**
 * Generates a Merkle Tree from a snapshot of users and their DSP balances.
 * This root will be uploaded to the blockchain for the "Claim" mechanism.
 */
function generateMerkle(snapshotPath) {
    const snapshotData = JSON.parse(fs.readFileSync(snapshotPath, "utf8"));

    // Format: hash(address, amount)
    const leaves = snapshotData.map(user => {
        return keccak256(
            Buffer.concat([
                Buffer.from(user.address.replace("0x", ""), "hex"),
                Buffer.from(BigInt(user.amount).toString(16).padStart(64, "0"), "hex")
            ])
        );
    });

    const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
    const root = tree.getHexRoot();

    console.log("Merkle Root:", root);

    // Generate proof for each user to be saved in the database
    const proofs = snapshotData.map((user, index) => {
        return {
            address: user.address,
            amount: user.amount,
            proof: tree.getHexProof(leaves[index])
        };
    });

    fs.writeFileSync("blockchain/scripts/merkle_proofs.json", JSON.stringify({ root, proofs }, null, 2));
    console.log("Proofs saved to scripts/merkle_proofs.json");
}

// Example MOCK data for testing
const mockSnapshot = [
    { address: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8", amount: "100000000000000000000000" }, // 100k
    { address: "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC", amount: "200000000000000000000000" }  // 200k
];

fs.writeFileSync("blockchain/scripts/mock_snapshot.json", JSON.stringify(mockSnapshot));
generateMerkle("blockchain/scripts/mock_snapshot.json");
