import { getApps, initializeApp, cert } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import hre from "hardhat";
import { createRequire } from "node:module";
import "dotenv/config";

// Initialize Firebase Admin
const require = createRequire(import.meta.url);
const serviceAccount = require("../../tools/admin-scripts/service-account-key.json");
if (!getApps().length) {
    initializeApp({
        credential: cert(serviceAccount)
    });
}
const db = getFirestore();

// ----------------------------------------------------------------------------
// Base Mainnet Addresses
// ----------------------------------------------------------------------------
const AERODROME_ROUTER_ADDRESS = "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43";
const USDC_ADDRESS = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"; // Native USDC on Base
const TARGET_VELOCITY = 1.0; 
const NETWORK_MULTIPLIER = 3.5;

async function main() {
    console.log("=".repeat(60));
    console.log("  $DIASPORA — Aerodrome Initial Liquidity Provision");
    console.log("=".repeat(60));

    const connection = await hre.network.getOrCreate();
    const { ethers } = connection;
    const [treasury] = await ethers.getSigners();
    
    console.log("Signer Account:", treasury.address);
    const ethBalance = await ethers.provider.getBalance(treasury.address);
    console.log("ETH Balance:", ethers.formatEther(ethBalance));

    const TOKEN_ADDRESS = process.env.TOKEN_ADDRESS || "0x55d7e7d006938A15082752225ED44Fd130B87735";

    // 1. Fetch real-time Economy Stats from Firestore (mirroring dsp_valuation_provider)
    console.log("\n📊 Fetching real-time economy stats from Firestore...");
    
    // Fetch global users
    const communityDoc = await db.collection("communities").doc("global_community").get();
    let totalUsers = 0;
    if (communityDoc.exists) {
        totalUsers = communityDoc.data().memberCount || 0;
    }

    // Fetch total supply
    const supplyDoc = await db.collection("system_stats").doc("dsp_supply").get();
    let totalTokensMinted = 0;
    if (supplyDoc.exists) {
        totalTokensMinted = supplyDoc.data().totalMinted || 0;
    }

    // Fetch treasury data (GDP and burned)
    const treasuryDoc = await db.collection("system_stats").doc("treasury").get();
    let totalFiatGdpUsd = 0;
    let totalBurned = 0;
    if (treasuryDoc.exists) {
        totalFiatGdpUsd = treasuryDoc.data().totalFiatGdpUsd || 0;
        totalBurned = treasuryDoc.data().totalBurnedUtility || 0;
    }
    
    let currentEpoch = 1;

    // Day 1 Fallback mapping if metrics are completely empty
    if (totalUsers === 0 && totalTokensMinted === 0) {
        console.warn("⚠️ Firestore stats are 0, using Epoch 1 fallback mapping.");
        totalTokensMinted = 1000000;
        totalUsers = 100;
        currentEpoch = 1;
        totalBurned = 0;
    }

    console.log(`   Total Users: ${totalUsers.toLocaleString()}`);
    console.log(`   Circulating Supply: ${totalTokensMinted.toLocaleString()} $DIASPORA`);
    console.log(`   Total Fiat GDP: $${totalFiatGdpUsd.toLocaleString()}`);

    // 2. Calculate Initial Price (using the 4-Variable Implied DSP Formula)
    const basePriceUsd = 0.001;
    const networkMultiplier = totalUsers > 0 ? Math.log10(Math.max(totalUsers, 1)) / 10.0 : 0.0;
    const rawDeflation = totalTokensMinted > 0 ? totalBurned / totalTokensMinted : 0.0;
    const deflationRatio = Math.min(rawDeflation, 0.5);
    const epochScarcity = 1.0 + (Math.max(currentEpoch, 1) * 0.1);
    const fiatGdpBoost = totalFiatGdpUsd > 0 ? 1.0 + Math.log10(Math.max(totalFiatGdpUsd, 1.0)) / 10.0 : 1.0;

    const publicPrice = basePriceUsd * (1.0 + networkMultiplier + deflationRatio) * epochScarcity * fiatGdpBoost;
    
    console.log(`\n💰 Calculated Initial Price: $${publicPrice.toFixed(5)} per $DIASPORA`);
    console.log(`   (Base: $0.001 * Network: +${networkMultiplier.toFixed(3)} * Deflation: +${deflationRatio.toFixed(3)} * Epoch: x${epochScarcity} * GDP: x${fiatGdpBoost.toFixed(3)})`);

    // 3. Connect to ERC20 Tokens & Check Real On-Chain Balances
    const ERC20_ABI = [
        "function approve(address spender, uint256 amount) external returns (bool)",
        "function balanceOf(address account) external view returns (uint256)",
        "function decimals() external view returns (uint8)"
    ];
    const diasporaToken = new ethers.Contract(TOKEN_ADDRESS, ERC20_ABI, treasury);
    const usdcToken = new ethers.Contract(USDC_ADDRESS, ERC20_ABI, treasury);

    const dspBalance = await diasporaToken.balanceOf(treasury.address);
    const usdcBalance = await usdcToken.balanceOf(treasury.address);
    const dspDecimals = await diasporaToken.decimals();
    const usdcDecimals = await usdcToken.decimals();

    console.log(`\n💳 Signer Balances on Base Mainnet:`);
    console.log(`   $DIASPORA: ${ethers.formatUnits(dspBalance, dspDecimals)}`);
    console.log(`   USDC:      ${ethers.formatUnits(usdcBalance, usdcDecimals)}`);

    if (dspBalance === 0n || usdcBalance === 0n) {
        console.error("\n❌ Insufficient balance in signer account.");
        console.error(`   Signer ${treasury.address} needs both $DIASPORA and USDC on Base Mainnet.`);
        console.error(`   Please transfer $12.40 USDC to ${treasury.address} to execute pool creation.`);
        process.exit(1);
    }

    // Determine deposit ratio
    const usdcAmountNum = Number(ethers.formatUnits(usdcBalance, usdcDecimals));
    const requiredDiasporaNum = usdcAmountNum / publicPrice;
    
    const usdcAmountWei = usdcBalance;
    const dspDecimalsNum = Number(dspDecimals);
    const diasporaAmountWei = ethers.parseUnits(requiredDiasporaNum.toFixed(dspDecimalsNum), dspDecimalsNum);

    if (diasporaAmountWei > dspBalance) {
        console.error(`\n❌ Signer only has ${ethers.formatUnits(dspBalance, dspDecimals)} $DIASPORA, but ${requiredDiasporaNum.toFixed(2)} is needed to match ${usdcAmountNum} USDC at $${publicPrice.toFixed(5)}.`);
        process.exit(1);
    }

    console.log(`\n🚀 Executing Aerodrome Deposit:`);
    console.log(`   USDC Amount:       ${usdcAmountNum}`);
    console.log(`   $DIASPORA Amount:  ${requiredDiasporaNum}`);

    // 5. Approve Router
    console.log("\n🔓 Approving Aerodrome Router...");
    const txApproveDsp = await diasporaToken.approve(AERODROME_ROUTER_ADDRESS, diasporaAmountWei);
    await txApproveDsp.wait();
    console.log("   ✅ Approved $DIASPORA");

    const txApproveUsdc = await usdcToken.approve(AERODROME_ROUTER_ADDRESS, usdcAmountWei);
    await txApproveUsdc.wait();
    console.log("   ✅ Approved USDC");

    // 6. Add Liquidity
    const ROUTER_ABI = [
        "function addLiquidity(address tokenA, address tokenB, bool stable, uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline) external returns (uint256 amountA, uint256 amountB, uint256 liquidity)"
    ];
    const router = new ethers.Contract(AERODROME_ROUTER_ADDRESS, ROUTER_ABI, treasury);

    const deadline = Math.floor(Date.now() / 1000) + 60 * 20; // 20 minutes
    const isStable = false; // Volatile pool (v2 style) for non-pegged assets

    console.log("\n💧 Adding Liquidity to Aerodrome...");
    const tx = await router.addLiquidity(
        TOKEN_ADDRESS,
        USDC_ADDRESS,
        isStable,
        diasporaAmountWei,
        usdcAmountWei,
        (diasporaAmountWei * 95n) / 100n, // 5% slippage
        (usdcAmountWei * 95n) / 100n,     // 5% slippage
        treasury.address,
        deadline
    );
    const receipt = await tx.wait();
    console.log(`   ✅ Liquidity Added! TX Hash: ${receipt.hash}`);
    console.log(`\n🔗 Verify on Basescan: https://basescan.org/tx/${receipt.hash}`);
    
    console.log("\n🎉 Aerodrome setup complete! Pool is live on Base Mainnet!");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
