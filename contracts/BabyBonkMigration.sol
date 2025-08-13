// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
    function tradingEnabled() external view returns (bool);
   
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
    * @dev Minimal interface for Uniswap V2 Router
    */
interface IUniswapV2Router {

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountETH);
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function getAmountsOut(uint amountIn, address[] calldata path)
        external view returns (uint[] memory amounts);

    function WETH() external pure returns (address);
}

/**
 * @title BabyBonkMigration
 * @dev A trustless two-phase migration contract for ERC20 tokens from v1 to v2
 * Phase 1: Direct 1:1 migration (first 3 weeks) - v1 tokens go to owner, v2 comes from owner's wallet via approval
 * Phase 2: DEX-based migration through router (after 3 weeks)
 * @notice This contract is designed to be trustless with no emergency controls
 * @notice v1 tokens are sent to the owner's wallet immediately upon migration
 * @notice Owner keeps v2 tokens in wallet and approves contract to spend them
 */
contract BabyBonkMigration is Ownable, ReentrancyGuard {
    // ============ State Variables ============
    
    /// @notice Address of the v1 (old) token contract
    address public immutable v1TokenAddress;
    
    /// @notice Address of the v2 (new) token contract
    address public immutable v2TokenAddress;

    /// @notice Address of the owner's wallet to receive v1 tokens
    address public immutable v1ReceiverWallet;

    /// @notice Total v1 tokens migrated in phase 1
    uint256 public totalV1Migrated;

    /// @notice Total v2 tokens distributed in phase 1
    uint256 public totalV2Distributed;
    
    /// @notice Cached v1 total supply for gas optimization
    uint256 public immutable v1TotalSupply;
    
    /// @notice Cached v2 total supply for gas optimization
    uint256 public immutable v2TotalSupply;

    /// @notice flag to indicate if migration is active. This is set to true when migration starts
    bool public isMigrationActive;

    // ============ Events ============
    
    event PhaseOneMigration(
        address indexed user,
        uint256 v1Amount,
        uint256 v2Amount
    );

    // ============ Modifiers ============
    
    /**
     * @dev Ensures migration has started
     */
    modifier migrationActive() {
        require(isMigrationActive, "BabyBonkMigrator: Migration not yet active");
        _;
    }

    // ============ Constructor ============
    
    /**
     * @notice Initialize the migration contract with immutable parameters
     * @param _v1TokenAddress Address of the v1 token contract
     * @param _v2TokenAddress Address of the v2 token contract
     */
    constructor(
        address _v1TokenAddress,
        address _v2TokenAddress,
        address _v1ReceiverWallet
    ) Ownable() {
        require(_v1TokenAddress != address(0), "BabyBonkMigrator: Invalid v1 token address");
        require(_v2TokenAddress != address(0), "BabyBonkMigrator: Invalid v2 token address");

        v1TokenAddress = _v1TokenAddress;
        v2TokenAddress = _v2TokenAddress;
        v1ReceiverWallet = _v1ReceiverWallet; // Owner's wallet to receive v1 tokens
        
        // Cache total supplies for gas optimization and immutability
        v1TotalSupply = IERC20(_v1TokenAddress).totalSupply();
        v2TotalSupply = IERC20(_v2TokenAddress).totalSupply();
        
        require(v1TotalSupply > 0, "BabyBonkMigrator: V1 total supply must be greater than zero");
        require(v2TotalSupply > 0, "BabyBonkMigrator: V2 total supply must be greater than zero");
    }

    // ============ Owner Functions ============
    
    /**
     * @notice Owner can withdraw v1 tokens received from migrations
     * @param amount Amount of v1 tokens to withdraw (0 = withdraw all)
     */
    function withdrawV1Tokens(uint256 amount) external onlyOwner {
        uint256 balance = IERC20(v1TokenAddress).balanceOf(address(this));
        require(balance > 0, "BabyBonkMigrator: No v1 tokens to withdraw");
        
        uint256 withdrawAmount = amount == 0 ? balance : amount;
        require(withdrawAmount <= balance, "BabyBonkMigrator: Insufficient v1 token balance");
        
        IERC20(v1TokenAddress).transfer(owner(), withdrawAmount);
    }

    function tradingEnabled() public view returns (bool) {
        // Trading is enabled if liquidity has been added and phase 2 has started
        return IERC20(v2TokenAddress).tradingEnabled();
    }

    function activateMigration() external onlyOwner {
        require(!isMigrationActive, "BabyBonkMigrator: Migration already active");
        isMigrationActive = true;
    }

    function getExpectedMigrationOutput(uint256 v1Amount) 
        external 
        view
        returns (uint256) 
    {
        if(v1Amount == 0 || !isMigrationActive) {
            return 0;
        }
        
        if (!tradingEnabled()) {
            // Phase 1: Proportional ratio based on total supplies
            uint256 v2Amount = calculateV2Amount(v1Amount);
            return v2Amount;
        } else {
            // Phase 2: Get expected output from DEX
            return 0;
        }
    }

    // ============ Migration Functions ============
    
    /**
     * @notice Migrate v1 tokens to v2 tokens (handles both phases automatically)
     * @param amount Amount of v1 tokens to migrate
     */
    function migrate(uint256 amount) 
        external 
        nonReentrant 
        migrationActive 
    {
        require(amount > 0, "BabyBonkMigrator: Amount must be greater than zero");
        
        IERC20(v1TokenAddress).transferFrom(msg.sender, v1ReceiverWallet, amount);
        if (!tradingEnabled()) {
            // Phase 1: Direct 1:1 migration using owner's v2 token allowance
            _migratePhaseOne(amount);
        } else {
            // Phase 2: DEX-based migration
            revert("BabyBonkMigrator: Phase 1 completed please use pancake router");
        }
    }

    /**
     * @notice Get available v2 tokens for phase 1 migrations from owner's wallet
     * @return available Amount of v2 tokens available (minimum of owner's balance and allowance)
     */
    function getAvailableV2Tokens() external view returns (uint256 available) {
        uint256 ownerBalance = IERC20(v2TokenAddress).balanceOf(owner());
        uint256 allowance = IERC20(v2TokenAddress).allowance(owner(), address(this));
        return ownerBalance < allowance ? ownerBalance : allowance;
    }

    /**
     * @notice Calculate proportional v2 amount based on total supplies
     * @param v1Amount Amount of v1 tokens
     * @return v2Amount Proportional amount of v2 tokens
     */
    function calculateV2Amount(uint256 v1Amount) public view returns (uint256 v2Amount) {
        // Formula: v2Amount = (v1Amount * v2TotalSupply) / v1TotalSupply
        // This maintains the proportional relationship based on total supplies
        uint256 v2Amount = (v1Amount * v2TotalSupply) / v1TotalSupply;
        return v2Amount;
    }

    // ============ Internal Functions ============
    
    /**
     * @dev Execute phase 1 migration (proportional conversion using owner's wallet allowance)
     * @param amount Amount of v1 tokens to migrate
     */
    function _migratePhaseOne(uint256 amount) internal {
        // Calculate proportional v2 amount based on total supplies
        uint256 v2Amount = calculateV2Amount(amount);
        
        // Check owner's v2 token balance
        uint256 ownerBalance = IERC20(v2TokenAddress).balanceOf(owner());
        require(ownerBalance >= v2Amount, "BabyBonkMigrator: Owner has insufficient v2 token balance");
        
        // Check owner's allowance to this contract
        uint256 allowance = IERC20(v2TokenAddress).allowance(owner(), address(this));
        require(allowance >= v2Amount, "BabyBonkMigrator: Insufficient v2 token allowance from owner");
        
        // Transfer v2 tokens from owner to user (v1 tokens already received by contract)
        IERC20(v2TokenAddress).transferFrom(owner(), msg.sender, v2Amount);
        
        // Update tracking variables
        totalV1Migrated += amount;
        totalV2Distributed += v2Amount;
        
        emit PhaseOneMigration(msg.sender, amount, v2Amount);
    }
}