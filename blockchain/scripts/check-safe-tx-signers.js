import hre from "hardhat";

const ADMIN_SAFE = "0xE06F8690e96a8BAAbCBe48664Ff1238F69082244";

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const provider = ethers.provider;

  console.log("=".repeat(60));
  console.log("Fetching pending transactions from Safe API...");
  console.log("=".repeat(60));

  const url = `https://safe-transaction-base.safe.global/api/v1/safes/${ADMIN_SAFE}/multisig-transactions/?ordering=-nonce`;
  const res = await fetch(url);
  const data = await res.json();

  if (data.results) {
    for (const tx of data.results.slice(0, 5)) {
      console.log(`Nonce: ${tx.nonce} | Destination: ${tx.to} | Value: ${tx.value}`);
      console.log(`  Executed: ${tx.isExecuted} | Confirmations Required: ${tx.confirmationsRequired}`);
      console.log(`  Confirmations (${tx.confirmations ? tx.confirmations.length : 0}):`);
      if (tx.confirmations) {
        tx.confirmations.forEach((c) => console.log(`    - ${c.owner}`));
      }
      console.log();
    }
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
