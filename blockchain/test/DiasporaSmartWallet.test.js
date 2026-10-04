import { expect } from "chai";
import hre from "hardhat";
import { upgrades as createUpgrades } from "@openzeppelin/hardhat-upgrades";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;
const upgrades = await createUpgrades(hre, connection);

describe("DiasporaSmartWallet & WalletFactory", function () {
    let factory, token;
    let admin, backendSigner, user1, user2;

    // Helper to create phone hash
    function phoneHash(phoneNumber) {
        return ethers.keccak256(ethers.toUtf8Bytes(phoneNumber));
    }

    beforeEach(async function () {
        [admin, backendSigner, user1, user2] = await ethers.getSigners();

        // Deploy Token via UUPS proxy (required by _disableInitializers)
        const DiasporaToken = await ethers.getContractFactory("DiasporaToken");
        token = await upgrades.deployProxy(
            DiasporaToken,
            [admin.address, admin.address, admin.address],
            { kind: "uups" }
        );
        await token.waitForDeployment();

        // Deploy WalletFactory
        const DiasporaWalletFactory = await ethers.getContractFactory("DiasporaWalletFactory");
        factory = await DiasporaWalletFactory.deploy(admin.address, backendSigner.address);
    });

    describe("Wallet Factory", function () {
        it("should compute deterministic addresses", async function () {
            const hash = phoneHash("+14155551234");
            const addr1 = await factory.computeAddress(hash);
            const addr2 = await factory.computeAddress(hash);

            // Same phone number should always give same address
            expect(addr1).to.equal(addr2);
            expect(addr1).to.not.equal(ethers.ZeroAddress);
        });

        it("should create a wallet from phone hash", async function () {
            const hash = phoneHash("+14155551234");
            const predictedAddr = await factory.computeAddress(hash);

            await expect(factory.connect(backendSigner).createWallet(hash))
                .to.emit(factory, "WalletCreated")
                .withArgs(hash, predictedAddr, 1);

            // The deployed wallet address should match the predicted one
            const walletAddr = await factory.getWallet(hash);
            expect(walletAddr).to.equal(predictedAddr);

            // Total wallets should be 1
            expect(await factory.totalWallets()).to.equal(1);
        });

        it("should return existing wallet if already created", async function () {
            const hash = phoneHash("+14155551234");

            await factory.connect(backendSigner).createWallet(hash);
            const firstAddr = await factory.getWallet(hash);

            // Creating again should return the same address (idempotent)
            await factory.connect(backendSigner).createWallet(hash);
            const secondAddr = await factory.getWallet(hash);

            expect(firstAddr).to.equal(secondAddr);
            // Total should still be 1 (not duplicated)
            expect(await factory.totalWallets()).to.equal(1);
        });

        it("should give different addresses for different phone numbers", async function () {
            const hash1 = phoneHash("+14155551234");
            const hash2 = phoneHash("+447911123456");

            const addr1 = await factory.computeAddress(hash1);
            const addr2 = await factory.computeAddress(hash2);

            expect(addr1).to.not.equal(addr2);
        });

        it("should only allow DEPLOYER_ROLE to create wallets", async function () {
            const hash = phoneHash("+14155551234");

            // user1 doesn't have DEPLOYER_ROLE
            await expect(
                factory.connect(user1).createWallet(hash)
            ).to.revert(ethers);
        });
    });

    describe("Smart Wallet Operations", function () {
        let wallet, walletAddr;

        beforeEach(async function () {
            const hash = phoneHash("+14155551234");
            await factory.connect(backendSigner).createWallet(hash);
            walletAddr = await factory.getWallet(hash);
            wallet = await ethers.getContractAt("DiasporaSmartWallet", walletAddr);
        });

        it("should have correct owner and factory", async function () {
            expect(await wallet.owner()).to.equal(backendSigner.address);
            expect(await wallet.factory()).to.equal(await factory.getAddress());
        });

        it("should transfer ERC-20 tokens via wallet", async function () {
            // Mint tokens to the smart wallet
            const amount = ethers.parseEther("1000");
            await token.connect(admin).mint(walletAddr, amount);

            expect(await token.balanceOf(walletAddr)).to.equal(amount);

            // Transfer tokens from smart wallet to user2
            const transferAmount = ethers.parseEther("100");
            await wallet.connect(backendSigner).transferToken(
                await token.getAddress(),
                user2.address,
                transferAmount
            );

            expect(await token.balanceOf(user2.address)).to.equal(transferAmount);
            expect(await token.balanceOf(walletAddr)).to.equal(amount - transferAmount);
        });

        it("should execute arbitrary calls via owner", async function () {
            // Mint some tokens to wallet
            const amount = ethers.parseEther("500");
            await token.connect(admin).mint(walletAddr, amount);

            // Use execute() to call token.transfer
            const tokenIface = new ethers.Interface([
                "function transfer(address to, uint256 amount) returns (bool)"
            ]);
            const data = tokenIface.encodeFunctionData("transfer", [
                user2.address,
                ethers.parseEther("50")
            ]);

            await wallet.connect(backendSigner).execute(
                await token.getAddress(),
                0,
                data
            );

            expect(await token.balanceOf(user2.address)).to.equal(ethers.parseEther("50"));
        });

        it("should prevent non-owner from executing", async function () {
            await expect(
                wallet.connect(user1).execute(ethers.ZeroAddress, 0, "0x")
            ).to.be.revertedWith("DSW: unauthorized");
        });

        it("should prevent re-initialization", async function () {
            await expect(
                wallet.initialize(user1.address)
            ).to.be.revertedWith("DSW: already initialized");
        });
    });

    describe("Wallet Migration", function () {
        it("should migrate wallet to new phone number", async function () {
            const oldHash = phoneHash("+14155551234");
            const newHash = phoneHash("+447911999999");

            await factory.connect(backendSigner).createWallet(oldHash);
            const walletAddr = await factory.getWallet(oldHash);

            // Migrate
            await factory.connect(admin).migrateWallet(oldHash, newHash);

            // Old hash should return zero
            expect(await factory.getWallet(oldHash)).to.equal(ethers.ZeroAddress);
            // New hash should return the wallet  
            expect(await factory.getWallet(newHash)).to.equal(walletAddr);
        });

        it("should prevent migration to occupied phone hash", async function () {
            const hash1 = phoneHash("+14155551234");
            const hash2 = phoneHash("+447911123456");

            await factory.connect(backendSigner).createWallet(hash1);
            await factory.connect(backendSigner).createWallet(hash2);

            await expect(
                factory.connect(admin).migrateWallet(hash1, hash2)
            ).to.be.revertedWith("DWF: new phone already has wallet");
        });
    });

    describe("Backend Signer Rotation", function () {
        it("should update backend signer", async function () {
            const oldHash = phoneHash("+447700900123");
            await factory.connect(backendSigner).createWallet(oldHash);
            const oldWalletAddress = await factory.getWallet(oldHash);
            const oldWallet = await ethers.getContractAt("DiasporaSmartWallet", oldWalletAddress);

            await factory.connect(admin).updateBackendSigner(user1.address);
            expect(await factory.backendSigner()).to.equal(user1.address);

            // New signer should be able to create wallets
            const hash = phoneHash("+14155551234");
            await factory.connect(user1).createWallet(hash);
            expect(await factory.walletExists(hash)).to.equal(true);

            // Existing wallets are rotated explicitly in bounded batches.
            expect(await oldWallet.owner()).to.equal(backendSigner.address);
            await factory.connect(admin).rotateWalletOwner(oldWalletAddress, user1.address);
            expect(await oldWallet.owner()).to.equal(user1.address);
            await expect(
                oldWallet.connect(backendSigner).transferToken(
                    ethers.ZeroAddress,
                    admin.address,
                    1,
                )
            ).to.be.revertedWith("DSW: unauthorized");
        });

        it("rejects rotation of an unknown wallet", async function () {
            await expect(
                factory.connect(admin).rotateWalletOwner(user2.address, user1.address)
            ).to.be.revertedWith("DWF: unknown wallet");
        });
    });
});
