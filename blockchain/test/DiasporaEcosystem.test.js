import { expect } from "chai";
import hre from "hardhat";
import { upgrades as createUpgrades } from "@openzeppelin/hardhat-upgrades";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;
const upgrades = await createUpgrades(hre, connection);

describe("Diaspora Ecosystem: Pre-Minted Epoch TGE", function () {
    let token, tgeController;
    let admin, upgrader, oracle, user1, user2, founder, investor;

    const DECIMALS = 18;
    const EPOCH_1_SUPPLY = ethers.parseUnits("1000000", DECIMALS); // 1M

    beforeEach(async function () {
        [admin, upgrader, oracle, user1, user2, founder, investor] = await ethers.getSigners();

        // Deploy DiasporaToken via UUPS proxy
        const DiasporaToken = await ethers.getContractFactory("DiasporaToken");
        token = await upgrades.deployProxy(
            DiasporaToken,
            [admin.address, admin.address, upgrader.address],
            { kind: "uups" }
        );
        await token.waitForDeployment();
        const tokenAddress = await token.getAddress();

        // Deploy TGEController via UUPS proxy
        const DiasporaTGEController = await ethers.getContractFactory("DiasporaTGEController");
        tgeController = await upgrades.deployProxy(
            DiasporaTGEController,
            [admin.address, upgrader.address, tokenAddress],
            { kind: "uups" }
        );
        await tgeController.waitForDeployment();
        const tgeAddress = await tgeController.getAddress();

        // Grant MINTER_ROLE to TGEController (so it can pre-mint)
        const MINTER_ROLE = await token.MINTER_ROLE();
        await token.connect(admin).grantRole(MINTER_ROLE, tgeAddress);

        // Grant TGE_ORACLE_ROLE to oracle signer
        const TGE_ORACLE_ROLE = await tgeController.TGE_ORACLE_ROLE();
        await tgeController.connect(admin).grantRole(TGE_ORACLE_ROLE, oracle.address);
    });

    describe("Initial State", function () {
        it("Should start at Epoch 1, TDE 0, zero supply", async function () {
            const stats = await tgeController.getStats();
            expect(stats[0]).to.equal(1); // epoch
            expect(stats[1]).to.equal(0); // tgeEvent
            expect(stats[2]).to.equal(0); // totalMinted
            expect(stats[3]).to.equal(0); // totalDistributed
            expect(stats[4]).to.equal(0); // totalBurned

            expect(await token.totalSupply()).to.equal(0);
        });
    });

    describe("mintEpochSupply()", function () {
        it("Should mint tokens to the TGEController", async function () {
            await tgeController.connect(oracle).mintEpochSupply(EPOCH_1_SUPPLY);

            const controllerAddr = await tgeController.getAddress();
            const balance = await token.balanceOf(controllerAddr);
            expect(balance).to.equal(EPOCH_1_SUPPLY);
            expect(await token.totalSupply()).to.equal(EPOCH_1_SUPPLY);
        });

        it("Should track epochLockedSupply", async function () {
            await tgeController.connect(oracle).mintEpochSupply(EPOCH_1_SUPPLY);
            expect(await tgeController.epochLockedSupply()).to.equal(EPOCH_1_SUPPLY);
            expect(await tgeController.totalMinted()).to.equal(EPOCH_1_SUPPLY);
        });

        it("Should update getLockedBalance()", async function () {
            await tgeController.connect(oracle).mintEpochSupply(EPOCH_1_SUPPLY);
            expect(await tgeController.getLockedBalance()).to.equal(EPOCH_1_SUPPLY);
        });

        it("Should allow incremental minting", async function () {
            const half = EPOCH_1_SUPPLY / 2n;
            await tgeController.connect(oracle).mintEpochSupply(half);
            await tgeController.connect(oracle).mintEpochSupply(half);

            expect(await tgeController.epochLockedSupply()).to.equal(EPOCH_1_SUPPLY);
            expect(await tgeController.getLockedBalance()).to.equal(EPOCH_1_SUPPLY);
        });

        it("Should revert on zero amount", async function () {
            await expect(
                tgeController.connect(oracle).mintEpochSupply(0)
            ).to.be.revertedWith("TGE: zero amount");
        });

        it("Should revert for non-oracle callers", async function () {
            await expect(
                tgeController.connect(user1).mintEpochSupply(EPOCH_1_SUPPLY)
            ).to.revert(ethers);
        });
    });

    describe("executeTGE() — Distribute from Pre-Minted Supply", function () {
        beforeEach(async function () {
            // Pre-mint Epoch 1 supply
            await tgeController.connect(oracle).mintEpochSupply(EPOCH_1_SUPPLY);
        });

        it("Should distribute by efficiency (100%)", async function () {
            const amount = ethers.parseUnits("1000", DECIMALS);
            await tgeController.connect(oracle).executeTGE(
                [user1.address],
                [amount],
                [100]
            );

            expect(await token.balanceOf(user1.address)).to.equal(amount);
        });

        it("Should distribute by efficiency (70%) — burn 30%", async function () {
            const amount = ethers.parseUnits("1000", DECIMALS);
            await tgeController.connect(oracle).executeTGE(
                [user1.address],
                [amount],
                [70]
            );

            const liquid = ethers.parseUnits("700", DECIMALS);
            const burned = ethers.parseUnits("300", DECIMALS);

            expect(await token.balanceOf(user1.address)).to.equal(liquid);

            const BURN_ADDRESS = "0x000000000000000000000000000000000000dEaD";
            expect(await token.balanceOf(BURN_ADDRESS)).to.equal(burned);
        });

        it("Should handle multi-recipient batch", async function () {
            const amounts = [
                ethers.parseUnits("500", DECIMALS),
                ethers.parseUnits("300", DECIMALS),
                ethers.parseUnits("200", DECIMALS),
            ];
            const efficiencies = [90, 100, 50];

            await tgeController.connect(oracle).executeTGE(
                [user1.address, founder.address, user2.address],
                amounts,
                efficiencies
            );

            // user1: 500 * 90% = 450
            expect(await token.balanceOf(user1.address)).to.equal(ethers.parseUnits("450", DECIMALS));
            // founder: 300 * 100% = 300
            expect(await token.balanceOf(founder.address)).to.equal(ethers.parseUnits("300", DECIMALS));
            // user2: 200 * 50% = 100
            expect(await token.balanceOf(user2.address)).to.equal(ethers.parseUnits("100", DECIMALS));

            // Burns: 50 + 0 + 100 = 150
            const BURN_ADDRESS = "0x000000000000000000000000000000000000dEaD";
            expect(await token.balanceOf(BURN_ADDRESS)).to.equal(ethers.parseUnits("150", DECIMALS));
        });

        it("Should update stats correctly after TGE", async function () {
            const amount = ethers.parseUnits("10000", DECIMALS);
            await tgeController.connect(oracle).executeTGE(
                [user1.address],
                [amount],
                [80]
            );

            const stats = await tgeController.getStats();
            expect(stats[0]).to.equal(1);     // still epoch 1
            expect(stats[1]).to.equal(1);     // advanced to TDE 1
            expect(stats[3]).to.equal(ethers.parseUnits("8000", DECIMALS));  // distributed
            expect(stats[4]).to.equal(ethers.parseUnits("2000", DECIMALS));  // burned
            expect(stats[5]).to.equal(1);     // tgeCount
        });

        it("Should reduce controller balance after distribution", async function () {
            const amount = ethers.parseUnits("100000", DECIMALS);
            await tgeController.connect(oracle).executeTGE(
                [user1.address],
                [amount],
                [100]
            );

            const remaining = EPOCH_1_SUPPLY - amount;
            expect(await tgeController.getLockedBalance()).to.equal(remaining);
        });

        it("Should REVERT when controller has insufficient supply", async function () {
            // Try to distribute more than the locked supply
            const tooMuch = EPOCH_1_SUPPLY + 1n;
            await expect(
                tgeController.connect(oracle).executeTGE(
                    [user1.address],
                    [tooMuch],
                    [100]
                )
            ).to.be.revertedWith("TGE: insufficient locked supply");
        });

        it("Should revert on empty batch", async function () {
            await expect(
                tgeController.connect(oracle).executeTGE([], [], [])
            ).to.be.revertedWith("TGE: empty batch");
        });

        it("Should revert on array length mismatch", async function () {
            await expect(
                tgeController.connect(oracle).executeTGE(
                    [user1.address, user2.address],
                    [ethers.parseUnits("100", DECIMALS)],
                    [100]
                )
            ).to.be.revertedWith("TGE: array length mismatch");
        });

        it("Should revert for non-oracle callers", async function () {
            await expect(
                tgeController.connect(user1).executeTGE(
                    [user1.address],
                    [ethers.parseUnits("100", DECIMALS)],
                    [100]
                )
            ).to.revert(ethers);
        });
    });

    describe("Epoch Advancement", function () {
        beforeEach(async function () {
            await tgeController.connect(oracle).mintEpochSupply(EPOCH_1_SUPPLY);
        });

        it("Should advance epoch after 10 TDE releases", async function () {
            const perTGE = ethers.parseUnits("100000", DECIMALS); // 100K per TDE (1M / 10)

            // Execute 10 TDE releases (10% of epoch each)
            for (let i = 0; i < 10; i++) {
                await tgeController.connect(oracle).executeTGE(
                    [user1.address],
                    [perTGE],
                    [100]
                );
            }

            const stats = await tgeController.getStats();
            expect(stats[0]).to.equal(2);     // Epoch advanced to 2
            expect(stats[1]).to.equal(0);     // TDE counter reset to 0
            expect(stats[5]).to.equal(10);    // 10 TDE releases executed

            // Epoch tracking should be reset
            expect(await tgeController.epochLockedSupply()).to.equal(0);
            expect(await tgeController.epochDistributed()).to.equal(0);

            // Controller should have 0 balance (all 1M distributed at 100%)
            expect(await tgeController.getLockedBalance()).to.equal(0);
        });

        it("Should handle mixed efficiencies across epoch", async function () {
            const perTGE = ethers.parseUnits("100000", DECIMALS);

            // 5 events at 100% efficiency, 5 at 80%
            for (let i = 0; i < 5; i++) {
                await tgeController.connect(oracle).executeTGE(
                    [user1.address],
                    [perTGE],
                    [100]
                );
            }
            for (let i = 0; i < 5; i++) {
                await tgeController.connect(oracle).executeTGE(
                    [user2.address],
                    [perTGE],
                    [80]
                );
            }

            const stats = await tgeController.getStats();
            expect(stats[0]).to.equal(2); // Epoch advanced

            // user1: 5 * 100K = 500K
            expect(await token.balanceOf(user1.address)).to.equal(ethers.parseUnits("500000", DECIMALS));
            // user2: 5 * 80K = 400K
            expect(await token.balanceOf(user2.address)).to.equal(ethers.parseUnits("400000", DECIMALS));
            // Burned: 5 * 20K = 100K
            const BURN_ADDRESS = "0x000000000000000000000000000000000000dEaD";
            expect(await token.balanceOf(BURN_ADDRESS)).to.equal(ethers.parseUnits("100000", DECIMALS));
        });
    });
});
