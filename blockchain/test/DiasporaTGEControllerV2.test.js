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
});
