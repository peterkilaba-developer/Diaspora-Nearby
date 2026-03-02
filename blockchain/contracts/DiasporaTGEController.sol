// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./DiasporaToken.sol";

/**
 * @title DiasporaTGEController
 * @dev Manages staged balances and TGE milestones (Supply + Population).
 * Upgradable via UUPS Proxy.
 */
contract DiasporaTGEController is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant ENGINE_ROLE = keccak256("ENGINE_ROLE");
    bytes32 public constant TGE_ORACLE_ROLE = keccak256("TGE_ORACLE_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    DiasporaToken public token;
    
    uint256 public currentEpoch;
    uint256 public currentTgeEvent;
    
    mapping(address => uint256) public stagedUserRewards;
    mapping(address => uint256) public stagedCommunityRewards;
    mapping(address => uint256) public stagedSystemRewards;

    event TGETriggered(uint256 epoch, uint256 eventNumber, uint256 supplyReleased);
    event RewardsStaged(address indexed target, uint256 amount, uint8 typeId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address upgrader, address _token) initializer public {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, upgrader);

        token = DiasporaToken(_token);
        currentEpoch = 1;
        currentTgeEvent = 0;
    }

    /**
     * @dev Stages a user reward.
     */
    function stageUserReward(address user, uint256 amount) external onlyRole(ENGINE_ROLE) {
        token.mint(address(this), amount); 
        stagedUserRewards[user] += amount;
        emit RewardsStaged(user, amount, 0);
    }

    /**
     * @dev Stages a community or system reward.
     */
    function stageMatchReward(address target, uint256 amount, bool isSystem) external onlyRole(ENGINE_ROLE) {
        token.mint(address(this), amount);
        if (isSystem) {
            stagedSystemRewards[target] += amount;
            emit RewardsStaged(target, amount, 2);
        } else {
            stagedCommunityRewards[target] += amount;
            emit RewardsStaged(target, amount, 1);
        }
    }

    /**
     * @dev Triggers a TGE Event.
     */
    function executeTGE(
        address[] calldata recipients,
        uint8[] calldata efficiencies
    ) external onlyRole(TGE_ORACLE_ROLE) {
        require(recipients.length == efficiencies.length, "TGE: data mismatch");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            address target = recipients[i];
            uint256 efficiency = efficiencies[i];
            
            if (stagedUserRewards[target] > 0) {
                _release(target, stagedUserRewards[target], efficiency, true);
                stagedUserRewards[target] = 0;
            }
            
            if (stagedCommunityRewards[target] > 0) {
                _release(target, stagedCommunityRewards[target], efficiency, true);
                stagedCommunityRewards[target] = 0;
            }
            
            if (stagedSystemRewards[target] > 0) {
                _release(target, stagedSystemRewards[target], 100, false);
                stagedSystemRewards[target] = 0;
            }
        }
        
        currentTgeEvent++;
        if (currentTgeEvent >= 10) {
            currentTgeEvent = 0;
            currentEpoch++;
        }
    }

    function _release(address target, uint256 amount, uint256 efficiency, bool applyFilter) internal {
        if (applyFilter) {
            uint256 liquid = (amount * efficiency) / 100;
            uint256 burned = amount - liquid;
            
            if (liquid > 0) token.transfer(target, liquid);
            if (burned > 0) token.transfer(BURN_ADDRESS, burned);
        } else {
            token.transfer(target, amount);
        }
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}
}
