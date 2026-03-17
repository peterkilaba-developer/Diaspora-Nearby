// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title DiasporaToken
 * @dev Implementation of the Diaspora Token ($DSP).
 * Upgradable via UUPS Proxy.
 * Features:
 * - Fixed Hard Cap: 1 Quadrillion tokens.
 * - Role-Based Access Control: Compatible with Gnosis Safe Multi-sig.
 * - Just-in-Time Minting: Tokens are minted as community milestones are reached.
 * - Permittable: Supports gasless approvals (EIP-2612).
 */
contract DiasporaToken is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, AccessControlUpgradeable, ERC20PermitUpgradeable, UUPSUpgradeable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    // 1 Quadrillion Hard Cap (18 decimals)
    uint256 public constant HARD_CAP = 1_000_000_000_000_000 * 10**18;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin, address minter, address upgrader) initializer public {
        __ERC20_init("Diaspora", "DIASPORA");
        __ERC20Burnable_init();
        __AccessControl_init();
        __ERC20Permit_init("Diaspora");
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(UPGRADER_ROLE, upgrader);
    }

    /**
     * @dev Mints new tokens. Can only be called by accounts with MINTER_ROLE.
     * Enforces the 1 Quadrillion HARD_CAP.
     * @param to The address that will receive the minted tokens.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        require(totalSupply() + amount <= HARD_CAP, "DiasporaToken: hard cap exceeded");
        _mint(to, amount);
    }

    /**
     * @dev Utility to check progress towards the total hard cap.
     */
    function getHardCapProgress() public view returns (uint256 currentSupply, uint256 maxSupply) {
        return (totalSupply(), HARD_CAP);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}
}
