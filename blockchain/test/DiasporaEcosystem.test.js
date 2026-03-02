const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("Diaspora Ecosystem Integration", function () {
    let token, registry, tgeController, allocationHub, engine;
    let owner, admin, upgrader, oracle, user, founder, investor;

    beforeEach(async function () {
        [owner, admin, upgrader, oracle, user, founder, investor] = await ethers.getSigners();

        // 1. Deploy Token
        const DiasporaToken = await ethers.getContractFactory("DiasporaToken");
        token = await upgrades.deployProxy(DiasporaToken, [admin.address, owner.address, upgrader.address], { kind: "uups" });
        await token.waitForDeployment();
        const tokenAddress = await token.getAddress();

        // 2. Deploy Registry
        const DiasporaRegistry = await ethers.getContractFactory("DiasporaRegistry");
        registry = await upgrades.deployProxy(DiasporaRegistry, [admin.address, upgrader.address], { kind: "uups" });
        await registry.waitForDeployment();
        const registryAddress = await registry.getAddress();

        // 3. Deploy TGE Controller
        const DiasporaTGEController = await ethers.getContractFactory("DiasporaTGEController");
        tgeController = await upgrades.deployProxy(DiasporaTGEController, [admin.address, upgrader.address, tokenAddress], { kind: "uups" });
        await tgeController.waitForDeployment();
        const tgeAddress = await tgeController.getAddress();

        // 4. Deploy Allocation Hub
        const DiasporaAllocationHub = await ethers.getContractFactory("DiasporaAllocationHub");
        allocationHub = await upgrades.deployProxy(DiasporaAllocationHub, [
            admin.address,
            upgrader.address,
            tokenAddress,
            registryAddress,
            tgeAddress,
            founder.address,
            investor.address
        ], { kind: "uups" });
        await allocationHub.waitForDeployment();
        const hubAddress = await allocationHub.getAddress();

        // 5. Deploy Expansion Engine
        const DiasporaExpansionEngine = await ethers.getContractFactory("DiasporaExpansionEngine");
        engine = await upgrades.deployProxy(DiasporaExpansionEngine, [
            admin.address,
            upgrader.address,
            tgeAddress,
            hubAddress
        ], { kind: "uups" });
        await engine.waitForDeployment();
        const engineAddress = await engine.getAddress();

        // --- Wiring ---
        const MINTER_ROLE = await token.MINTER_ROLE();
        const ENGINE_ROLE = await tgeController.ENGINE_ROLE();
        const TGE_ORACLE_ROLE = await tgeController.TGE_ORACLE_ROLE();
        const DISTRIBUTOR_ROLE = await allocationHub.DISTRIBUTOR_ROLE();
        const REPORTER_ROLE = await engine.REPORTER_ROLE();
        const DEFAULT_ADMIN_ROLE = await token.DEFAULT_ADMIN_ROLE();

        console.log("Admin address:", admin.address);
        console.log("Token Admin Role check:", await token.hasRole(DEFAULT_ADMIN_ROLE, admin.address));

        await token.connect(admin).grantRole(MINTER_ROLE, tgeAddress);
        await token.connect(admin).grantRole(MINTER_ROLE, hubAddress);
        await tgeController.connect(admin).grantRole(ENGINE_ROLE, hubAddress);
        await tgeController.connect(admin).grantRole(ENGINE_ROLE, engineAddress);
        await tgeController.connect(admin).grantRole(TGE_ORACLE_ROLE, oracle.address);
        await allocationHub.connect(admin).grantRole(DISTRIBUTOR_ROLE, engineAddress);
        await engine.connect(admin).grantRole(REPORTER_ROLE, oracle.address);

        console.log("Wiring complete.");
    });

    describe("1:1 Expansion Rule", function () {
        it("Should stage rewards correctly for user and treasuries", async function () {
            const rewardAmount = ethers.parseEther("100"); // 100 DSP
            const initialSupply = await token.totalSupply();

            // Record activity via Oracle
            await engine.connect(oracle).recordActivity(user.address, rewardAmount);

            // Verify User Staging
            expect(await tgeController.stagedUserRewards(user.address)).to.equal(rewardAmount);

            // Verify System Staging (Founders/Investors get 10% each of the match)
            expect(await tgeController.stagedSystemRewards(founder.address)).to.equal(ethers.parseEther("10"));
            expect(await tgeController.stagedSystemRewards(investor.address)).to.equal(ethers.parseEther("10"));

            // Verify Total Supply Increase (User 100 + Match 100 = 200)
            expect(await token.totalSupply()).to.equal(initialSupply + ethers.parseEther("200"));

            // Verify TGE Controller Balance (Staged User 100 + Founder 10 + Investor 10 = 120)
            // (The other 80 are burned: 70 unassigned community slots + 10 fixed burn slot)
            expect(await token.balanceOf(await tgeController.getAddress())).to.equal(ethers.parseEther("120"));
        });
    });

    describe("TGE Filtering (PoCT)", function () {
        it("Should release liquid tokens based on PoCT and burn the rest", async function () {
            const rewardAmount = ethers.parseEther("100");
            await engine.connect(oracle).recordActivity(user.address, rewardAmount);

            // Execute TGE with 70% PoCT for user
            // Efficiency 70 means 70% liquid, 30% burned
            const recipients = [user.address, founder.address, investor.address];
            const efficiencies = [70, 100, 100]; // System always 100

            const initialUserBalance = await token.balanceOf(user.address);

            await tgeController.connect(oracle).executeTGE(recipients, efficiencies);

            // Verify User got 70 DSP
            expect(await token.balanceOf(user.address)).to.equal(initialUserBalance + ethers.parseEther("70"));

            // Verify Founder got 10 DSP (100% of 10 staged)
            expect(await token.balanceOf(founder.address)).to.equal(ethers.parseEther("10"));

            // Verify Staged Balances are cleared
            expect(await tgeController.stagedUserRewards(user.address)).to.equal(0);

            // Verify Burn (30 DSP from user + 0 from system)
            // Note: The rest of the 50/50 match (80 DSP) is still staged for communities if they aren't in recipients list.
        });
    });
});
