import hre from "hardhat";

const TGE_CONTROLLER = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";

const TGE_ABI = [
  "event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender)",
  "function TGE_ORACLE_ROLE() view returns (bytes32)",
];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const provider = ethers.provider;

  const tge = new ethers.Contract(TGE_CONTROLLER, TGE_ABI, provider);
  const oracleRole = await tge.TGE_ORACLE_ROLE();

  const filter = tge.filters.RoleGranted(oracleRole);
  const latestBlock = await provider.getBlockNumber();
  
  // Search in 1000 block chunks around deploy block (approx 44,914,000) and recent
  const chunks = [
    [44914000, 44915000],
    [latestBlock - 1000, latestBlock],
  ];

  for (const [start, end] of chunks) {
    const events = await tge.queryFilter(filter, start, end);
    console.log(`Range ${start}-${end}: Found ${events.length} RoleGranted event(s):`);
    for (const ev of events) {
      console.log(`  - Account: ${ev.args.account} (Granted by ${ev.args.sender})`);
    }
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
