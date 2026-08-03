import hre from "hardhat";

const TOKEN = "0x55d7e7d006938A15082752225ED44Fd130B87735";
const TGE = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";
const SAFE = "0xE06F8690e96a8BAAbCBe48664Ff1238F69082244";
const DEPLOYER = "0xeEf494A14E6e66ec7c3E14E8674dCe2d99144de6";
const FOUNDER_KEY = "0x881e6CD5cC081Bf85587A8DC585de1E664BB90A2";

const TOKEN_ABI = [
  "function hasRole(bytes32 role, address account) view returns (bool)",
  "function MINTER_ROLE() view returns (bytes32)",
  "function DEFAULT_ADMIN_ROLE() view returns (bytes32)",
  "function balanceOf(address account) view returns (uint256)",
];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const provider = ethers.provider;

  const token = new ethers.Contract(TOKEN, TOKEN_ABI, provider);
  const minterRole = await token.MINTER_ROLE();
  const adminRole = await token.DEFAULT_ADMIN_ROLE();

  console.log("=".repeat(60));
  console.log("Diaspora Token:", TOKEN);
  console.log("=".repeat(60));

  const accounts = [
    { name: "Deployer EOA", addr: ethers.getAddress(DEPLOYER.toLowerCase()) },
    { name: "Admin Safe", addr: ethers.getAddress(SAFE.toLowerCase()) },
    { name: "Founder Key", addr: ethers.getAddress(FOUNDER_KEY.toLowerCase()) },
    { name: "TGE Controller Proxy", addr: ethers.getAddress(TGE.toLowerCase()) },
  ];

  for (const acc of accounts) {
    const isMinter = await token.hasRole(minterRole, acc.addr);
    const isAdmin = await token.hasRole(adminRole, acc.addr);
    const bal = await token.balanceOf(acc.addr);
    console.log(`Account: ${acc.name} (${acc.addr})`);
    console.log(`  Balance:            ${ethers.formatEther(bal)} $DIASPORA`);
    console.log(`  MINTER_ROLE:        ${isMinter}`);
    console.log(`  DEFAULT_ADMIN_ROLE: ${isAdmin}`);
    console.log();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
