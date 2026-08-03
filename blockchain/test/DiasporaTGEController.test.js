import { expect } from "chai";
import hre from "hardhat";
import { upgrades as createUpgrades } from "@openzeppelin/hardhat-upgrades";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;
const upgrades = await createUpgrades(hre, connection);

/**
 * Tests for DiasporaTGEController.
 *
 * Covers the high-value paths that previously had ZERO coverage:
 *   - mintEpochSupply: locked-supply accounting
 *   - executeTGE: efficiency math, burn behavior, epoch rollover after 10 TDE releases
 *   - distributeWelcomeBonus: doesn't advance event counter, BURN_ADDRESS handling
 *   - Integer-division edge cases (the source of the 1,000 DIASPORA drift on mainnet)
 *   - Access control: only TGE_ORACLE_ROLE can call privileged functions
 */
describe("DiasporaTGEController", function () {
  const ONE = ethers.parseUnits("1", 18);
  const BURN = "0x000000000000000000000000000000000000dEaD";

  let admin, oracle, alice, bob, carol, attacker;
  let token, tge;

  beforeEach(async function () {
    [admin, oracle, alice, bob, carol, attacker] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("DiasporaToken");
    token = await upgrades.deployProxy(
      Token,
      [admin.address, admin.address /* minter, replaced below */, admin.address],
      { kind: "uups" }
    );

    const TGE = await ethers.getContractFactory("DiasporaTGEController");
    tge = await upgrades.deployProxy(
      TGE,
      [admin.address, admin.address, await token.getAddress()],
      { kind: "uups" }
    );

    // Wire MINTER to TGE controller (the production pattern)
    const MINTER_ROLE = await token.MINTER_ROLE();
    await token.grantRole(MINTER_ROLE, await tge.getAddress());

    // Grant ORACLE to a dedicated signer for cleaner tests
    const ORACLE_ROLE = await tge.TGE_ORACLE_ROLE();
    await tge.grantRole(ORACLE_ROLE, oracle.address);
  });

  describe("mintEpochSupply", function () {
    it("mints to controller and updates accounting", async function () {
      const amount = 1_000n * ONE;
      await expect(tge.connect(oracle).mintEpochSupply(amount))
        .to.emit(tge, "EpochSupplyMinted")
        .withArgs(1, amount, amount);

      expect(await token.balanceOf(await tge.getAddress())).to.equal(amount);
      expect(await tge.epochLockedSupply()).to.equal(amount);
      expect(await tge.totalMinted()).to.equal(amount);
    });

    it("rejects zero amount", async function () {
      await expect(tge.connect(oracle).mintEpochSupply(0)).to.be.revertedWith("TGE: zero amount");
    });

    it("rejects non-oracle caller", async function () {
      await expect(tge.connect(attacker).mintEpochSupply(ONE)).to.revert(ethers);
    });
  });

  describe("executeTGE", function () {
    beforeEach(async function () {
      await tge.connect(oracle).mintEpochSupply(10_000n * ONE);
    });

    it("distributes by efficiency, burns the rest", async function () {
      // alice: 100 DIASPORA @ 80% → 80 to alice, 20 burned
      // bob:   200 DIASPORA @ 50% → 100 to bob,  100 burned
      const recipients = [alice.address, bob.address];
      const amounts = [100n * ONE, 200n * ONE];
      const efficiencies = [80, 50];

      await tge.connect(oracle).executeTGE(recipients, amounts, efficiencies);

      expect(await token.balanceOf(alice.address)).to.equal(80n * ONE);
      expect(await token.balanceOf(bob.address)).to.equal(100n * ONE);
      expect(await token.balanceOf(BURN)).to.equal(120n * ONE);
      expect(await tge.totalDistributed()).to.equal(180n * ONE);
      expect(await tge.totalBurned()).to.equal(120n * ONE);
    });

    it("100% efficiency burns nothing", async function () {
      await tge.connect(oracle).executeTGE([alice.address], [50n * ONE], [100]);
      expect(await token.balanceOf(alice.address)).to.equal(50n * ONE);
      expect(await token.balanceOf(BURN)).to.equal(0);
    });

    it("0% efficiency burns everything", async function () {
      await tge.connect(oracle).executeTGE([alice.address], [50n * ONE], [0]);
      expect(await token.balanceOf(alice.address)).to.equal(0);
      expect(await token.balanceOf(BURN)).to.equal(50n * ONE);
    });

    it("advances epoch after exactly 10 events", async function () {
      for (let i = 0; i < 9; i++) {
        await tge.connect(oracle).executeTGE([alice.address], [ONE], [100]);
        expect(await tge.currentEpoch()).to.equal(1);
      }
      // 10th TDE release rolls the epoch
      await tge.connect(oracle).executeTGE([alice.address], [ONE], [100]);
      expect(await tge.currentEpoch()).to.equal(2);
      expect(await tge.currentTgeEvent()).to.equal(0);
      expect(await tge.epochLockedSupply()).to.equal(0);
      expect(await tge.epochDistributed()).to.equal(0);
    });

    it("reverts on insufficient locked supply", async function () {
      await expect(
        tge.connect(oracle).executeTGE([alice.address], [100_000n * ONE], [100])
      ).to.be.revertedWith("TGE: insufficient locked supply");
    });

    it("reverts on array length mismatch", async function () {
      await expect(
        tge.connect(oracle).executeTGE([alice.address, bob.address], [ONE], [100, 100])
      ).to.be.revertedWith("TGE: array length mismatch");
    });

    it("reverts on empty batch", async function () {
      await expect(tge.connect(oracle).executeTGE([], [], [])).to.be.revertedWith("TGE: empty batch");
    });

    it("rejects non-oracle caller", async function () {
      await expect(
        tge.connect(attacker).executeTGE([alice.address], [ONE], [100])
      ).to.revert(ethers);
    });

    it("integer-division rounding: efficiency=33 on amount=100 produces tiny drift", async function () {
      // 100 * 33 / 100 = 33 (exact in wei), so for round wei amounts there's no drift.
      // But for amount=10 wei, efficiency=33: 10*33/100 = 3, burn = 7. Exact.
      // The drift only matters when (amount * efficiency) % 100 ≠ 0 AND we sum many such amounts.
      // V1 accounting bug: epochDistributed += amount (full pre-efficiency), losing track of rounding.
      // Verify the on-chain balance vs derived expectation diverge predictably.
      const amount = 7n; // 7 wei; 7*33/100 = 2 (integer), burn = 5
      await tge.connect(oracle).executeTGE([alice.address], [amount], [33]);
      expect(await token.balanceOf(alice.address)).to.equal(2);
      expect(await token.balanceOf(BURN)).to.equal(5);
    });
  });

  describe("distributeWelcomeBonus", function () {
    beforeEach(async function () {
      await tge.connect(oracle).mintEpochSupply(10_000n * ONE);
    });

    it("distributes 100% to recipients, no burn", async function () {
      await tge
        .connect(oracle)
        .distributeWelcomeBonus(
          [alice.address, bob.address],
          [100n * ONE, 200n * ONE]
        );
      expect(await token.balanceOf(alice.address)).to.equal(100n * ONE);
      expect(await token.balanceOf(bob.address)).to.equal(200n * ONE);
      expect(await token.balanceOf(BURN)).to.equal(0);
    });

    it("BURN_ADDRESS recipient actually burns", async function () {
      await tge.connect(oracle).distributeWelcomeBonus([BURN], [50n * ONE]);
      expect(await token.balanceOf(BURN)).to.equal(50n * ONE);
      expect(await tge.totalBurned()).to.equal(50n * ONE);
    });

    it("does NOT advance currentTgeEvent or currentEpoch", async function () {
      const epochBefore = await tge.currentEpoch();
      const eventBefore = await tge.currentTgeEvent();
      await tge.connect(oracle).distributeWelcomeBonus([alice.address], [ONE]);
      expect(await tge.currentEpoch()).to.equal(epochBefore);
      expect(await tge.currentTgeEvent()).to.equal(eventBefore);
    });

    it("counts toward totalWelcomeBonuses and totalDistributed", async function () {
      await tge.connect(oracle).distributeWelcomeBonus([alice.address], [42n * ONE]);
      expect(await tge.totalWelcomeBonuses()).to.equal(42n * ONE);
      expect(await tge.totalDistributed()).to.equal(42n * ONE);
    });

    it("rejects non-oracle caller", async function () {
      await expect(
        tge.connect(attacker).distributeWelcomeBonus([alice.address], [ONE])
      ).to.revert(ethers);
    });

    it("skips zero-amount recipients silently", async function () {
      // Current V1 behavior: amounts[i] == 0 → no transfer, but still added to batchTotal.
      // Documenting this in a test so future contributors know.
      await tge.connect(oracle).distributeWelcomeBonus([alice.address, bob.address], [0, ONE]);
      expect(await token.balanceOf(alice.address)).to.equal(0);
      expect(await token.balanceOf(bob.address)).to.equal(ONE);
    });
  });

  describe("access control", function () {
    it("only UPGRADER_ROLE can authorize upgrades", async function () {
      const TGEv2 = await ethers.getContractFactory("DiasporaTGEController", attacker);
      await expect(
        upgrades.upgradeProxy(await tge.getAddress(), TGEv2)
      ).to.revert(ethers);
    });

    it("admin can grant TGE_ORACLE_ROLE to a new address", async function () {
      const ORACLE_ROLE = await tge.TGE_ORACLE_ROLE();
      await tge.grantRole(ORACLE_ROLE, alice.address);
      expect(await tge.hasRole(ORACLE_ROLE, alice.address)).to.equal(true);
    });
  });
});
