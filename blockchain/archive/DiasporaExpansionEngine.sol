// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./DiasporaTGEController.sol";
import "./DiasporaAllocationHub.sol";

/**
 * @title DiasporaExpansionEngine
 * @dev The economic motor of the platform. Handles the 1:1 Expansion Rule.
 * Upgradable via UUPS Proxy.
 */
contract DiasporaExpansionEngine is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant REPORTER_ROLE = keccak256("REPORTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    DiasporaTGEController public tgeController;
    DiasporaAllocationHub public allocationHub;

    event ActivityRecorded(address indexed user, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address upgrader,
        address _tgeController,
        address _allocationHub
    ) initializer public {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, upgrader);

        tgeController = DiasporaTGEController(_tgeController);
        allocationHub = DiasporaAllocationHub(_allocationHub);
    }

    /**
     * @dev Records a user activity (e.g., PoA achievement).
     */
    function recordActivity(address user, uint256 amount) external onlyRole(REPORTER_ROLE) {
        tgeController.stageUserReward(user, amount);
        allocationHub.allocate(user, amount);
        emit ActivityRecorded(user, amount);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}
}
