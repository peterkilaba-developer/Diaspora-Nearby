import { MerkleTree } from "merkletreejs";
import { expect } from "chai";
import hre from "hardhat";
import { upgrades as createUpgrades } from "@openzeppelin/hardhat-upgrades";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;
const upgrades = await createUpgrades(hre, connection);

/**
 * Tests for DiasporaTGEControllerV2.
 *
 * Focuses on the NEW V2 behavior:
 *   - Storage-layout compatibility with V1 (upgradeProxy works)
 *   - User vs treasury split in distributeWelcomeBonus
 *   - Per-user cap and lifetime dedupe
 *   - Treasury recipients uncapped (no dedupe)
 *   - Merkle root commitment per batch
 *   - getReconciliation() returns expected drift
 *
 * The V1 behavior (mintEpochSupply, executeTGE, epoch rollover) is already
 * covered by DiasporaTGEController.test.js — we don't duplicate those here.
 */
describe("DiasporaTGEControllerV2", function () {
  const ONE = ethers.parseUnits("1", 18);
  const BURN = "0x000000000000000000000000000000000000dEaD";
  const ZERO_ROOT = "0x0000000000000000000000000000000000000000000000000000000000000000";
  const ROOT_A = "0x1111111111111111111111111111111111111111111111111111111111111111";

  let admin, oracle, user1, user2, founders, liquidity, communityA, communityB, attacker;
  let token, tge;
  const WELCOME_CAP = 1000n * ONE;

  beforeEach(async function () {
    [admin, oracle, user1, user2, founders, liquidity, communityA, communityB, attacker] =
      await ethers.getSigners();

    const Token = await ethers.getContractFactory("DiasporaToken");
    token = await upgrades.deployProxy(
      Token,
      [admin.address, admin.address, admin.address],
      { kind: "uups" }
    );

    // Deploy V1 first to mimic the production upgrade path
    const TGEv1 = await ethers.getContractFactory("DiasporaTGEController");
    tge = await upgrades.deployProxy(
      TGEv1,
      [admin.address, admin.address, await token.getAddress()],
      { kind: "uups" }
    );

    const MINTER_ROLE = await token.MINTER_ROLE();
    await token.grantRole(MINTER_ROLE, await tge.getAddress());

    const ORACLE_ROLE = await tge.TGE_ORACLE_ROLE();
    await tge.grantRole(ORACLE_ROLE, oracle.address);

    // Pre-mint epoch supply on V1
    await tge.connect(oracle).mintEpochSupply(100_000n * ONE);

    // Upgrade to V2 with initializeV2(welcomeCap = 1000 DIASPORA)
    const TGEv2 = await ethers.getContractFactory("DiasporaTGEControllerV2");
    tge = await upgrades.upgradeProxy(await tge.getAddress(), TGEv2, {
      call: { fn: "initializeV2", args: [WELCOME_CAP] },
    });
  });

  describe("V2 upgrade", function () {
    it("preserves V1 storage after upgrade", async function () {
      expect(await tge.currentEpoch()).to.equal(1);
      expect(await tge.totalMinted()).to.equal(100_000n * ONE);
      expect(await tge.epochLockedSupply()).to.equal(100_000n * ONE);
    });

    it("sets maxWelcomeBonusPerRecipient via initializeV2", async function () {
      expect(await tge.maxWelcomeBonusPerRecipient()).to.equal(WELCOME_CAP);
    });

    it("initializeV2 can only be called once", async function () {
      await expect(tge.initializeV2(WELCOME_CAP)).to.revert(ethers);
    });

    it("prevents a non-admin from initializing V2 state", async function () {
      const TGEv2 = await ethers.getContractFactory("DiasporaTGEControllerV2");
      const fresh = await upgrades.deployProxy(
        TGEv2,
        [admin.address, admin.address, await token.getAddress()],
        { kind: "uups" }
      );
      await expect(
        fresh.connect(attacker).initializeV2(WELCOME_CAP)
      ).to.revert(ethers);
      await fresh.connect(admin).initializeV2(WELCOME_CAP);
      expect(await fresh.maxWelcomeBonusPerRecipient()).to.equal(WELCOME_CAP);
    });

    it("admin can tune the cap with setMaxWelcomeBonusPerRecipient", async function () {
      await tge.setMaxWelcomeBonusPerRecipient(500n * ONE);
      expect(await tge.maxWelcomeBonusPerRecipient()).to.equal(500n * ONE);
    });

    it("non-admin cannot tune the cap", async function () {
      await expect(tge.connect(attacker).setMaxWelcomeBonusPerRecipient(500n * ONE)).to.revert(ethers);
    });
  });

  describe("distributeWelcomeBonus — user split", function () {
    it("pays user exactly userAmount and treasuries exactly treasuryAmounts", async function () {
      await tge.connect(oracle).distributeWelcomeBonus(
        user1.address,
        1000n * ONE,
        [BURN, founders.address, liquidity.address, communityA.address, communityB.address],
        [100n * ONE, 100n * ONE, 100n * ONE, 100n * ONE, 100n * ONE],
        ROOT_A
      );

      expect(await token.balanceOf(user1.address)).to.equal(1000n * ONE);
      expect(await token.balanceOf(founders.address)).to.equal(100n * ONE);
      expect(await token.balanceOf(liquidity.address)).to.equal(100n * ONE);
      expect(await token.balanceOf(communityA.address)).to.equal(100n * ONE);
      expect(await token.balanceOf(communityB.address)).to.equal(100n * ONE);
      expect(await token.balanceOf(BURN)).to.equal(100n * ONE);
    });

    it("records userRecipient's lifetime welcomeBonusReceived", async function () {
      await tge.connect(oracle).distributeWelcomeBonus(
        user1.address, 1000n * ONE, [BURN], [100n * ONE], ROOT_A
      );
      expect(await tge.welcomeBonusReceived(user1.address)).to.equal(1000n * ONE);
    });

    it("does NOT record welcomeBonusReceived for treasuries (uncapped)", async function () {
      await tge.connect(oracle).distributeWelcomeBonus(
        user1.address, 1000n * ONE,
        [founders.address, liquidity.address], [100n * ONE, 100n * ONE], ROOT_A
      );
      expect(await tge.welcomeBonusReceived(founders.address)).to.equal(0);
      expect(await tge.welcomeBonusReceived(liquidity.address)).to.equal(0);
    });

    it("reverts if userAmount exceeds cap", async function () {
      await expect(
        tge.connect(oracle).distributeWelcomeBonus(
          user1.address, WELCOME_CAP + 1n, [], [], ROOT_A
        )
      ).to.be.revertedWith("TGE: user amount exceeds welcome cap");
    });

    it("reverts if same user tries to receive a second welcome bonus", async function () {
      await tge.connect(oracle).distributeWelcomeBonus(
        user1.address, 1000n * ONE, [BURN], [100n * ONE], ROOT_A
      );
      await expect(
        tge.connect(oracle).distributeWelcomeBonus(
          user1.address, 1n, [], [], ROOT_A
        )
      ).to.be.revertedWith("TGE: user already received welcome bonus");
    });

    it("allows the SAME treasury to receive in many calls (uncapped)", async function () {
      // Simulate 20 signups, each crediting founders 100 DIASPORA
      for (let i = 0; i < 20; i++) {
        const wallet = ethers.Wallet.createRandom();
        await tge.connect(oracle).distributeWelcomeBonus(
          wallet.address, 1000n * ONE,
          [founders.address], [100n * ONE], ROOT_A
        );
      }
      // After V1's cap would have bricked at signup #10, V2 keeps going
      expect(await token.balanceOf(founders.address)).to.equal(2000n * ONE);
    });

    it("burn recipient correctly increments totalBurned", async function () {
      await tge.connect(oracle).distributeWelcomeBonus(
        user1.address, 1000n * ONE, [BURN], [100n * ONE], ROOT_A
      );
      expect(await tge.totalBurned()).to.equal(100n * ONE);
      expect(await token.balanceOf(BURN)).to.equal(100n * ONE);
    });

    it("reverts on zero user recipient", async function () {
      await expect(
        tge.connect(oracle).distributeWelcomeBonus(
          ethers.ZeroAddress, 1000n * ONE, [], [], ROOT_A
        )
      ).to.be.revertedWith("TGE: zero user recipient");
    });

    it("reverts on zero user amount", async function () {
      await expect(
        tge.connect(oracle).distributeWelcomeBonus(
          user1.address, 0, [], [], ROOT_A
        )
      ).to.be.revertedWith("TGE: zero user amount");
    });

    it("reverts on missing merkle root", async function () {
      await expect(
        tge.connect(oracle).distributeWelcomeBonus(
          user1.address, 1000n * ONE, [], [], ZERO_ROOT
        )
      ).to.be.revertedWith("TGE: missing merkle root");
    });

    it("reverts on treasury array length mismatch", async function () {
      await expect(
        tge.connect(oracle).distributeWelcomeBonus(
          user1.address, 1000n * ONE,
          [founders.address, liquidity.address], [100n * ONE], ROOT_A
        )
      ).to.be.revertedWith("TGE: array length mismatch");
    });

    it("rejects non-oracle caller", async function () {
      await expect(
        tge.connect(attacker).distributeWelcomeBonus(
          user1.address, 1000n * ONE, [], [], ROOT_A
        )
      ).to.revert(ethers);
    });

    it("emits WelcomeBonusDistributed with full distribution", async function () {
      await expect(
        tge.connect(oracle).distributeWelcomeBonus(
          user1.address, 1000n * ONE,
          [BURN, founders.address], [100n * ONE, 100n * ONE], ROOT_A
        )
      )
        .to.emit(tge, "WelcomeBonusDistributed")
        .withArgs(
          user1.address,
          1000n * ONE,
          [BURN, founders.address],
          [100n * ONE, 100n * ONE],
          1200n * ONE, // batchTotal
          1, // epoch
          ROOT_A
        );
    });

    it("stores merkle root keyed by (epoch, blockNumber, userRecipient)", async function () {
      const tx = await tge.connect(oracle).distributeWelcomeBonus(
        user1.address, 1000n * ONE, [], [], ROOT_A
      );
      const receipt = await tx.wait();
      const expectedKey = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["string", "uint256", "uint256", "address"],
          ["WB", 1, receipt.blockNumber, user1.address]
        )
      );
      expect(await tge.batchRoots(expectedKey)).to.equal(ROOT_A);
    });
  });

  describe("getReconciliation", function () {
    it("returns zero drift after a clean V2-only welcome bonus", async function () {
      await tge.connect(oracle).distributeWelcomeBonus(
        user1.address, 1000n * ONE,
        [BURN, founders.address], [100n * ONE, 100n * ONE], ROOT_A
      );
      const [expected, actual, drift] = await tge.getReconciliation();
      expect(drift).to.equal(0n);
      expect(expected).to.equal(actual);
    });
  });

  describe("executeTGE V2 — Merkle commitment", function () {
    it("requires a non-zero merkle root", async function () {
      await expect(
        tge.connect(oracle).executeTGE(
          [user1.address], [1n * ONE], [100], ZERO_ROOT
        )
      ).to.be.revertedWith("TGE: missing merkle root");
    });

    it("stores merkle root per (epoch, tgeEvent)", async function () {
      await tge.connect(oracle).executeTGE(
        [user1.address], [1n * ONE], [100], ROOT_A
      );
      const key = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["string", "uint256", "uint256"],
          ["TGE", 1, 0]
        )
      );
      expect(await tge.batchRoots(key)).to.equal(ROOT_A);
    });

    it("rejects efficiency > 100", async function () {
      await expect(
        tge.connect(oracle).executeTGE(
          [user1.address], [1n * ONE], [101], ROOT_A
        )
      ).to.be.revertedWith("TGE: efficiency > 100");
    });
  });
  describe("Individual Pull-Claim & Genesis Distribution (V3)", function () {
    function makeLeaf(recipient, epoch, tgeEvent, earnedAmount, efficiency) {
      return ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256", "uint256", "uint256", "uint8"],
          [recipient, epoch, tgeEvent, earnedAmount, efficiency]
        )
      );
    }

    it("allows oracle to publish TDE root and users to pull-claim anytime", async function () {
      const epoch = 1;
      const tgeEvent = 0;
      const earnedUser1 = 1000n * ONE;
      const efficiencyUser1 = 100; // 100% liquid
      const earnedUser2 = 2000n * ONE;
      const efficiencyUser2 = 50;  // 50% liquid, 50% burn (score below 91)

      const leaf1 = makeLeaf(user1.address, epoch, tgeEvent, earnedUser1, efficiencyUser1);
      const leaf2 = makeLeaf(user2.address, epoch, tgeEvent, earnedUser2, efficiencyUser2);

      const tree = new MerkleTree([leaf1, leaf2], ethers.keccak256, { sortPairs: true });
      const root = tree.getHexRoot();
      const proof1 = tree.getHexProof(leaf1);
      const proof2 = tree.getHexProof(leaf2);

      // Oracle publishes root
      await tge.connect(oracle).publishTdeRoot(epoch, tgeEvent, root, earnedUser1 + earnedUser2);

      // User 1 claims anytime (100% efficiency)
      const u1BalBefore = await token.balanceOf(user1.address);
      await tge.connect(user1).claimTdeTokens(user1.address, epoch, tgeEvent, earnedUser1, efficiencyUser1, proof1);
      const u1BalAfter = await token.balanceOf(user1.address);
      expect(u1BalAfter - u1BalBefore).to.equal(earnedUser1);

      // User 2 claims (50% efficiency: score below 91 does not freeze claim, 50% liquid and 50% burned)
      const u2BalBefore = await token.balanceOf(user2.address);
      const deadBalBefore = await token.balanceOf(BURN);
      await tge.connect(user2).claimTdeTokens(user2.address, epoch, tgeEvent, earnedUser2, efficiencyUser2, proof2);
      const u2BalAfter = await token.balanceOf(user2.address);
      const deadBalAfter = await token.balanceOf(BURN);

      expect(u2BalAfter - u2BalBefore).to.equal(1000n * ONE); // 50% of 2000
      expect(deadBalAfter - deadBalBefore).to.equal(0n); // TDE 1-9 carries over unconverted balance (0 burned until TDE 10 Great Reset)

      // At TDE 10 (tgeEvent = 9, The Great Reset), unconverted balance is burned to 0x...dEaD
      const resetEvent = 9;
      const leafReset = makeLeaf(user2.address, epoch, resetEvent, earnedUser2, efficiencyUser2);
      const treeReset = new MerkleTree([leafReset], ethers.keccak256, { sortPairs: true });
      const rootReset = treeReset.getHexRoot();
      const proofReset = treeReset.getHexProof(leafReset);
      await tge.connect(oracle).publishTdeRoot(epoch, resetEvent, rootReset, earnedUser2);
      await tge.connect(user2).claimTdeTokens(user2.address, epoch, resetEvent, earnedUser2, efficiencyUser2, proofReset);
      const deadBalAfterReset = await token.balanceOf(BURN);
      expect(deadBalAfterReset - deadBalAfter).to.equal(1000n * ONE);

      // Verify executeTGE carry-over (TDE 1-9) + Great Reset burn (TDE 10)
      await tge.connect(oracle).mintEpochSupply(1_000_000n * ONE);
      // TDE 1 (event 0): 50,000 DSP @ 50% PCT -> 25,000 liquid, 0 burned (25,000 carried over)
      const u1Start = await token.balanceOf(user1.address);
      const burnStart = await token.balanceOf(BURN);
      await tge.connect(oracle).executeTGE([user1.address], [50_000n * ONE], [50], ROOT_A);
      expect((await token.balanceOf(user1.address)) - u1Start).to.equal(25_000n * ONE);
      expect((await token.balanceOf(BURN)) - burnStart).to.equal(0n);

      // TDE 2 (event 1): 25,000 carried over + 35,000 new = 60,000 DSP @ 70% PCT -> 42,000 liquid, 0 burned (18,000 carried over)
      await tge.connect(oracle).executeTGE([user1.address], [60_000n * ONE], [70], ROOT_A);
      expect((await token.balanceOf(user1.address)) - u1Start).to.equal(67_000n * ONE);
      expect((await token.balanceOf(BURN)) - burnStart).to.equal(0n);
    });

    it("prevents double-claiming TDE tokens", async function () {
      const epoch = 1;
      const tgeEvent = 0;
      const earned = 500n * ONE;
      const efficiency = 80;

      const leaf = makeLeaf(user1.address, epoch, tgeEvent, earned, efficiency);
      const tree = new MerkleTree([leaf], ethers.keccak256, { sortPairs: true });
      const root = tree.getHexRoot();
      const proof = tree.getHexProof(leaf);

      await tge.connect(oracle).publishTdeRoot(epoch, tgeEvent, root, earned);
      await tge.claimTdeTokens(user1.address, epoch, tgeEvent, earned, efficiency, proof);

      await expect(
        tge.claimTdeTokens(user1.address, epoch, tgeEvent, earned, efficiency, proof)
      ).to.be.revertedWith("TGE: already claimed");
    });

    it("prevents pull-claiming after executeTGE has already pushed distribution", async function () {
      const epoch = 1;
      const tgeEvent = 0;
      const earned = 500n * ONE;
      const efficiency = 80;

      const leaf = makeLeaf(user1.address, epoch, tgeEvent, earned, efficiency);
      const tree = new MerkleTree([leaf], ethers.keccak256, { sortPairs: true });
      const root = tree.getHexRoot();
      const proof = tree.getHexProof(leaf);

      await tge.connect(oracle).executeTGE(
        [user1.address],
        [earned],
        [efficiency],
        root
      );

      await expect(
        tge.claimTdeTokens(user1.address, epoch, tgeEvent, earned, efficiency, proof)
      ).to.be.revertedWith("TGE: already claimed");
    });

    it("rejects invalid Merkle proof on TDE claim", async function () {
      const epoch = 1;
      const tgeEvent = 0;
      const earned = 500n * ONE;
      const efficiency = 80;

      const leaf = makeLeaf(user1.address, epoch, tgeEvent, earned, efficiency);
      const tree = new MerkleTree([leaf], ethers.keccak256, { sortPairs: true });
      const root = tree.getHexRoot();

      await tge.connect(oracle).publishTdeRoot(epoch, tgeEvent, root, earned);

      const fakeProof = [ROOT_A];
      await expect(
        tge.claimTdeTokens(user1.address, epoch, tgeEvent, earned, efficiency, fakeProof)
      ).to.be.revertedWith("TGE: invalid merkle proof");
    });

    it("distributes Genesis 7,000 $DIASPORA tokens on 6-milestone completion", async function () {
      const genesisAmount = 7000n * ONE;
      await tge.connect(admin).setMaxGenesisDistribution(genesisAmount);

      const userBalBefore = await token.balanceOf(user1.address);
      await tge.connect(oracle).distributeGenesisTokens(
        user1.address,
        genesisAmount,
        [founders.address, BURN],
        [700n * ONE, 700n * ONE],
        ROOT_A
      );

      const userBalAfter = await token.balanceOf(user1.address);
      expect(userBalAfter - userBalBefore).to.equal(genesisAmount);

      // Dedupe check
      await expect(
        tge.connect(oracle).distributeGenesisTokens(
          user1.address,
          genesisAmount,
          [],
          [],
          ROOT_A
        )
      ).to.be.revertedWith("TGE: user already received genesis distribution");
    });
  });
});
