// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./DiasporaRegistry.sol";
import "./DiasporaTGEController.sol";
import "./DiasporaToken.sol";

/**
 * @title DiasporaAllocationHub
 * @dev Distributes the "System Match" supply into 10 slots (10% each).
 * Upgradable via UUPS Proxy.
 */
contract DiasporaAllocationHub is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    DiasporaToken public token;
    DiasporaRegistry public registry;
    DiasporaTGEController public tgeController;

    address public foundersVault;
    address public investorsVault;

    event Allocated(address indexed user, uint256 totalAmount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address upgrader,
        address _token,
        address _registry,
        address _tgeController,
        address _founders,
        address _investors
    ) initializer public {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, upgrader);

        token = DiasporaToken(_token);
        registry = DiasporaRegistry(_registry);
        tgeController = DiasporaTGEController(_tgeController);
        foundersVault = _founders;
        investorsVault = _investors;
    }

    /**
     * @dev Updates the treasury vaults.
     */
    function setVaults(address _founders, address _investors) external onlyRole(DEFAULT_ADMIN_ROLE) {
        foundersVault = _founders;
        investorsVault = _investors;
    }

    /**
     * @dev Allocates the matched amount into 10 slots and stages them in the TGE Controller.
     * @param user The user whose activity triggered the match.
     * @param amount The total match amount (equals the user reward).
     */
    function allocate(address user, uint256 amount) external onlyRole(DISTRIBUTOR_ROLE) {
        uint256 unit = amount / 10;
        if (unit == 0) return;

        address[7] memory communities = registry.getUserCommunities(user);

        // 7 Community Tributes (Staged)
        for (uint8 i = 0; i < 7; i++) {
            address target = communities[i];
            if (target != address(0)) {
                tgeController.stageMatchReward(target, unit, false); // Community type
            } else {
                // Unassigned slots are burned immediately to keep supply clean
                token.mint(BURN_ADDRESS, unit); 
            }
        }

        // 3 System Slots
        // Founders and Investors are staged, Burn is immediate
        tgeController.stageMatchReward(foundersVault, unit, true); // System type
        tgeController.stageMatchReward(investorsVault, unit, true); // System type
        token.mint(BURN_ADDRESS, unit); // Fixed deflation

        emit Allocated(user, amount);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}
}
