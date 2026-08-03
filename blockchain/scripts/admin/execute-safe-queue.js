import hre from "hardhat";

const ADMIN_SAFE = "0xE06F8690e96a8BAAbCBe48664Ff1238F69082244";

const SAFE_ABI = [
  "function execTransaction(address to, uint256 value, bytes calldata data, uint8 operation, uint256 safeTxGas, uint256 baseGas, uint256 gasPrice, address gasToken, address refundReceiver, bytes calldata signatures) external payable returns (bool success)",
  "function nonce() view returns (uint256)",
];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const provider = ethers.provider;
  const [signer] = await ethers.getSigners();

  console.log("=".repeat(60));
  console.log("  🚀 Safe Queue Executor via Hardhat / Base RPC");
  console.log("=".repeat(60));
  console.log("Signer Account:", signer.address);

  // Fetch pending transactions from Safe API
  const url = `https://safe-transaction-base.safe.global/api/v1/safes/${ADMIN_SAFE}/multisig-transactions/?ordering=nonce`;
  const res = await fetch(url);
  const data = await res.json();

  if (!data.results || data.results.length === 0) {
    console.log("No pending transactions found.");
    return;
  }

  const safe = new ethers.Contract(ADMIN_SAFE, SAFE_ABI, signer);
  const currentNonce = await safe.nonce();
  console.log(`Current Safe On-Chain Nonce: ${currentNonce}`);

  for (const tx of data.results) {
    if (tx.isExecuted) continue;
    if (tx.confirmations.length < tx.confirmationsRequired) {
      console.log(`Nonce ${tx.nonce}: waiting for more confirmations (${tx.confirmations.length}/${tx.confirmationsRequired})`);
      continue;
    }

    console.log(`Executing Nonce ${tx.nonce} on-chain...`);
    console.log(`  To: ${tx.to}`);
    console.log(`  Confirmations: ${tx.confirmations.length}`);

    // Sort confirmations by owner address (Gnosis Safe requires signatures sorted by owner address)
    const sortedConfs = [...tx.confirmations].sort((a, b) => 
      a.owner.toLowerCase().localeCompare(b.owner.toLowerCase())
    );

    // Concatenate signature bytes
    let sigBytes = "0x";
    for (const conf of sortedConfs) {
      sigBytes += conf.signature.slice(2);
    }

    try {
      const execTx = await safe.execTransaction(
        tx.to,
        tx.value || 0,
        tx.data || "0x",
        tx.operation || 0,
        tx.safeTxGas || 0,
        tx.baseGas || 0,
        tx.gasPrice || 0,
        tx.gasToken || "0x0000000000000000000000000000000000000000",
        tx.refundReceiver || "0x0000000000000000000000000000000000000000",
        sigBytes,
        { gasLimit: 500000 }
      );
      console.log(`  Transaction submitted! Tx Hash: ${execTx.hash}`);
      await execTx.wait();
      console.log(`  ✅ Nonce ${tx.nonce} executed successfully!`);
    } catch (e) {
      console.error(`  ❌ Failed to execute Nonce ${tx.nonce}:`, e.message);
    }
  }

  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
