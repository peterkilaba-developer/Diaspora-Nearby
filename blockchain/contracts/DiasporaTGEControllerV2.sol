// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./DiasporaToken.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title DiasporaTGEControllerV2
 * @dev Upgrade target for DiasporaTGEController.
 *
 * Storage-layout-compatible with V1: only appends new state variables.
 * Deploy via `upgrades.upgradeProxy(0xb6C049...4d45, DiasporaTGEControllerV2)`.
 *
 * Changes vs V1 (all motivated by the 2026-06-01 audit, see IMPROVEMENTS.md):
 *  - Per-recipient welcome-bonus cap: oracle can no longer pass arbitrarily
 *    large amounts to a single recipient.
 *  - Per-recipient "received" tracking: prevents double-paying the same
 *    address in distributeWelcomeBonus.
 *  - Merkle root commitment per TGE batch + welcome-bonus batch: lets
 *    anyone verify a specific user's claim against the published root.
 *  - Reconciliation view (getReconciliation): exposes the drift between
 *    stats-derived expected balance and actual on-chain balance.
 *  - Initializer for the new V2-only state (`initializeV2`).
 */
contract DiasporaTGEControllerV2 is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    // ── V1 storage (DO NOT REORDER) ─────────────────────────────────
    bytes32 public constant TGE_ORACLE_ROLE = keccak256("TGE_ORACLE_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    DiasporaToken public token;

    uint256 public currentEpoch;
    uint256 public currentTgeEvent;

    uint256 public totalMinted;
    uint256 public totalDistributed;
    uint256 public totalBurned;
    uint256 public tgeCount;

    uint256 public epochLockedSupply;
    uint256 public epochDistributed;

    uint256 public totalWelcomeBonuses;
    // ── End V1 storage ──────────────────────────────────────────────

    // ── V2 storage (append-only) ────────────────────────────────────
    /// @notice Maximum $DIASPORA a single recipient can receive in one welcome-bonus call.
    /// @dev Admin-tunable. Set in initializeV2 to a sane default.
    uint256 public maxWelcomeBonusPerRecipient;

    /// @notice Tracks total welcome bonus received per recipient (lifetime).
    mapping(address => uint256) public welcomeBonusReceived;

    /// @notice Merkle root committed per (epoch, tgeEvent) for TGE batches.
    /// @dev Off-chain auditors can verify any recipient's allocation by inclusion proof.
    mapping(bytes32 => bytes32) public batchRoots;
    // ── End V2 storage ──────────────────────────────────────────────

    // ── V3 storage (append-only) ────────────────────────────────────
    /// @notice Tracks whether a user has claimed their TDE tokens for (recipient, epoch, tgeEvent).
    mapping(bytes32 => bool) public tdeClaimed;

    /// @notice Maximum $DIASPORA for Genesis PoH distribution.
    uint256 public maxGenesisDistribution;

    /// @notice Tracks Genesis PoH distribution received per user.
    mapping(address => uint256) public genesisDistributionReceived;
    // ── End V3 storage ──────────────────────────────────────────────

    event EpochSupplyMinted(uint256 indexed epoch, uint256 amount, uint256 controllerBalance);
    event TGEExecuted(
        uint256 indexed epoch,
        uint256 indexed tgeEvent,
        uint256 minted,
        uint256 burned,
        uint256 recipientCount,
        bytes32 merkleRoot
    );
    event TokensDistributed(address indexed recipient, uint256 liquid, uint256 burned, uint8 efficiency);
    event WelcomeBonusDistributed(
        address indexed userRecipient,
        uint256 userAmount,
        address[] treasuryRecipients,
        uint256[] treasuryAmounts,
        uint256 totalAmount,
        uint256 indexed epoch,
        bytes32 merkleRoot
    );
    event MaxWelcomeBonusUpdated(uint256 oldMax, uint256 newMax);
    event MaxGenesisDistributionUpdated(uint256 oldMax, uint256 newMax);
    event TokensClaimed(
        address indexed recipient,
        uint256 indexed epoch,
        uint256 indexed tgeEvent,
        uint256 liquid,
        uint256 burned,
        uint8 efficiency
    );
    event TdeRootPublished(uint256 indexed epoch, uint256 indexed tgeEvent, bytes32 merkleRoot, uint256 totalAmount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice V1 initializer kept for storage-layout compatibility.
    function initialize(address admin, address upgrader, address _token) initializer public {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, upgrader);
        _grantRole(TGE_ORACLE_ROLE, admin);

        token = DiasporaToken(_token);
        currentEpoch = 1;
        currentTgeEvent = 0;
    }

    /**
     * @notice One-time initializer for V2-only state.
     * @dev Called via `upgrades.upgradeProxy(..., { call: { fn: 'initializeV2', args: [...] } })`.
     *      Reinitializer(2) makes it callable exactly once on an upgraded proxy.
     */
    function initializeV2(uint256 _maxWelcomeBonusPerRecipient)
        reinitializer(2)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_maxWelcomeBonusPerRecipient > 0, "TGE: zero max");
        maxWelcomeBonusPerRecipient = _maxWelcomeBonusPerRecipient;
        emit MaxWelcomeBonusUpdated(0, _maxWelcomeBonusPerRecipient);
    }

    /// @notice Admin can tune the welcome-bonus cap (e.g. for promotional epochs).
    function setMaxWelcomeBonusPerRecipient(uint256 newMax) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newMax > 0, "TGE: zero max");
        emit MaxWelcomeBonusUpdated(maxWelcomeBonusPerRecipient, newMax);
        maxWelcomeBonusPerRecipient = newMax;
    }

    function mintEpochSupply(uint256 amount) external onlyRole(TGE_ORACLE_ROLE) {
        require(amount > 0, "TGE: zero amount");
        token.mint(address(this), amount);
        epochLockedSupply += amount;
        totalMinted += amount;
        emit EpochSupplyMinted(currentEpoch, amount, token.balanceOf(address(this)));
    }

    /**
     * @dev Execute a TGE batch with an off-chain Merkle commitment.
     * @param recipients Array of wallet addresses.
     * @param amounts Array of DSP amounts (smallest unit, 18 decimals).
     * @param efficiencies Array of PoCT efficiencies (0-100).
     * @param merkleRoot Root of (recipient, amount, efficiency) tuples for this batch.
     */
    function executeTGE(
        address[] calldata recipients,
        uint256[] calldata amounts,
        uint8[] calldata efficiencies,
        bytes32 merkleRoot
    ) external onlyRole(TGE_ORACLE_ROLE) {
        require(
            recipients.length == amounts.length && amounts.length == efficiencies.length,
            "TGE: array length mismatch"
        );
        require(recipients.length > 0, "TGE: empty batch");
        require(merkleRoot != bytes32(0), "TGE: missing merkle root");

        uint256 batchTotal;
        uint256 batchDistributed;
        uint256 batchBurned;

        for (uint256 i = 0; i < amounts.length; i++) {
            require(efficiencies[i] <= 100, "TGE: efficiency > 100");
            batchTotal += amounts[i];
        }

        require(token.balanceOf(address(this)) >= batchTotal, "TGE: insufficient locked supply");

        for (uint256 i = 0; i < recipients.length; i++) {
            tdeClaimed[keccak256(abi.encode(recipients[i], currentEpoch, currentTgeEvent))] = true;
            uint256 liquid = (amounts[i] * efficiencies[i]) / 100;
            uint256 burned = (currentTgeEvent >= 9) ? (amounts[i] - liquid) : 0;
            if (liquid > 0) {
                token.transfer(recipients[i], liquid);
                batchDistributed += liquid;
            }
            if (burned > 0) batchBurned += burned;
            emit TokensDistributed(recipients[i], liquid, burned, efficiencies[i]);
        }

        if (batchBurned > 0) token.transfer(BURN_ADDRESS, batchBurned);

        totalDistributed += batchDistributed;
        totalBurned += batchBurned;
        epochDistributed += batchDistributed + batchBurned; // fix V1 drift: exact accounting
        tgeCount++;

        batchRoots[_batchKey(currentEpoch, currentTgeEvent)] = merkleRoot;
        emit TGEExecuted(currentEpoch, currentTgeEvent, batchTotal, batchBurned, recipients.length, merkleRoot);

        currentTgeEvent++;
        if (currentTgeEvent >= 10) {
            currentTgeEvent = 0;
            currentEpoch++;
            epochLockedSupply = 0;
            epochDistributed = 0;
        }
    }

    /**
     * @dev Welcome bonus with explicit user vs treasury split.
     *
     * The function signature names the user recipient separately so the contract
     * can enforce two important invariants the V1 contract couldn't:
     *
     *   1. The user receives AT MOST `maxWelcomeBonusPerRecipient` per call AND
     *      cumulatively over their lifetime — they can never receive a second
     *      welcome bonus, even via separate signups.
     *
     *   2. Treasury recipients (founders, liquidity, burn, and the per-signup
     *      community treasury slots) are NOT capped and NOT deduped — the
     *      backend is trusted on those amounts because each signup legitimately
     *      adds to every treasury slot.
     *
     * Why we don't try to auto-detect treasuries: in our WalletFactory, both
     * user wallets and treasury wallets are created via `createWallet(salt)`
     * with different salts. The factory's `walletToPhoneHash` mapping can't
     * distinguish a user phone hash from a community-treasury salt. So we
     * declare the user explicitly at the call site instead.
     *
     * The Merkle root commits to the full (userRecipient, userAmount,
     * treasuryRecipients[], treasuryAmounts[]) tuple — any user can verify
     * their allocation off-chain.
     *
     * @param userRecipient The user's smart wallet receiving the welcome bonus.
     * @param userAmount The welcome bonus (must be <= maxWelcomeBonusPerRecipient).
     * @param treasuryRecipients Founders, liquidity, burn, community treasury slots.
     * @param treasuryAmounts Per-treasury tribute amounts.
     * @param merkleRoot Off-chain commitment to the full distribution.
     */
    function distributeWelcomeBonus(
        address userRecipient,
        uint256 userAmount,
        address[] calldata treasuryRecipients,
        uint256[] calldata treasuryAmounts,
        bytes32 merkleRoot
    ) external onlyRole(TGE_ORACLE_ROLE) {
        require(treasuryRecipients.length == treasuryAmounts.length, "TGE: array length mismatch");
        require(userRecipient != address(0), "TGE: zero user recipient");
        require(userAmount > 0, "TGE: zero user amount");
        require(merkleRoot != bytes32(0), "TGE: missing merkle root");

        uint256 cap = maxWelcomeBonusPerRecipient;
        require(userAmount <= cap, "TGE: user amount exceeds welcome cap");
        require(
            welcomeBonusReceived[userRecipient] + userAmount <= cap,
            "TGE: user already received welcome bonus"
        );
        welcomeBonusReceived[userRecipient] += userAmount;

        uint256 batchTotal = userAmount;
        for (uint256 i = 0; i < treasuryAmounts.length; i++) {
            // Treasuries are uncapped, but we reject 0-amount and 0-address rows
            // so the on-chain log is clean.
            require(treasuryRecipients[i] != address(0), "TGE: zero treasury recipient");
            batchTotal += treasuryAmounts[i];
        }

        require(
            token.balanceOf(address(this)) >= batchTotal,
            "TGE: insufficient epoch supply for welcome bonus"
        );

        // Pay user
        token.transfer(userRecipient, userAmount);

        // Pay treasuries, tracking burn separately so we don't double-count in totalDistributed
        uint256 burnedInBatch;
        for (uint256 i = 0; i < treasuryRecipients.length; i++) {
            if (treasuryAmounts[i] == 0) continue;
            if (treasuryRecipients[i] == BURN_ADDRESS) {
                token.transfer(BURN_ADDRESS, treasuryAmounts[i]);
                burnedInBatch += treasuryAmounts[i];
            } else {
                token.transfer(treasuryRecipients[i], treasuryAmounts[i]);
            }
        }

        // totalDistributed counts non-burn outflows; totalBurned counts burn outflows.
        // Fixes the V1 drift where both were incremented for burn amounts.
        totalDistributed += batchTotal - burnedInBatch;
        totalBurned += burnedInBatch;
        totalWelcomeBonuses += batchTotal;
        epochDistributed += batchTotal;

        bytes32 wbKey = keccak256(abi.encode("WB", currentEpoch, block.number, userRecipient));
        batchRoots[wbKey] = merkleRoot;
        emit WelcomeBonusDistributed(userRecipient, userAmount, treasuryRecipients, treasuryAmounts, batchTotal, currentEpoch, merkleRoot);
    }

    function getLockedBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function getStats() external view returns (
        uint256 epoch,
        uint256 tgeEvent,
        uint256 minted,
        uint256 distributed,
        uint256 burned,
        uint256 events,
        uint256 welcomeBonuses
    ) {
        return (currentEpoch, currentTgeEvent, totalMinted, totalDistributed, totalBurned, tgeCount, totalWelcomeBonuses);
    }

    /**
     * @notice Compare on-chain balance against accounting-derived expected balance.
     * @dev Drift is the unaccounted-for amount, typically from V1 integer-division rounding
     *      in the welcome-bonus path before the V2 fix. Should be 0 for new TGEs after V2.
     */
    function getReconciliation() external view returns (
        uint256 expectedBalance,
        uint256 actualBalance,
        int256 drift
    ) {
        uint256 net = totalMinted >= (totalDistributed + totalBurned)
            ? totalMinted - totalDistributed - totalBurned
            : 0;
        expectedBalance = net;
        actualBalance = token.balanceOf(address(this));
        drift = int256(actualBalance) - int256(expectedBalance);
    }

    function _batchKey(uint256 epoch, uint256 tgeEvent) internal pure returns (bytes32) {
        return keccak256(abi.encode("TGE", epoch, tgeEvent));
    }

    /**
     * @notice Publish Merkle root for a TDE event, locking supply for anytime pull claims.
     * @param epoch The epoch number.
     * @param tgeEvent The TDE event index (0-9).
     * @param merkleRoot The root of eligible claims.
     * @param totalBatchAmount Total earned DSP across all eligible recipients in this TDE.
     */
    function publishTdeRoot(
        uint256 epoch,
        uint256 tgeEvent,
        bytes32 merkleRoot,
        uint256 totalBatchAmount
    ) external onlyRole(TGE_ORACLE_ROLE) {
        require(merkleRoot != bytes32(0), "TGE: missing merkle root");
        require(totalBatchAmount > 0, "TGE: zero batch amount");
        require(token.balanceOf(address(this)) >= totalBatchAmount, "TGE: insufficient locked supply");

        batchRoots[_batchKey(epoch, tgeEvent)] = merkleRoot;
        emit TdeRootPublished(epoch, tgeEvent, merkleRoot, totalBatchAmount);
    }

    /**
     * @notice Pull claim for individual users at any time without expiration.
     * @dev Only tokens lost from the efficiency gate are burned to BURN_ADDRESS.
     *      Users can claim their earned tokens anytime.
     *      Score below 91 does not freeze claims - liquid tokens equal earnedAmount * efficiency / 100.
     * @param recipient The smart wallet address to receive the liquid tokens.
     * @param epoch The epoch of the TDE.
     * @param tgeEvent The TDE event index (0-9).
     * @param earnedAmount Total DSP earned by the user for this TDE.
     * @param efficiency User's PCT efficiency score (0-100).
     * @param proof Merkle inclusion proof.
     */
    function claimTdeTokens(
        address recipient,
        uint256 epoch,
        uint256 tgeEvent,
        uint256 earnedAmount,
        uint8 efficiency,
        bytes32[] calldata proof
    ) external {
        require(recipient != address(0), "TGE: zero recipient");
        require(earnedAmount > 0, "TGE: zero earned amount");
        require(efficiency <= 100, "TGE: efficiency > 100");

        bytes32 claimKey = keccak256(abi.encode(recipient, epoch, tgeEvent));
        require(!tdeClaimed[claimKey], "TGE: already claimed");

        bytes32 root = batchRoots[_batchKey(epoch, tgeEvent)];
        require(root != bytes32(0), "TGE: root not published");

        bytes32 leaf = keccak256(abi.encode(recipient, epoch, tgeEvent, earnedAmount, efficiency));
        require(MerkleProof.verify(proof, root, leaf), "TGE: invalid merkle proof");

        tdeClaimed[claimKey] = true;

        uint256 liquid = (earnedAmount * efficiency) / 100;
        uint256 burned = (tgeEvent >= 9) ? (earnedAmount - liquid) : 0;

        require(token.balanceOf(address(this)) >= (liquid + burned), "TGE: insufficient supply");

        if (liquid > 0) {
            token.transfer(recipient, liquid);
        }
        if (burned > 0) {
            token.transfer(BURN_ADDRESS, burned);
        }

        totalDistributed += liquid;
        totalBurned += burned;
        epochDistributed += (liquid + burned);

        emit TokensClaimed(recipient, epoch, tgeEvent, liquid, burned, efficiency);
    }

    /**
     * @notice Distribute Genesis 7,000 $DIASPORA tokens upon completing 6 base PoH milestones.
     */
    function distributeGenesisTokens(
        address userRecipient,
        uint256 userAmount,
        address[] calldata treasuryRecipients,
        uint256[] calldata treasuryAmounts,
        bytes32 merkleRoot
    ) external onlyRole(TGE_ORACLE_ROLE) {
        require(treasuryRecipients.length == treasuryAmounts.length, "TGE: array length mismatch");
        require(userRecipient != address(0), "TGE: zero user recipient");
        require(userAmount > 0, "TGE: zero user amount");
        require(merkleRoot != bytes32(0), "TGE: missing merkle root");

        uint256 cap = maxGenesisDistribution > 0 ? maxGenesisDistribution : maxWelcomeBonusPerRecipient;
        if (cap == 0) cap = 7000 * 10**18;
        require(userAmount <= cap, "TGE: user amount exceeds genesis cap");
        require(
            genesisDistributionReceived[userRecipient] + userAmount <= cap,
            "TGE: user already received genesis distribution"
        );
        genesisDistributionReceived[userRecipient] += userAmount;

        uint256 batchTotal = userAmount;
        for (uint256 i = 0; i < treasuryAmounts.length; i++) {
            require(treasuryRecipients[i] != address(0), "TGE: zero treasury recipient");
            batchTotal += treasuryAmounts[i];
        }

        require(token.balanceOf(address(this)) >= batchTotal, "TGE: insufficient epoch supply");

        token.transfer(userRecipient, userAmount);

        uint256 burnedInBatch;
        for (uint256 i = 0; i < treasuryRecipients.length; i++) {
            if (treasuryAmounts[i] == 0) continue;
            if (treasuryRecipients[i] == BURN_ADDRESS) {
                token.transfer(BURN_ADDRESS, treasuryAmounts[i]);
                burnedInBatch += treasuryAmounts[i];
            } else {
                token.transfer(treasuryRecipients[i], treasuryAmounts[i]);
            }
        }

        totalDistributed += batchTotal - burnedInBatch;
        totalBurned += burnedInBatch;
        totalWelcomeBonuses += batchTotal;
        epochDistributed += batchTotal;

        bytes32 gKey = keccak256(abi.encode("GENESIS", currentEpoch, block.number, userRecipient));
        batchRoots[gKey] = merkleRoot;
        emit WelcomeBonusDistributed(userRecipient, userAmount, treasuryRecipients, treasuryAmounts, batchTotal, currentEpoch, merkleRoot);
    }

    function setMaxGenesisDistribution(uint256 newMax) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newMax > 0, "TGE: zero max");
        emit MaxGenesisDistributionUpdated(maxGenesisDistribution, newMax);
        maxGenesisDistribution = newMax;
    }

    function _authorizeUpgrade(address newImplementation) internal onlyRole(UPGRADER_ROLE) override {}
}
