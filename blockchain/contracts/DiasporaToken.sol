// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC-20/ERC-20.sol";
import "@openzeppelin/contracts/token/ERC-20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC-20/extensions/ERC20Permit.sol";

/**
 * @title DiasporaToken
 * @dev Implementation of the Diaspora Token ($DSP).
 * Features:
 * - Fixed Hard Cap: 1 Trillion tokens.
 * - Role-Based Access Control: Compatible with Gnosis Safe Multi-sig.
 * - Just-in-Time Minting: Tokens are minted as community milestones are reached.
 * - Permittable: Supports gasless approvals (EIP-2612).
 */
contract DiasporaToken is ERC20, ERC20Burnable, AccessControl, ERC20Permit {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    // 1 Trillion Hard Cap (18 decimals)
    uint256 public constant HARD_CAP = 1_000_000_000_000 * 10**18;

    constructor(address defaultAdmin, address minter) 
        ERC20("Diaspora", "DSP") 
        ERC20Permit("Diaspora") 
    {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
    }

    /**
     * @dev Mints new tokens. Can only be called by accounts with MINTER_ROLE.
     * Enforces the 1 Trillion HARD_CAP.
     * @param to The address that will receive the minted tokens.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        require(totalSupply() + amount <= HARD_CAP, "DiasporaToken: hard cap exceeded");
        _mint(to, amount);
    }

    /**
     * @dev Utility to check progress towards the total hard cap.
     * Useful for Epoch-based transparency.
     */
    function getHardCapProgress() public view returns (uint256 currentSupply, uint256 maxSupply) {
        return (totalSupply(), HARD_CAP);
    }
}
