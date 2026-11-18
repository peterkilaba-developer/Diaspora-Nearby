import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { ethers } = require("../../node_modules/ethers");

const RPC_URL = process.env.RPC_URL || "https://mainnet.base.org";
const TOKEN_PROXY = "0x55d7e7d006938A15082752225ED44Fd130B87735";
const TGE_PROXY = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";
const ADMIN_SAFE = "0xE06F8690e96a8BAAbCBe48664Ff1238F69082244";

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL, 8453, { staticNetwork: true });

  const tokenIface = new ethers.Interface([
    "function totalSupply() view returns (uint256)",
    "function balanceOf(address) view returns (uint256)",
    "function adminReconcileSupply(address[] burnTargets, uint256[] burnAmounts, address[] reclaimTargets, uint256[] reclaimAmounts, address reclaimRecipient)",
  ]);

  const tgeIface = new ethers.Interface([
    "function getStats() view returns (uint256 epoch, uint256 tgeEvent, uint256 minted, uint256 distributed, uint256 burned, uint256 events, uint256 welcomeBonuses)",
    "function getLockedBalance() view returns (uint256)",
    "function epochLockedSupply() view returns (uint256)",
    "function epochDistributed() view returns (uint256)",
    "function maxGenesisDistribution() view returns (uint256)",
    "function adminReconcileState(uint256[10] _stats, address[] _genesisUsers, uint256[] _genesisAmounts)",
  ]);

  const token = new ethers.Contract(TOKEN_PROXY, tokenIface, provider);
  const tge = new ethers.Contract(TGE_PROXY, tgeIface, provider);

  const [
    totalSupplyBefore,
    lockedBalBefore,
    statsBefore,
    epochLockedBefore,
    epochDistBefore,
    maxGenBefore,
  ] = await Promise.all([
    token.totalSupply(),
    tge.getLockedBalance(),
    tge.getStats(),
    tge.epochLockedSupply(),
    tge.epochDistributed(),
    tge.maxGenesisDistribution(),
  ]);

  const targetEpoch2MaxSupply = ethers.parseUnits("10000000", 18);
  if (totalSupplyBefore <= targetEpoch2MaxSupply) {
    console.log(`✅ On-chain totalSupply (${ethers.formatUnits(totalSupplyBefore, 18)}) is already <= 10,000,000.`);
    return;
  }

  const excessToBurnWei = totalSupplyBefore - targetEpoch2MaxSupply;
  if (lockedBalBefore < excessToBurnWei) {
    throw new Error(
      `TGE locked balance (${ethers.formatUnits(lockedBalBefore, 18)}) < excess (${ethers.formatUnits(excessToBurnWei, 18)})`
    );
  }

  const lockedBalAfter = lockedBalBefore - excessToBurnWei;
  const totalDistPlusBurned = statsBefore.distributed + statsBefore.burned;
  const expectedBalAfter = targetEpoch2MaxSupply - totalDistPlusBurned;
  if (expectedBalAfter !== lockedBalAfter) {
    throw new Error(`Post-burn reconciliation mismatch: expected ${expectedBalAfter} vs actual ${lockedBalAfter}`);
  }

  const targetEpochLockedAfter = lockedBalAfter + epochDistBefore;

  const tx1Data = tokenIface.encodeFunctionData("adminReconcileSupply", [
    [TGE_PROXY],
    [excessToBurnWei],
    [],
    [],
    ethers.ZeroAddress,
  ]);

  const statsTupleAfter = [
    statsBefore.epoch,
    statsBefore.tgeEvent,
    targetEpoch2MaxSupply,
    statsBefore.distributed,
    statsBefore.burned,
    statsBefore.events,
    targetEpochLockedAfter,
    epochDistBefore,
    statsBefore.welcomeBonuses,
    maxGenBefore,
  ];

  const tx2Data = tgeIface.encodeFunctionData("adminReconcileState", [
    statsTupleAfter,
    [],
    [],
  ]);

  await provider.call({ from: ADMIN_SAFE, to: TOKEN_PROXY, data: tx1Data });
  await provider.call({ from: ADMIN_SAFE, to: TGE_PROXY, data: tx2Data });

  const fmt = (w) => ethers.formatUnits(w, 18);
  const safeBatch = {
    version: "1.0",
    chainId: "8453",
    createdAt: Date.now(),
    meta: {
      name: "Epoch 2 Strict 10,000,000 $DIASPORA Max Supply Reconciliation",
      description:
        `1. Burn exact ${fmt(excessToBurnWei)} excess $DIASPORA from TGEController (${TGE_PROXY}) via DiasporaToken.adminReconcileSupply so Basescan totalSupply() equals exact 10,000,000.0 $DIASPORA (leaving all user, community treasury, Safe, and DEX balances untouched).\n` +
        `2. Align DiasporaTGEControllerV2 accounting (totalMinted = 10,000,000, epochLockedSupply = ${fmt(targetEpochLockedAfter)}) via adminReconcileState with 0.0 drift.`,
      txBuilderVersion: "1.16.5",
      createdFromSafeAddress: ADMIN_SAFE,
    },
    transactions: [
      {
        to: TOKEN_PROXY,
        value: "0",
        data: tx1Data,
        contractMethod: {
          inputs: [
            { internalType: "address[]", name: "burnTargets", type: "address[]" },
            { internalType: "uint256[]", name: "burnAmounts", type: "uint256[]" },
            { internalType: "address[]", name: "reclaimTargets", type: "address[]" },
            { internalType: "uint256[]", name: "reclaimAmounts", type: "uint256[]" },
            { internalType: "address", name: "reclaimRecipient", type: "address" },
          ],
          name: "adminReconcileSupply",
          payable: false,
        },
        contractInputsValues: {
          burnTargets: JSON.stringify([TGE_PROXY]),
          burnAmounts: JSON.stringify([excessToBurnWei.toString()]),
          reclaimTargets: "[]",
          reclaimAmounts: "[]",
          reclaimRecipient: ethers.ZeroAddress,
        },
      },
      {
        to: TGE_PROXY,
        value: "0",
        data: tx2Data,
        contractMethod: {
          inputs: [
            { internalType: "uint256[10]", name: "_stats", type: "uint256[10]" },
            { internalType: "address[]", name: "_genesisUsers", type: "address[]" },
            { internalType: "uint256[]", name: "_genesisAmounts", type: "uint256[]" },
          ],
          name: "adminReconcileState",
          payable: false,
        },
        contractInputsValues: {
          _stats: JSON.stringify(statsTupleAfter.map((x) => x.toString())),
          _genesisUsers: "[]",
          _genesisAmounts: "[]",
        },
      },
    ],
  };

  const outPath = path.resolve(import.meta.dirname, "../../safe-reconcile-epoch2-10m-supply.json");
  fs.writeFileSync(outPath, JSON.stringify(safeBatch, null, 2) + "\n", "utf8");
  console.log("✅ Simulated on Base Mainnet & wrote Safe batch:", outPath);
  console.log(`   totalSupply:       ${fmt(totalSupplyBefore)} -> ${fmt(targetEpoch2MaxSupply)} $DIASPORA`);
  console.log(`   TGE lockedBalance: ${fmt(lockedBalBefore)} -> ${fmt(lockedBalAfter)} $DIASPORA`);
  console.log(`   drift:             0.0 $DIASPORA`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
