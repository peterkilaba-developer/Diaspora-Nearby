const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("DiasporaToken", function () {
    let DiasporaToken;
    let token;
    let owner;
    let minter;
    let addr1;
    let addr2;

    beforeEach(async function () {
        [owner, minter, addr1, addr2] = await ethers.getSigners();
        DiasporaToken = await ethers.getContractFactory("DiasporaToken");
        token = await DiasporaToken.deploy(owner.address, minter.address);
    });

    describe("Deployment", function () {
        it("Should set the right name and symbol", async function () {
            expect(await token.name()).to.equal("Diaspora");
            expect(await token.symbol()).to.equal("DSP");
        });

        it("Should set the admin and minter roles", async function () {
            const DEFAULT_ADMIN_ROLE = await token.DEFAULT_ADMIN_ROLE();
            const MINTER_ROLE = await token.MINTER_ROLE();
            expect(await token.hasRole(DEFAULT_ADMIN_ROLE, owner.address)).to.equal(true);
            expect(await token.hasRole(MINTER_ROLE, minter.address)).to.equal(true);
        });
    });

    describe("Minting", function () {
        it("Should allow the minter to mint within the cap", async function () {
            const amount = ethers.parseEther("1000");
            await token.connect(minter).mint(addr1.address, amount);
            expect(await token.balanceOf(addr1.address)).to.equal(amount);
        });

        it("Should fail if a non-minter tries to mint", async function () {
            const amount = ethers.parseEther("1000");
            await expect(token.connect(addr1).mint(addr1.address, amount))
                .to.be.revertedWithCustomError(token, "AccessControlUnauthorizedAccount");
        });

        it("Should not allow minting beyond the 1 Trillion cap", async function () {
            const HARD_CAP = await token.HARD_CAP();
            // Try to mint capped + 1
            await expect(token.connect(minter).mint(addr1.address, HARD_CAP + 1n))
                .to.be.revertedWith("DiasporaToken: hard cap exceeded");
        });
    });

    describe("Burning", function () {
        it("Should allow anyone to burn their own tokens", async function () {
            const amount = ethers.parseEther("1000");
            await token.connect(minter).mint(addr1.address, amount);
            await token.connect(addr1).burn(amount);
            expect(await token.balanceOf(addr1.address)).to.equal(0);
        });
    });
});
