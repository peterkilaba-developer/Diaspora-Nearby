import { expect } from "chai";
import hre from "hardhat";
import { upgrades as createUpgrades } from "@openzeppelin/hardhat-upgrades";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;
const upgrades = await createUpgrades(hre, connection);

describe("DiasporaToken Proxy", function () {
    let DiasporaToken;
    let token;
    let owner;
    let minter;
    let upgrader;
    let addr1;

    beforeEach(async function () {
        [owner, minter, upgrader, addr1] = await ethers.getSigners();
        DiasporaToken = await ethers.getContractFactory("DiasporaToken");
        // Deploy as UUPS Proxy
        token = await upgrades.deployProxy(DiasporaToken, [owner.address, minter.address, upgrader.address], { kind: "uups" });
        await token.waitForDeployment();
    });

    describe("Deployment", function () {
        it("Should set the right name and symbol", async function () {
            expect(await token.name()).to.equal("Diaspora");
            expect(await token.symbol()).to.equal("DIASPORA");
        });

        it("Should set roles correctly", async function () {
            const DEFAULT_ADMIN_ROLE = await token.DEFAULT_ADMIN_ROLE();
            const MINTER_ROLE = await token.MINTER_ROLE();
            const UPGRADER_ROLE = await token.UPGRADER_ROLE();
            expect(await token.hasRole(DEFAULT_ADMIN_ROLE, owner.address)).to.equal(true);
            expect(await token.hasRole(MINTER_ROLE, minter.address)).to.equal(true);
            expect(await token.hasRole(UPGRADER_ROLE, upgrader.address)).to.equal(true);
        });
    });

    describe("Minting & Cap", function () {
        it("Should allow the minter to mint", async function () {
            const amount = ethers.parseEther("1000");
            await token.connect(minter).mint(addr1.address, amount);
            expect(await token.balanceOf(addr1.address)).to.equal(amount);
        });

        it("Should respect the 1 Quadrillion cap", async function () {
            const HARD_CAP = await token.HARD_CAP();
            expect(HARD_CAP).to.equal(1000000000000000n * 10n ** 18n); // 1 Quadrillion

            // Try to mint capped + 1 (using a smaller number for sanity, just testing the check)
            await expect(token.connect(minter).mint(addr1.address, HARD_CAP + 1n))
                .to.be.revertedWith("DiasporaToken: hard cap exceeded");
        });
    });

    describe("Upgradability", function () {
        it("Should allow only the upgrader to upgrade", async function () {
            const DiasporaTokenV2 = await ethers.getContractFactory("DiasporaToken"); // Same logic for test

            // Non-upgrader fails
            await expect(upgrades.upgradeProxy(await token.getAddress(), DiasporaTokenV2.connect(addr1)))
                .to.revert(ethers);

            // Upgrader succeeds
            const upgraded = await upgrades.upgradeProxy(await token.getAddress(), DiasporaTokenV2.connect(upgrader));
            expect(await upgraded.getAddress()).to.equal(await token.getAddress());
        });
    });
});
