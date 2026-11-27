import fs from "node:fs";
import https from "node:https";
import path from "node:path";
import { execSync } from "node:child_process";
import { createRequire } from "node:module";
import "dotenv/config";

const require = createRequire(import.meta.url);
const { ethers } = require("C:/Projects/DiasporaNearby/functions/node_modules/ethers");

const PROJECT_ID = "diaspora-nearby-a3dac";
const TOKEN_PROXY = "0x55d7e7d006938A15082752225ED44Fd130B87735";
const TGE_PROXY = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";
const ADMIN_SAFE = "0xE06F8690e96a8BAAbCBe48664Ff1238F69082244";
const BURN_ADDRESS = "0x000000000000000000000000000000000000dEaD";
const DEPLOYER_EOA = "0xeEf494A14E6e66ec7c3E14E8674dCe2d99144de6";
const CREATOR_METAMASK = "0xeef49F2a10f0EF143Cd8c710e013285F137F4dE6";
const FOUNDERS_SAFE = "0xc27f74031f63c24c5E29492e23ecE019E698B46c";
const LIQUIDITY_SAFE = "0xF0f15Cf38Ef463E0fF46DC0540489F466E222edB";

async function getAccessToken() {
  const cfgPath = path.join(process.env.USERPROFILE, ".config", "configstore", "firebase-tools.json");
  const cfg = JSON.parse(fs.readFileSync(cfgPath, "utf8"));
  const rt = cfg.tokens && cfg.tokens.refresh_token;
  const scopes = cfg.tokens && cfg.tokens.scopes;
  const auth = require("C:/Users/Nemo CLAW/AppData/Roaming/npm/node_modules/firebase-tools/lib/auth");
  const tokenObj = await auth.getAccessToken(rt, scopes);
  return typeof tokenObj === "string" ? tokenObj : tokenObj.access_token;
}

function httpsRequest(options, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = "";
      res.on("data", (chunk) => (data += chunk));
      res.on("end", () => {
        try {
          const parsed = data ? JSON.parse(data) : {};
          resolve({ status: res.statusCode, data: parsed, raw: data });
        } catch (e) {
          resolve({ status: res.statusCode, data: null, raw: data });
        }
      });
    });
    req.on("error", reject);
    if (body) req.write(typeof body === "string" ? body : JSON.stringify(body));
    req.end();
  });
}

function parseFirestoreValue(val) {
  if (!val) return null;
  if (val.stringValue !== undefined) return val.stringValue;
  if (val.integerValue !== undefined) return parseInt(val.integerValue, 10);
  if (val.doubleValue !== undefined) return parseFloat(val.doubleValue);
  if (val.booleanValue !== undefined) return val.booleanValue;
  if (val.timestampValue !== undefined) return val.timestampValue;
  if (val.nullValue !== undefined) return null;
  if (val.arrayValue) return (val.arrayValue.values || []).map(parseFirestoreValue);
  if (val.mapValue) {
    const obj = {};
    for (const [k, v] of Object.entries(val.mapValue.fields || {})) obj[k] = parseFirestoreValue(v);
    return obj;
  }
  return val;
}

function parseFirestoreDoc(doc) {
  if (!doc || !doc.fields) return null;
  const result = { id: doc.name.split("/").pop() };
  for (const [k, v] of Object.entries(doc.fields)) result[k] = parseFirestoreValue(v);
  return result;
}

async function listCollection(token, collectionPath) {
  let docs = [];
  let pageToken = "";
  do {
    const q = pageToken ? `?pageSize=300&pageToken=${encodeURIComponent(pageToken)}` : `?pageSize=300`;
    const res = await httpsRequest({
      hostname: "firestore.googleapis.com",
      path: `/v1/projects/${PROJECT_ID}/databases/(default)/documents/${collectionPath}${q}`,
      method: "GET",
      headers: { Authorization: `Bearer ${token}` },
    });
    if (res.status === 404) return [];
    if (res.status !== 200) throw new Error(`Failed list ${collectionPath}: ${res.raw}`);
    const batch = (res.data.documents || []).map(parseFirestoreDoc).filter(Boolean);
    docs = docs.concat(batch);
    pageToken = res.data.nextPageToken || "";
  } while (pageToken);
  return docs;
}

async function main() {
  const provider = new ethers.JsonRpcProvider("https://mainnet.base.org", 8453, { staticNetwork: true });
  const rawKey = (
    process.env.PRIVATE_KEY ||
    execSync("firebase functions:secrets:access BACKEND_SIGNER_PRIVATE_KEY --project diaspora-nearby-a3dac", {
      encoding: "utf8",
    })
  ).trim();
  const pk = rawKey.startsWith("0x") ? rawKey : "0x" + rawKey;
  const deployer = new ethers.Wallet(pk, provider);

  const tokenArtifact = JSON.parse(
    fs.readFileSync(path.resolve("artifacts/contracts/DiasporaToken.sol/DiasporaToken.json"), "utf8")
  );
  const tgeArtifact = JSON.parse(
    fs.readFileSync(path.resolve("artifacts/contracts/DiasporaTGEControllerV2.sol/DiasporaTGEControllerV2.json"), "utf8")
  );

  console.log("=".repeat(68));
  console.log("  Option C — Deploy UUPS Implementations & Build Safe Batch");
  console.log("=".repeat(68));
  console.log("  Deployer EOA:     ", deployer.address);
  console.log("  ETH Balance:      ", ethers.formatEther(await provider.getBalance(deployer.address)), "ETH");
  console.log("  Token Proxy:      ", TOKEN_PROXY);
  console.log("  TGE Proxy:        ", TGE_PROXY);
  console.log("  Admin Safe (2/3): ", ADMIN_SAFE);

  console.log("\n→ [1/3] Deploying new implementation contracts on Base Mainnet...");
  const TokenFactory = new ethers.ContractFactory(tokenArtifact.abi, tokenArtifact.bytecode, deployer);
  const tokenImplContract = await TokenFactory.deploy();
  await tokenImplContract.waitForDeployment();
  const tokenImpl = await tokenImplContract.getAddress();
  console.log("  ✅ DiasporaToken implementation deployed at:        ", tokenImpl);

  const TGEV2Factory = new ethers.ContractFactory(tgeArtifact.abi, tgeArtifact.bytecode, deployer);
  const tgeImplContract = await TGEV2Factory.deploy();
  await tgeImplContract.waitForDeployment();
  const tgeImpl = await tgeImplContract.getAddress();
  console.log("  ✅ DiasporaTGEControllerV2 implementation deployed at:", tgeImpl);

  console.log("\n→ [2/3] Auditing live on-chain balances & Firestore targets...");
  const fbToken = await getAccessToken();
  const [users, comms] = await Promise.all([
    listCollection(fbToken, "users"),
    listCollection(fbToken, "communities"),
  ]);

  const erc20 = new ethers.Contract(
    TOKEN_PROXY,
    ["function balanceOf(address) view returns (uint256)", "function totalSupply() view returns (uint256)"],
    provider
  );

  const totalSupplyBefore = await erc20.totalSupply();
  const targetSupply = ethers.parseUnits("1000000", 18);
  const totalBurnNeeded = totalSupplyBefore - targetSupply; // 1,000,000e18

  const commTargetByWallet = new Map();
  for (const c of comms) {
    if (!c.walletAddress || !c.walletAddress.startsWith("0x")) continue;
    if (String(c.id).startsWith("bilateral_")) continue;
    const addr = ethers.getAddress(c.walletAddress.toLowerCase());
    commTargetByWallet.set(addr, (commTargetByWallet.get(addr) || 0) + Number(c.awardedBalance || c.points || 0));
  }

  const commExcessRows = [];
  for (const [addr, targetNum] of commTargetByWallet.entries()) {
    const balWei = await erc20.balanceOf(addr);
    await new Promise((r) => setTimeout(r, 70));
    const targetWei = ethers.parseUnits(String(targetNum), 18);
    if (balWei > targetWei) {
      commExcessRows.push({ addr, balWei, targetWei, excessWei: balWei - targetWei });
    }
  }

  const foundersAddr = ethers.getAddress(FOUNDERS_SAFE.toLowerCase());
  const liquidityAddr = ethers.getAddress(LIQUIDITY_SAFE.toLowerCase());
  const deployerAddr = ethers.getAddress(DEPLOYER_EOA.toLowerCase());
  const creatorAddr = ethers.getAddress(CREATOR_METAMASK.toLowerCase());
  const deadAddr = ethers.getAddress(BURN_ADDRESS.toLowerCase());
  const tgeAddr = ethers.getAddress(TGE_PROXY.toLowerCase());

  const [foundersBal, liquidityBal, deployerBal, creatorBal, deadBal, tgeBal] = await Promise.all([
    erc20.balanceOf(foundersAddr),
    erc20.balanceOf(liquidityAddr),
    erc20.balanceOf(deployerAddr),
    erc20.balanceOf(creatorAddr),
    erc20.balanceOf(deadAddr),
    erc20.balanceOf(tgeAddr),
  ]);

  const fivePctWei = ethers.parseUnits("39480", 18);
  const aeroPoolWei = ethers.parseUnits("10000", 18);
  const liquiditySafeTargetWei = fivePctWei - aeroPoolWei; // 29,480 $DIASPORA in Safe + 10,000 in Aerodrome Pool = 39,480 total!

  const adjustments = [
    { label: "TGEController excess", addr: tgeAddr, excessWei: ethers.parseUnits("602150.5", 18) },
    { label: "0x...dEaD excess over 39,480", addr: deadAddr, excessWei: deadBal - fivePctWei },
    { label: "Deployer EOA excess", addr: deployerAddr, excessWei: deployerBal },
    { label: "Creator MetaMask leftover", addr: creatorAddr, excessWei: creatorBal },
    { label: "Founders Safe excess over 39,480", addr: foundersAddr, excessWei: foundersBal - fivePctWei },
    { label: "Liquidity Safe excess over 29,480", addr: liquidityAddr, excessWei: liquidityBal - liquiditySafeTargetWei },
    ...commExcessRows.map((r) => ({ label: `Comm ${r.addr}`, addr: r.addr, excessWei: r.excessWei })),
  ];

  let totalExcessWei = 0n;
  for (const a of adjustments) {
    totalExcessWei += a.excessWei;
  }

  console.log(`  Total Supply Before: ${ethers.formatEther(totalSupplyBefore)} $DIASPORA`);
  console.log(`  Target Supply After: ${ethers.formatEther(targetSupply)} $DIASPORA`);
  console.log(`  Total Burn Needed:   ${ethers.formatEther(totalBurnNeeded)} $DIASPORA`);
  console.log(`  Total Excess Found:  ${ethers.formatEther(totalExcessWei)} $DIASPORA`);

  const burnTargets = [];
  const burnAmounts = [];
  const reclaimTargets = [];
  const reclaimAmounts = [];

  let remainingToBurn = totalBurnNeeded;
  for (const a of adjustments) {
    if (a.excessWei <= 0n) continue;
    if (remainingToBurn >= a.excessWei) {
      burnTargets.push(a.addr);
      burnAmounts.push(a.excessWei);
      remainingToBurn -= a.excessWei;
    } else if (remainingToBurn > 0n) {
      burnTargets.push(a.addr);
      burnAmounts.push(remainingToBurn);
      const reclaimPart = a.excessWei - remainingToBurn;
      reclaimTargets.push(a.addr);
      reclaimAmounts.push(reclaimPart);
      remainingToBurn = 0n;
    } else {
      reclaimTargets.push(a.addr);
      reclaimAmounts.push(a.excessWei);
    }
  }

  if (remainingToBurn !== 0n) {
    throw new Error(`Remaining to burn is non-zero: ${ethers.formatEther(remainingToBurn)}`);
  }

  const totalBurnedSum = burnAmounts.reduce((s, x) => s + x, 0n);
  const totalReclaimedSum = reclaimAmounts.reduce((s, x) => s + x, 0n);
  const burnedFromTge = burnTargets[0] === tgeAddr ? burnAmounts[0] : 0n;
  const expectedTgeFinalBal = tgeBal - burnedFromTge + totalReclaimedSum;

  console.log(`  Total Burned in Call:          ${ethers.formatEther(totalBurnedSum)} $DIASPORA`);
  console.log(`  Total Reclaimed to Controller: ${ethers.formatEther(totalReclaimedSum)} $DIASPORA`);
  console.log(`  Expected Final TGE Balance:    ${ethers.formatEther(expectedTgeFinalBal)} $DIASPORA`);

  const genesisUsers = [];
  const genesisAmounts = [];
  let sumUserTokensWei = 0n;
  for (const u of users) {
    if (!u.walletAddress || !u.walletAddress.startsWith("0x")) continue;
    const addr = ethers.getAddress(u.walletAddress.toLowerCase());
    const b = await erc20.balanceOf(addr);
    await new Promise((r) => setTimeout(r, 60));
    if (b > 0n) {
      genesisUsers.push(addr);
      genesisAmounts.push(b);
      sumUserTokensWei += b;
    }
  }

  const finalTotalMinted = targetSupply;
  const finalTotalBurned = fivePctWei;
  const finalTotalDistributed = finalTotalMinted - expectedTgeFinalBal - finalTotalBurned;
  const finalEpochDistributed = finalTotalDistributed + finalTotalBurned;
  const maxGenesisCap = ethers.parseUnits("70000", 18);

  const statsArray = [
    "1",
    "7",
    finalTotalMinted.toString(),
    finalTotalDistributed.toString(),
    finalTotalBurned.toString(),
    "7",
    finalTotalMinted.toString(),
    finalEpochDistributed.toString(),
    sumUserTokensWei.toString(),
    maxGenesisCap.toString(),
  ];

  const tokenReconcileData = TokenFactory.interface.encodeFunctionData("adminReconcileSupply", [
    burnTargets,
    burnAmounts,
    reclaimTargets,
    reclaimAmounts,
    tgeAddr,
  ]);
  const tokenUpgradeCalldata = TokenFactory.interface.encodeFunctionData("upgradeToAndCall", [
    tokenImpl,
    tokenReconcileData,
  ]);

  const tgeReconcileData = TGEV2Factory.interface.encodeFunctionData("adminReconcileState", [
    statsArray,
    genesisUsers,
    genesisAmounts,
  ]);
  const tgeUpgradeCalldata = TGEV2Factory.interface.encodeFunctionData("upgradeToAndCall", [
    tgeImpl,
    tgeReconcileData,
  ]);

  // Simulate both upgradeToAndCall transactions as if called by ADMIN_SAFE using eth_call!
  console.log("\n→ [3/3] Simulating both upgradeToAndCall transactions from Admin Safe via eth_call...");
  const sim1 = await provider.call({
    from: ADMIN_SAFE,
    to: TOKEN_PROXY,
    data: tokenUpgradeCalldata,
  });
  console.log("  ✅ Simulation 1 (DiasporaToken.upgradeToAndCall) succeeded! Return:", sim1);

  const sim2 = await provider.call({
    from: ADMIN_SAFE,
    to: TGE_PROXY,
    data: tgeUpgradeCalldata,
  });
  console.log("  ✅ Simulation 2 (DiasporaTGEController.upgradeToAndCall) succeeded! Return:", sim2);

  const safeBatch = {
    version: "1.0",
    chainId: "8453",
    createdAt: Date.now(),
    meta: {
      name: "Option C: UUPS Upgrade & Epoch 1 (1,000,000 $DIASPORA) Supply Reconciliation",
      description:
        "1. Upgrade DiasporaToken (0x55d7...7735) and atomically burn 1,000,000 excess $DIASPORA + align treasury/controller balances to Epoch 1 (TDE 7).\n2. Upgrade DiasporaTGEController (0xb6C0...4d45) to enable distributeGenesisTokens (70k cap) and reset Epoch 1 / TDE 7 accounting with 0 drift.",
      txBuilderVersion: "1.16.5",
      createdFromSafeAddress: ADMIN_SAFE,
    },
    transactions: [
      {
        to: TOKEN_PROXY,
        value: "0",
        data: tokenUpgradeCalldata,
        contractMethod: {
          inputs: [
            { internalType: "address", name: "newImplementation", type: "address" },
            { internalType: "bytes", name: "data", type: "bytes" },
          ],
          name: "upgradeToAndCall",
          payable: true,
        },
        contractInputsValues: {
          newImplementation: tokenImpl,
          data: tokenReconcileData,
        },
      },
      {
        to: TGE_PROXY,
        value: "0",
        data: tgeUpgradeCalldata,
        contractMethod: {
          inputs: [
            { internalType: "address", name: "newImplementation", type: "address" },
            { internalType: "bytes", name: "data", type: "bytes" },
          ],
          name: "upgradeToAndCall",
          payable: true,
        },
        contractInputsValues: {
          newImplementation: tgeImpl,
          data: tgeReconcileData,
        },
      },
    ],
  };

  const outPath = path.resolve("safe-option-c-reconcile-epoch1.json");
  fs.writeFileSync(outPath, JSON.stringify(safeBatch, null, 2));
  console.log(`\n✅ Wrote Safe Transaction Builder batch JSON to: ${outPath}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
