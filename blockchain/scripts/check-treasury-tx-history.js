import hre from "hardhat";

const FOUNDERS = "0xc27f74031f63c24c5E29492e23ecE019E698B46c";
const LIQUIDITY = "0xF0f15Cf38Ef463E0ff46DC0540489F466E222edB";
const TOKEN = "0x55d7e7d006938A15082752225ED44Fd130B87735";

const TOKEN_ABI = [
  "event Transfer(address indexed from, address indexed to, uint256 value)",
];

async function queryInChunks(token, filter, fromBlock, toBlock, chunkSize = 100000) {
  const events = [];
  for (let current = fromBlock; current <= toBlock; current += chunkSize) {
    const end = Math.min(current + chunkSize - 1, toBlock);
    try {
      const subEvents = await token.queryFilter(filter, current, end);
      events.push(...subEvents);
    } catch (e) {
      // If chunk too big, split in half
      const mid = Math.floor((current + end) / 2);
      const e1 = await token.queryFilter(filter, current, mid);
      const e2 = await token.queryFilter(filter, mid + 1, end);
      events.push(...e1, ...e2);
    }
  }
  return events;
}

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const provider = ethers.provider;

  const fAddr = ethers.getAddress(FOUNDERS.toLowerCase());
  const lAddr = ethers.getAddress(LIQUIDITY.toLowerCase());

  const token = new ethers.Contract(TOKEN, TOKEN_ABI, provider);

  const latestBlock = await provider.getBlockNumber();
  const startBlock = 44000000;

  console.log("=".repeat(60));
  console.log(`  📜 Auditing All Transfers to Founders & Liquidity (${startBlock} -> ${latestBlock})`);
  console.log("=".repeat(60));

  const fFilter = token.filters.Transfer(null, fAddr);
  const lFilter = token.filters.Transfer(null, lAddr);

  const fEvents = await queryInChunks(token, fFilter, startBlock, latestBlock, 50000);
  console.log(`Founders (${fAddr}) received ${fEvents.length} transfer(s):`);
  for (const ev of fEvents) {
    console.log(`  - Block ${ev.blockNumber}: +${ethers.formatEther(ev.args.value)} $DIASPORA (From: ${ev.args.from}) [tx ${ev.transactionHash}]`);
  }
  console.log();

  const lEvents = await queryInChunks(token, lFilter, startBlock, latestBlock, 50000);
  console.log(`Liquidity (${lAddr}) received ${lEvents.length} transfer(s):`);
  for (const ev of lEvents) {
    console.log(`  - Block ${ev.blockNumber}: +${ethers.formatEther(ev.args.value)} $DIASPORA (From: ${ev.args.from}) [tx ${ev.transactionHash}]`);
  }

  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
