// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

/**
 * @title DiasporaSmartWallet
 * @dev Minimal smart wallet for Diaspora users. Uses phone-number-derived
 *      deterministic addresses via CREATE2 and an opaque server-derived salt.
 * 
 * Account Abstraction Lite:
 * - No private keys needed by the user
 * - Backend (Cloud Function) acts as the authorized executor
 * - A keyed, non-reversible user identifier is used as the CREATE2 salt
 * - Supports ERC-20 token transfers (gasless for the user)
 * - Owner can be rotated (for phone number changes)
 */
contract DiasporaSmartWallet {
    address public owner;
    address public factory;
    bool private _initialized;

    event Executed(address indexed target, uint256 value, bytes data, bool success);
    event ExecutionFailed(address indexed target, uint256 value, bytes data, bytes reason);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    /**
     * @dev Disable initialize() on the implementation contract.
     * Clones (deployed via Clones.cloneDeterministic in the factory) do not
     * inherit the implementation's storage, so they are unaffected and can
     * still be initialized by the factory exactly once. This only prevents
     * an attacker from calling initialize() on the implementation contract
     * itself to claim ownership of an empty stub.
     */
    constructor() {
        _initialized = true;
    }

    modifier onlyOwnerOrFactory() {
        require(msg.sender == owner || msg.sender == factory, "DSW: unauthorized");
        _;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "DSW: only factory");
        _;
    }

    /**
     * @dev Initialize the wallet. Can only be called once (by the factory).
     * @param _owner The backend-controlled owner address (Cloud Function signer)
     */
    function initialize(address _owner) external {
        require(!_initialized, "DSW: already initialized");
        owner = _owner;
        factory = msg.sender;
        _initialized = true;
    }

    /**
     * @dev Execute an arbitrary call. Used by the backend to send tokens, etc.
     */
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyOwnerOrFactory returns (bytes memory) {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) {
            emit ExecutionFailed(target, value, data, result);
            // Bubble up the revert reason if any
            if (result.length > 0) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
            revert("DSW: execution failed");
        }
        emit Executed(target, value, data, true);
        return result;
    }

    /**
     * @dev Transfer ERC-20 tokens from this wallet. Convenience function.
     */
    function transferToken(
        address token,
        address to,
        uint256 amount
    ) external onlyOwnerOrFactory returns (bool) {
        bool success = IERC20(token).transfer(to, amount);
        require(success, "DSW: token transfer failed");
        return true;
    }

    /**
     * @dev Change the owner (e.g., when user changes phone number).
     */
    function changeOwner(address newOwner) external onlyFactory {
        require(newOwner != address(0), "DSW: zero address");
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    /**
     * @dev Allow receiving ETH (for gas relay or native token).
     */
    receive() external payable {}
}

/**
 * @title DiasporaWalletFactory
 * @dev Factory that deploys DiasporaSmartWallet instances using CREATE2.
 *      The salt is a keyed opaque identifier, making wallet addresses
 *      deterministic without publishing a dictionary-attackable phone hash.
 * 
 * Key invariant: the same opaque identifier → the same address every time.
 */
contract DiasporaWalletFactory is AccessControl {
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

    address public immutable walletImplementation;
    address public backendSigner; // The Cloud Function's signing address

    // phone hash => wallet address
    mapping(bytes32 => address) public wallets;
    // wallet address => phone hash (reverse lookup)
    mapping(address => bytes32) public walletToPhoneHash;
    // total wallets created
    uint256 public totalWallets;

    event WalletCreated(
        bytes32 indexed phoneHash,
        address indexed wallet,
        uint256 walletIndex
    );
    event WalletMigrated(
        bytes32 indexed oldPhoneHash,
        bytes32 indexed newPhoneHash,
        address indexed wallet
    );
    event BackendSignerUpdated(address indexed oldSigner, address indexed newSigner);

    constructor(address _admin, address _backendSigner) {
        walletImplementation = address(new DiasporaSmartWallet());
        backendSigner = _backendSigner;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(DEPLOYER_ROLE, _admin);
        _grantRole(DEPLOYER_ROLE, _backendSigner);
    }

    /**
     * @dev Compute the deterministic address for a phone hash WITHOUT deploying.
     *      This allows the backend to know the wallet address before deployment.
     * @param phoneHash keccak256(abi.encodePacked(phoneNumber))
     */
    function computeAddress(bytes32 phoneHash) public view returns (address) {
        return Clones.predictDeterministicAddress(
            walletImplementation,
            phoneHash,
            address(this)
        );
    }

    /**
     * @dev Deploy a smart wallet for a phone number hash.
     *      If the wallet already exists, returns the existing address.
     * @param phoneHash keccak256(abi.encodePacked(phoneNumber))
     */
    function createWallet(bytes32 phoneHash) 
        external 
        onlyRole(DEPLOYER_ROLE) 
        returns (address wallet) 
    {
        // Return existing wallet if already deployed
        if (wallets[phoneHash] != address(0)) {
            return wallets[phoneHash];
        }

        // Deploy using CREATE2 (deterministic address)
        wallet = Clones.cloneDeterministic(walletImplementation, phoneHash);
        
        // Initialize the wallet with the backend signer as owner
        DiasporaSmartWallet(payable(wallet)).initialize(backendSigner);

        // Store mappings
        wallets[phoneHash] = wallet;
        walletToPhoneHash[wallet] = phoneHash;
        totalWallets++;

        emit WalletCreated(phoneHash, wallet, totalWallets);
        return wallet;
    }

    /**
     * @dev Migrate a wallet from one phone number to another.
     *      Used when a user changes their phone number.
     */
    function migrateWallet(
        bytes32 oldPhoneHash, 
        bytes32 newPhoneHash
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(wallets[oldPhoneHash] != address(0), "DWF: old wallet not found");
        require(wallets[newPhoneHash] == address(0), "DWF: new phone already has wallet");

        address wallet = wallets[oldPhoneHash];
        
        // Update mappings
        wallets[newPhoneHash] = wallet;
        walletToPhoneHash[wallet] = newPhoneHash;
        delete wallets[oldPhoneHash];

        emit WalletMigrated(oldPhoneHash, newPhoneHash, wallet);
    }

    /**
     * @dev Update the backend signer address (e.g., key rotation).
     */
    function updateBackendSigner(address newSigner) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(newSigner != address(0), "DWF: zero address");
        
        // Grant deployer role to new signer, revoke from old
        _grantRole(DEPLOYER_ROLE, newSigner);
        _revokeRole(DEPLOYER_ROLE, backendSigner);
        
        emit BackendSignerUpdated(backendSigner, newSigner);
        backendSigner = newSigner;
    }

    /**
     * @dev Rotate one existing wallet after the backend signer changes.
     * Kept explicit so operators can migrate in bounded, auditable batches.
     */
    function rotateWalletOwner(address wallet, address newSigner)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(wallet != address(0) && newSigner != address(0), "DWF: zero address");
        require(walletToPhoneHash[wallet] != bytes32(0), "DWF: unknown wallet");
        require(newSigner == backendSigner, "DWF: signer mismatch");
        DiasporaSmartWallet(payable(wallet)).changeOwner(newSigner);
    }

    /** @dev Batch variant capped to prevent an unbounded-gas transaction. */
    function rotateWalletOwners(address[] calldata walletList, address newSigner)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newSigner != address(0), "DWF: zero address");
        require(walletList.length > 0 && walletList.length <= 100, "DWF: invalid batch");
        require(newSigner == backendSigner, "DWF: signer mismatch");
        for (uint256 i = 0; i < walletList.length; i++) {
            address wallet = walletList[i];
            require(walletToPhoneHash[wallet] != bytes32(0), "DWF: unknown wallet");
            DiasporaSmartWallet(payable(wallet)).changeOwner(newSigner);
        }
    }

    /**
     * @dev Check if a wallet exists for a phone hash.
     */
    function walletExists(bytes32 phoneHash) external view returns (bool) {
        return wallets[phoneHash] != address(0);
    }

    /**
     * @dev Get wallet address for a phone hash. Returns zero if not deployed.
     */
    function getWallet(bytes32 phoneHash) external view returns (address) {
        return wallets[phoneHash];
    }
}
