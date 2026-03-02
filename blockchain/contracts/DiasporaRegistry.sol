// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title DiasporaRegistry
 * @dev Stores the mapping of users to their 7 community treasury slots.
 * Upgradable via UUPS Proxy.
 */
contract DiasporaRegistry is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // mapping(user => communities[7])
    mapping(address => address[7]) private _userCommunities;

    event CommunityUpdated(address indexed user, uint8 slot, address indexed communityVault);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address upgrader) initializer public {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, upgrader);
    }

    /**
     * @dev Sets the community vault for a specific slot of a user.
     */
    function setUserCommunity(address user, uint8 slot, address communityVault) external onlyRole(REGISTRAR_ROLE) {
        require(slot < 7, "DiasporaRegistry: invalid slot");
        _userCommunities[user][slot] = communityVault;
        emit CommunityUpdated(user, slot, communityVault);
    }

    /**
     * @dev Batch sets community slots for a user.
     */
    function setUserCommunities(address user, address[7] calldata communityVaults) external onlyRole(REGISTRAR_ROLE) {
        _userCommunities[user] = communityVaults;
        for (uint8 i = 0; i < 7; i++) {
            emit CommunityUpdated(user, i, communityVaults[i]);
        }
    }

    /**
     * @dev Retrieves all 7 community vaults for a user.
     */
    function getUserCommunities(address user) external view returns (address[7] memory) {
        return _userCommunities[user];
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}
}
