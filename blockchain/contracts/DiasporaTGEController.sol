// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./DiasporaToken.sol";

/**
 * @title DiasporaTGEController
 * @dev Pre-Minted Epoch Supply TGE Controller.
 *
 * Architecture:
 * - Each epoch's total token supply is PRE-MINTED to this contract via mintEpochSupply().
 * - Users can verify on-chain that the exact epoch supply exists and is locked here.
 * - When a DSP milestone is reached, the Cloud Function oracle:
 *   1. Creates a snapshot of all user/treasury balances + PoCT scores
 *   2. Calls executeTGE() with the snapshot
 *   3. Contract distributes from its pre-minted balance by PoCT efficiency, burns the rest
 *
 * Welcome Bonus Distribution:
 * - On user signup, the oracle calls distributeWelcomeBonus() to instantly convert
 *   the user's DSP welcome bonus (and tribute) to $DIASPORA at 100% efficiency.
 * - This does NOT advance TGE event counters — it's a separate distribution channel.
 *
 * Each Epoch has 10 TGE events. After 10 events, the epoch advances.
 * Upgradable via UUPS Proxy.
 */
contract DiasporaTGEController is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant TGE_ORACLE_ROLE = keccak256("TGE_ORACLE_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    DiasporaToken public token;

    uint256 public currentEpoch;
    uint256 public currentTgeEvent;

    // Lifetime on-chain transparency stats
    uint256 public totalMinted;
    uint256 public totalDistributed;
    uint256 public totalBurned;
    uint256 public tgeCount; // Total TGE events executed

    // Epoch supply tracking
    uint256 public epochLockedSupply;   // Total pre-minted for current epoch
    uint256 public epochDistributed;    // Amount distributed from current epoch

    // V2: Welcome bonus tracking
    uint256 public totalWelcomeBonuses; // Total $DIASPORA distributed as welcome bonuses

    event EpochSupplyMinted(
        uint256 indexed epoch,
        uint256 amount,
        uint256 controllerBalance
    );
    event TGEExecuted(
        uint256 indexed epoch,
        uint256 indexed tgeEvent,
        uint256 minted,
        uint256 burned,
        uint256 recipientCount
    );
    event TokensDistributed(
        address indexed recipient,
        uint256 liquid,
        uint256 burned,
        uint8 efficiency
    );
    event WelcomeBonusDistributed(
        address[] recipients,
        uint256[] amounts,
        uint256 totalAmount,
        uint256 indexed epoch
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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
     * @dev Pre-mint the epoch's token supply and lock it in this contract.
     * Called by admin/oracle BEFORE TGE events begin for each epoch.
     * Users can verify on-chain that the exact epoch supply exists here.
     *
     * @param amount The total epoch supply to mint (e.g. 1,000,000 * 10^18 for Epoch 1)
     */
    function mintEpochSupply(uint256 amount) external onlyRole(TGE_ORACLE_ROLE) {
        require(amount > 0, "TGE: zero amount");

        // Mint tokens to this contract (locked until TGE distribution)
        token.mint(address(this), amount);

        // Track epoch supply
        epochLockedSupply += amount;
        totalMinted += amount;

        emit EpochSupplyMinted(currentEpoch, amount, token.balanceOf(address(this)));
    }

    /**
     * @dev Execute a Token Generation Event from a Firestore snapshot.
     * Distributes from the pre-minted epoch supply (no fresh minting).
     *
     * Called by the Cloud Function oracle when a DSP milestone is reached.
     * The snapshot includes ALL addresses to receive tokens — users, community
     * treasuries, founders, investors — with their earned DSP and efficiency.
     *
     * For system addresses (treasuries, founders, investors), set efficiency to 100.
     * For users, efficiency is derived from PoCT score (decile scale: 0-100).
     *
     * @param recipients Array of wallet addresses (smart wallets)
     * @param amounts Array of DSP amounts earned (in smallest unit, 18 decimals)
     * @param efficiencies Array of PoCT-based efficiencies (0-100, where 100 = 100%)
     */
    function executeTGE(
        address[] calldata recipients,
        uint256[] calldata amounts,
        uint8[] calldata efficiencies
    ) external onlyRole(TGE_ORACLE_ROLE) {
        require(
            recipients.length == amounts.length && amounts.length == efficiencies.length,
            "TGE: array length mismatch"
        );
        require(recipients.length > 0, "TGE: empty batch");

        uint256 batchTotal;
        uint256 batchDistributed;
        uint256 batchBurned;

        // Calculate total needed for this batch
        for (uint256 i = 0; i < amounts.length; i++) {
            batchTotal += amounts[i];
        }

        // Verify controller has enough pre-minted tokens
        uint256 controllerBalance = token.balanceOf(address(this));
        require(controllerBalance >= batchTotal, "TGE: insufficient locked supply");

        // Distribute by efficiency (from pre-minted balance, no fresh minting)
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 liquid = (amounts[i] * efficiencies[i]) / 100;
            uint256 burned = amounts[i] - liquid;

            if (liquid > 0) {
                token.transfer(recipients[i], liquid);
                batchDistributed += liquid;
            }
            if (burned > 0) {
                batchBurned += burned;
            }

            emit TokensDistributed(recipients[i], liquid, burned, efficiencies[i]);
        }

        // Burn all inefficiency in one transfer (gas efficient)
        if (batchBurned > 0) {
            token.transfer(BURN_ADDRESS, batchBurned);
        }

        // Update lifetime stats
        totalDistributed += batchDistributed;
        totalBurned += batchBurned;
        epochDistributed += batchTotal;
        tgeCount++;

        emit TGEExecuted(currentEpoch, currentTgeEvent, batchTotal, batchBurned, recipients.length);

        // Advance TGE event counter
        currentTgeEvent++;
        if (currentTgeEvent >= 10) {
            currentTgeEvent = 0;
            currentEpoch++;
            // Reset epoch tracking for the new epoch
            epochLockedSupply = 0;
            epochDistributed = 0;
        }
    }

    /**
     * @dev Distribute welcome bonus tokens from pre-minted epoch supply.
     *
     * Called by the Cloud Function oracle on user signup. Mirrors the DSP
     * welcome bonus + tribute distribution, but converts to $DIASPORA at
     * 100% efficiency immediately (rather than waiting for a TGE milestone).
     *
     * Recipients include the user's wallet AND all treasury wallets
     * (community treasuries, founders, investors, burn) — same pattern as TGE.
     *
     * Does NOT advance TGE event counters — this is a separate distribution
     * channel that draws from the same pre-minted epoch supply.
     *
     * @param recipients Array of wallet addresses (user + treasury wallets)
     * @param amounts Array of $DIASPORA amounts (in smallest unit, 18 decimals)
     */
    function distributeWelcomeBonus(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyRole(TGE_ORACLE_ROLE) {
        require(recipients.length == amounts.length, "TGE: array length mismatch");
        require(recipients.length > 0, "TGE: empty batch");

        uint256 batchTotal;

        for (uint256 i = 0; i < amounts.length; i++) {
            batchTotal += amounts[i];
        }

        // Verify controller has enough pre-minted tokens
        uint256 controllerBalance = token.balanceOf(address(this));
        require(controllerBalance >= batchTotal, "TGE: insufficient epoch supply for welcome bonus");

        // Distribute at 100% efficiency (no burn on welcome bonus)
        for (uint256 i = 0; i < recipients.length; i++) {
            if (amounts[i] > 0 && recipients[i] != address(0)) {
                // Burn address recipient = actual burn
                if (recipients[i] == BURN_ADDRESS) {
                    token.transfer(BURN_ADDRESS, amounts[i]);
                    totalBurned += amounts[i];
                } else {
                    token.transfer(recipients[i], amounts[i]);
                }
            }
        }

        // Update stats (does NOT advance TGE event counter or epoch)
        totalDistributed += batchTotal;
        totalWelcomeBonuses += batchTotal;
        epochDistributed += batchTotal;

        emit WelcomeBonusDistributed(recipients, amounts, batchTotal, currentEpoch);
    }

    /**
     * @dev View the controller's current $DIASPORA balance (locked tokens awaiting TGE).
     */
    function getLockedBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @dev View the on-chain transparency stats.
     */
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

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}
}

