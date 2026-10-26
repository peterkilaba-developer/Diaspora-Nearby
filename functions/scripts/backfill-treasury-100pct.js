/**
 * Backfill all Community, State Reserve, Continental Sovereign Bond, and System
 * Treasuries in Firestore to:
 *   1. Convert at 100% efficiency (`averagePoCT: 100`, `averagePct: 100`).
 *   2. Rename continental treasuries to `<Continent> Sovereign Bond Treasury`
 *      (without "Community").
 *   3. Reconcile active unconverted DSP balances (`points` / `treasuryBalance`)
 *      against on-chain $DIASPORA balances (`awardedBalance - onChainBalance`),
 *      so:
 *        - Treasuries that already converted on-chain (e.g. Global Reserve,
 *          Founders, Liquidity) have their already-minted $DIASPORA deducted.
 *        - Community treasuries that were shortchanged in earlier TDEs (when
 *          efficiency was < 100%) retain 100% of their unconverted DSP as
 *          carried-over DSP ready to convert at 100% efficiency in the next TDE.
 *
 * Usage:
 *   node functions/scripts/backfill-treasury-100pct.js          # dry run
 *   node functions/scripts/backfill-treasury-100pct.js --apply  # write changes
 */
const fs = require("fs");
const os = require("os");
const path = require("path");
const {Firestore, FieldValue} = require("@google-cloud/firestore");
const {ethers} = require("ethers");

function loadEnv(envPath) {
  if (!fs.existsSync(envPath)) return;
  const lines = fs.readFileSync(envPath, "utf8").split("\n");
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eqIdx = trimmed.indexOf("=");
    if (eqIdx === -1) continue;
    const key = trimmed.substring(0, eqIdx).trim();
    const value = trimmed.substring(eqIdx + 1).trim();
    if (!process.env[key]) process.env[key] = value;
  }
}
loadEnv(path.join(__dirname, "..", ".env"));

function createFirestoreClient() {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "diaspora-nearby-a3dac";
  try {
    const cfgPath = path.join(os.homedir(), ".config", "configstore", "firebase-tools.json");
    if (fs.existsSync(cfgPath)) {
      const cfg = JSON.parse(fs.readFileSync(cfgPath, "utf8"));
      if (cfg.tokens && cfg.tokens.access_token) {
        const authClient = {
          getAccessToken: async () => ({
            token: cfg.tokens.access_token,
            res: null,
          }),
          getRequestHeaders: async () => ({
            Authorization: `Bearer ${cfg.tokens.access_token}`,
          }),
        };
        return new Firestore({
          projectId,
          authClient,
          preferRest: true,
        });
      }
    }
  } catch (_) {
    // Fall back to default credentials
  }
  return new Firestore({projectId});
}

const DRY_RUN = !process.argv.includes("--apply");
const TOKEN_ADDRESS = "0x55d7e7d006938A15082752225ED44Fd130B87735";
const ERC20_ABI = ["function balanceOf(address account) external view returns (uint256)"];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const ADJECTIVE_MAP = {
  "africa": "African",
  "asia": "Asian",
  "europe": "European",
  "north america": "North American",
  "south america": "South American",
  "oceania": "Oceanian",
  "antarctica": "Antarctic",
  "caribbean": "Caribbean",
};

const REVERSE_ADJECTIVE_MAP = {
  "african": "Africa",
  "asian": "Asia",
  "european": "Europe",
  "north american": "North America",
  "south american": "South America",
  "oceanian": "Oceania",
  "antarctic": "Antarctica",
  "caribbean": "Caribbean",
};

function cleanBasePlaceName(rawName) {
  let cleaned = String(rawName || "").trim();
  const suffixPattern = /\s+(?:Sovereign\s+Bond\s+Treasury|Continental\s+Treasury|Reserve\s+Treasury|DDI\s+Treasury|Sovereign\s+Bond|Continental|Reserve|DDI|Treasury|Community)$/i;
  while (suffixPattern.test(cleaned)) {
    cleaned = cleaned.replace(suffixPattern, "").trim();
  }
  return cleaned;
}

function resolveCanonicalBasePlace(rawName, commId, govId) {
  let base = cleanBasePlaceName(rawName);
  const effectiveId = String(commId || govId || "");
  const isContinent = effectiveId.includes("continent");
  const isHost = effectiveId.startsWith("host_") || effectiveId.startsWith("past_") || /_[a-z]{2}$/i.test(effectiveId);

  if (isContinent) {
    const slug = effectiveId
      .replace(/^(home_|host_|past_)?continent_/, "")
      .replace(/_[a-z]{2}$/i, "");
    const fromSlug = slug
      .split("-")
      .filter(Boolean)
      .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
      .join(" ");
    const candidate = fromSlug || base;
    const canonicalNoun = REVERSE_ADJECTIVE_MAP[candidate.toLowerCase()] || candidate;
    if (isHost) {
      return canonicalNoun;
    }
    return ADJECTIVE_MAP[canonicalNoun.toLowerCase()] || canonicalNoun;
  }

  return base;
}

function formatCanonicalCommunityName(rawName, commId, govId) {
  if (commId === "global_community" || govId === "global_community") return "Global Community";
  const base = resolveCanonicalBasePlace(rawName, commId, govId);
  return base ? `${base} Community` : null;
}

function formatCanonicalTreasuryTitle(rawName, commId, govId, commType) {
  if (commId === "global_community" || govId === "global_community" || commType === "global") {
    return "Global Reserve";
  }
  const effectiveId = String(commId || govId || "");
  const base = resolveCanonicalBasePlace(rawName, commId, govId);
  const isContinent = commType === "continent" || /(^|_)continent_/.test(effectiveId);
  const isState = commType === "state" || commType === "province" || /(^|_)state_/.test(effectiveId);
  const suffix = isContinent
    ? "Sovereign Bond Treasury"
    : (isState ? "Reserve Treasury" : "DDI Treasury");
  return base ? `${base} ${suffix}` : suffix;
}

async function main() {
  const db = createFirestoreClient();
  const provider = new ethers.JsonRpcProvider(process.env.RPC_URL || "https://mainnet.base.org");
  const token = new ethers.Contract(TOKEN_ADDRESS, ERC20_ABI, provider);

  console.log(`\n=== Treasury 100% Efficiency & Balance Reconciliation Backfill (${DRY_RUN ? "DRY RUN" : "APPLY"}) ===\n`);

  // 1. Load users and user_points to compute exact lifetime awarded DSP per slot
  const [usersSnap, userPointsSnap, commSnap, govSnap] = await Promise.all([
    db.collection("users").get(),
    db.collection("user_points").get(),
    db.collection("communities").get(),
    db.collection("governance").get(),
  ]);

  const userProfiles = {};
  usersSnap.forEach((doc) => {
    userProfiles[doc.id] = doc.data();
  });

  const communityAwardedMap = {};
  const communityBasisMap = {};
  const communityMemberPointsMap = {};

  let totalUserPoints = 0;
  let totalSystemSlotAwarded = 0;

  userPointsSnap.forEach((doc) => {
    const userId = doc.id;
    const pointsData = doc.data();
    const userPoints = Number(pointsData.totalPoints || 0);
    if (userPoints <= 0) return;

    totalUserPoints += userPoints;
    const unit = Math.floor(userPoints * 0.10); // 10% of the 1:1 Ubuntu matching pool per slot (10 slots = 100% match)
    totalSystemSlotAwarded += unit;

    const userMemberships = (userProfiles[userId] || {}).communityMemberships || [];
    const findMembership = (prefix) => {
      const match = userMemberships.find((id) => String(id).startsWith(prefix));
      return match ? String(match) : "";
    };

    const slotFractions = {};
    const addSlot = (id, fraction) => {
      const effectiveId = (!id || id === "") ? "global_community" : id;
      slotFractions[effectiveId] = (slotFractions[effectiveId] || 0) + fraction;
    };

    addSlot("global_community", 1.0);

    const homeContinent = findMembership("home_continent_");
    const homeCountry = findMembership("home_country_");
    const homeState = findMembership("home_state_");
    const homeCity = findMembership("home_city_");

    addSlot(homeContinent, 1.0);
    if (homeState) {
      addSlot(homeCountry, 0.5);
      addSlot(homeState, 0.5);
    } else {
      addSlot(homeCountry, 1.0);
    }
    addSlot(homeCity, 1.0);

    const hostContinent = findMembership("host_continent_");
    const hostCountry = findMembership("host_country_");
    const hostState = findMembership("host_state_");
    const hostCity = findMembership("host_city_");

    addSlot(hostContinent, 1.0);
    if (hostState) {
      addSlot(hostCountry, 0.5);
      addSlot(hostState, 0.5);
    } else {
      addSlot(hostCountry, 1.0);
    }
    addSlot(hostCity, 1.0);

    for (const [cid, fraction] of Object.entries(slotFractions)) {
      const slotUnit = Math.round(unit * fraction);
      const slotBasis = Math.round(userPoints * fraction);

      communityAwardedMap[cid] = (communityAwardedMap[cid] || 0) + slotUnit;
      communityBasisMap[cid] = (communityBasisMap[cid] || 0) + slotBasis + slotUnit;
      communityMemberPointsMap[cid] = (communityMemberPointsMap[cid] || 0) + slotBasis;
    }
  });

  // 2. Map governance docs and fetch their on-chain $DIASPORA balances
  const govDocsMap = {};
  const onChainBalances = {};

  for (const doc of govSnap.docs) {
    const d = doc.data();
    govDocsMap[doc.id] = d;
    const w = d.walletAddress;
    if (w && w.startsWith("0x") && w.length === 42 && doc.id !== "burn") {
      await sleep(75);
      const balWei = await token.balanceOf(w);
      onChainBalances[doc.id] = Math.floor(Number(ethers.formatUnits(balWei, 18)));
    } else {
      onChainBalances[doc.id] = 0;
    }
  }

  // System slots: Founders, Liquidity, Burn
  // Note: `0x...dEaD` holds both 10% system burn AND TDE inefficiency penalty burns,
  // so for the 10% system `burn` slot we use the same converted baseline as `founders`/`liquidity`.
  const foundersConverted = onChainBalances["founders"] || 0;
  const liquidityConverted = onChainBalances["liquidity"] || 0;
  const burnSlotConverted = Math.max(foundersConverted, liquidityConverted);

  const reconciledFoundersDsp = Math.max(0, totalSystemSlotAwarded - foundersConverted);
  const reconciledLiquidityDsp = Math.max(0, totalSystemSlotAwarded - liquidityConverted);
  const reconciledBurnDsp = Math.max(0, totalSystemSlotAwarded - burnSlotConverted);

  console.log("System Treasuries:");
  console.log(`  founders  | awarded=${totalSystemSlotAwarded} | onChain=${foundersConverted} | activeDsp: ${govDocsMap.founders?.treasuryBalance} -> ${reconciledFoundersDsp}`);
  console.log(`  liquidity | awarded=${totalSystemSlotAwarded} | onChain=${liquidityConverted} | activeDsp: ${govDocsMap.liquidity?.treasuryBalance} -> ${reconciledLiquidityDsp}`);
  console.log(`  burn      | awarded=${totalSystemSlotAwarded} | converted=${burnSlotConverted} | activeDsp: ${govDocsMap.burn?.treasuryBalance} -> ${reconciledBurnDsp}\n`);

  // Collect all community IDs from both `communities` collection and `communityAwardedMap`
  const allCommIds = new Set([
    ...commSnap.docs.map((d) => d.id),
    ...Object.keys(communityAwardedMap),
  ]);

  const commDocsMap = {};
  commSnap.forEach((d) => {
    commDocsMap[d.id] = d.data();
  });

  const operations = [];

  // System stats + system governance docs
  operations.push({
    ref: db.collection("system_stats").doc("treasury"),
    data: {
      foundersPoints: reconciledFoundersDsp,
      liquidityPoints: reconciledLiquidityDsp,
      burnedPoints: reconciledBurnDsp,
      lastUpdated: FieldValue.serverTimestamp(),
    },
  });
  operations.push({
    ref: db.collection("governance").doc("founders"),
    data: {
      name: "Founders & Core Team",
      title: "Founders & Core Team",
      treasuryBalance: reconciledFoundersDsp,
      averagePct: 100,
      averagePoCT: 100,
      updatedAt: FieldValue.serverTimestamp(),
    },
  });
  operations.push({
    ref: db.collection("governance").doc("liquidity"),
    data: {
      name: "Liquidity Treasury",
      title: "Liquidity Treasury",
      treasuryBalance: reconciledLiquidityDsp,
      averagePct: 100,
      averagePoCT: 100,
      updatedAt: FieldValue.serverTimestamp(),
    },
  });
  operations.push({
    ref: db.collection("governance").doc("burn"),
    data: {
      name: "Natural Burn Pool",
      title: "Natural Burn Pool",
      treasuryBalance: reconciledBurnDsp,
      averagePct: 100,
      averagePoCT: 100,
      updatedAt: FieldValue.serverTimestamp(),
    },
  });

  console.log("Community, State Reserve & Sovereign Bond Treasuries:");
  for (const commId of Array.from(allCommIds).sort()) {
    const existingComm = commDocsMap[commId] || {};
    const govId = commId === "global_community"
      ? "global_community"
      : (commId.includes("_") ? commId.substring(commId.indexOf("_") + 1) : commId);
    const existingGov = govDocsMap[govId] || {};

    const awarded = communityAwardedMap[commId] !== undefined
      ? communityAwardedMap[commId]
      : Number(existingComm.awardedBalance || existingComm.points || existingGov.treasuryBalance || 0);
    const onChain = onChainBalances[govId] || 0;
    const reconciledDsp = Math.max(0, awarded - onChain);

    const canonicalCommName = formatCanonicalCommunityName(
      existingComm.name || existingGov.name,
      commId,
      govId
    );
    const canonicalTreasuryTitle = formatCanonicalTreasuryTitle(
      existingComm.name || existingGov.name,
      commId,
      govId,
      existingComm.type
    );

    console.log(
      `  ${commId.padEnd(46)} | awarded=${String(awarded).padEnd(7)} | onChain=${String(onChain).padEnd(7)} | dsp: ${String(existingComm.points ?? 0).padEnd(7)} -> ${String(reconciledDsp).padEnd(7)} | comm="${canonicalCommName}" | treasury="${canonicalTreasuryTitle}"`
    );

    const commPatch = {
      points: reconciledDsp,
      awardedBalance: awarded,
      averagePct: 100,
      averagePoCT: 100,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (communityBasisMap[commId] !== undefined) {
      commPatch.cumulativeEarnings = communityBasisMap[commId];
    }
    if (communityMemberPointsMap[commId] !== undefined) {
      commPatch.memberPoints = communityMemberPointsMap[commId];
    }
    if (canonicalCommName) {
      commPatch.name = canonicalCommName;
    }

    operations.push({
      ref: db.collection("communities").doc(commId),
      data: commPatch,
    });

    operations.push({
      ref: db.collection("communities").doc(commId).collection("treasury").doc("current"),
      data: {
        points: reconciledDsp,
        awardedBalance: awarded,
        ...(communityBasisMap[commId] !== undefined ? {cumulativeEarnings: communityBasisMap[commId]} : {}),
        ...(communityMemberPointsMap[commId] !== undefined ? {memberPoints: communityMemberPointsMap[commId]} : {}),
        averagePct: 100,
        averagePoCT: 100,
        updatedAt: FieldValue.serverTimestamp(),
      },
    });

    const govPatch = {
      treasuryBalance: reconciledDsp,
      averagePct: 100,
      averagePoCT: 100,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (canonicalTreasuryTitle) {
      govPatch.name = canonicalTreasuryTitle;
      govPatch.title = canonicalTreasuryTitle;
    }
    operations.push({
      ref: db.collection("governance").doc(govId),
      data: govPatch,
    });
  }

  // Also ensure any standalone governance docs not in allCommIds (except investors) get averagePoCT=100
  const SYSTEM_DOC_IDS = new Set(["founders", "liquidity", "investors", "burn"]);
  for (const doc of govSnap.docs) {
    if (SYSTEM_DOC_IDS.has(doc.id)) continue;
    const alreadyCovered = Array.from(allCommIds).some((cid) => {
      const gid = cid === "global_community"
        ? "global_community"
        : (cid.includes("_") ? cid.substring(cid.indexOf("_") + 1) : cid);
      return gid === doc.id;
    });
    if (!alreadyCovered) {
      const d = doc.data();
      const updatedTitle = formatCanonicalTreasuryTitle(d.name, d.communityId, doc.id, d.type);
      operations.push({
        ref: db.collection("governance").doc(doc.id),
        data: {
          averagePct: 100,
          averagePoCT: 100,
          ...(updatedTitle ? {name: updatedTitle, title: updatedTitle} : {}),
          updatedAt: FieldValue.serverTimestamp(),
        },
      });
    }
  }

  console.log(`\nTotal Firestore document writes prepared: ${operations.length}`);

  if (DRY_RUN) {
    console.log("\nDRY RUN complete. Re-run with --apply to write changes.");
    return;
  }

  const BATCH_SIZE = 400;
  for (let i = 0; i < operations.length; i += BATCH_SIZE) {
    const chunk = operations.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const op of chunk) {
      batch.set(op.ref, op.data, {merge: true});
    }
    await batch.commit();
    console.log(`Committed batch ${Math.floor(i / BATCH_SIZE) + 1} (${chunk.length} writes)`);
  }

  console.log("\n✅ Backfill applied successfully!");
}

main().catch((err) => {
  console.error("Backfill failed:", err);
  process.exit(1);
});
