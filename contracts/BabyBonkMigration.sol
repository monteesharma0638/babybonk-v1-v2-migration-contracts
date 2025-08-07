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
 * @notice Owner keeps v2 tokens in wallet and approves contract to spend them
 */
contract BabyBonkMigration is Ownable, ReentrancyGuard {
    // ============ State Variables ============
    
    /// @notice Address of the v1 (old) token contract
    address public immutable v1TokenAddress;
    
    /// @notice Address of the v2 (new) token contract
    address public immutable v2TokenAddress;
    
    /// @notice Address of the DEX router for phase 2 swaps
    address public immutable routerV2Address;
    
    /// @notice Timestamp when migration becomes active
    uint256 public immutable migrationStartTime;
    
    /// @notice Timestamp when phase 2 begins (3 weeks after start)
    uint256 public immutable phaseTwoStartTime;
    
    /// @notice Duration of phase 1 in seconds (3 weeks)
    uint256 public constant PHASE_ONE_DURATION = 3 weeks;
    
    /// @notice Maximum slippage allowed in phase 2 (5% = 500 basis points)
    uint256 public constant MAX_SLIPPAGE_BPS = 500;
    
    /// @notice Basis points denominator (10000 = 100%)
    uint256 public constant BPS_DENOMINATOR = 10000;

    /// @notice Total v1 tokens migrated in phase 1
    uint256 public totalV1Migrated;

    /// @notice Total v2 tokens distributed in phase 1
    uint256 public totalV2Distributed;
    
    /// @notice Cached v1 total supply for gas optimization
    uint256 public immutable v1TotalSupply;
    
    /// @notice Cached v2 total supply for gas optimization
    uint256 public immutable v2TotalSupply;

    // ============ Events ============
    
    event PhaseOneMigration(
        address indexed user,
        uint256 v1Amount,
        uint256 v2Amount
    );
    
    event PhaseTwoMigration(
        address indexed user,
        uint256 v1Amount,
        uint256 v2Amount,
        uint256 minV2Amount
    );

    // ============ Modifiers ============
    
    /**
     * @dev Ensures migration has started
     */
    modifier migrationActive() {
        require(
            block.timestamp >= migrationStartTime,
            "TokenMigrator: Migration not yet active"
        );
        _;
    }

    // ============ Constructor ============
    
    /**
     * @notice Initialize the migration contract with immutable parameters
     * @param _v1TokenAddress Address of the v1 token contract
     * @param _v2TokenAddress Address of the v2 token contract
     * @param _migrationStartTime Timestamp when migration begins
     */
    constructor(
        address _v1TokenAddress,
        address _v2TokenAddress,
        uint256 _migrationStartTime
    ) Ownable() {
        require(_v1TokenAddress != address(0), "TokenMigrator: Invalid v1 token address");
        require(_v2TokenAddress != address(0), "TokenMigrator: Invalid v2 token address");
        require(_migrationStartTime > block.timestamp, "TokenMigrator: Start time must be in future");

        v1TokenAddress = _v1TokenAddress;
        v2TokenAddress = _v2TokenAddress;
        routerV2Address = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
        migrationStartTime = _migrationStartTime;
        phaseTwoStartTime = _migrationStartTime + PHASE_ONE_DURATION;
        
        // Cache total supplies for gas optimization and immutability
        v1TotalSupply = IERC20(_v1TokenAddress).totalSupply();
        v2TotalSupply = IERC20(_v2TokenAddress).totalSupply();
        
        require(v1TotalSupply > 0, "TokenMigrator: V1 total supply must be greater than zero");
        require(v2TotalSupply > 0, "TokenMigrator: V2 total supply must be greater than zero");
    }

    // ============ Owner Functions ============
    
    /**
     * @notice Owner can withdraw v1 tokens received from migrations
     * @param amount Amount of v1 tokens to withdraw (0 = withdraw all)
     */
    function withdrawV1Tokens(uint256 amount) external onlyOwner {
        uint256 balance = IERC20(v1TokenAddress).balanceOf(address(this));
        require(balance > 0, "TokenMigrator: No v1 tokens to withdraw");
        
        uint256 withdrawAmount = amount == 0 ? balance : amount;
        require(withdrawAmount <= balance, "TokenMigrator: Insufficient v1 token balance");
        
        IERC20(v1TokenAddress).transfer(owner(), withdrawAmount);
    }

    // ============ Migration Functions ============
    
    /**
     * @notice Migrate v1 tokens to v2 tokens (handles both phases automatically)
     * @param amount Amount of v1 tokens to migrate
     * @param minV2Amount Minimum amount of v2 tokens to receive (only used in phase 2)
     */
    function migrate(uint256 amount, uint256 minV2Amount) 
        external 
        nonReentrant 
        migrationActive 
    {
        require(amount > 0, "TokenMigrator: Amount must be greater than zero");
        
        // Transfer v1 tokens from user to this contract
        IERC20(v1TokenAddress).transferFrom(msg.sender, address(this), amount);
        
        if (block.timestamp < phaseTwoStartTime) {
            // Phase 1: Direct 1:1 migration using owner's v2 token allowance
            _migratePhaseOne(amount);
        } else {
            // Phase 2: DEX-based migration
            _migratePhaseTwo(amount, minV2Amount);
        }
    }

    /**
     * @notice Get expected v2 tokens for a given v1 amount (preview function)
     * @param v1Amount Amount of v1 tokens to migrate
     * @return expectedV2Amount Expected amount of v2 tokens
     * @return isPhaseOne Whether this would use phase 1 logic
     */
    function getExpectedMigrationOutput(uint256 v1Amount) 
        external 
        view
        returns (uint256 expectedV2Amount, bool isPhaseOne) 
    {
        require(v1Amount > 0, "TokenMigrator: Amount must be greater than zero");
        
        if (block.timestamp < migrationStartTime) {
            return (0, true); // Migration not started
        }
        
        if (block.timestamp < phaseTwoStartTime) {
            // Phase 1: Proportional ratio based on total supplies
            uint256 v2Amount = calculateV2Amount(v1Amount);
            uint256 ownerBalance = IERC20(v2TokenAddress).balanceOf(owner());
            uint256 allowance = IERC20(v2TokenAddress).allowance(owner(), address(this));
            uint256 availableAmount = ownerBalance < allowance ? ownerBalance : allowance;
            require(v2Amount <= availableAmount, "TokenMigrator: Insufficient v2 token allowance from owner");
            return (v2Amount, true);
        } else {
            // Phase 2: Get expected output from DEX
            address[] memory path = _getSwapPath();
            try IUniswapV2Router(routerV2Address).getAmountsOut(v1Amount, path) returns (uint[] memory amounts) {
                return (amounts[amounts.length - 1], false);
            } catch {
                return (0, false);
            }
        }
    }

    // ============ View Functions ============
    
    /**
     * @notice Check which migration phase is currently active
     * @return phase Current phase (1 or 2), 0 if migration hasn't started
     */
    function getCurrentPhase() external view returns (uint8 phase) {
        if (block.timestamp < migrationStartTime) {
            return 0; // Not started
        } else if (block.timestamp < phaseTwoStartTime) {
            return 1; // Phase 1
        } else {
            return 2; // Phase 2
        }
    }

    /**
     * @notice Get time remaining in current phase
     * @return timeRemaining Seconds remaining in current phase (0 if in phase 2)
     */
    function getTimeRemainingInPhase() external view returns (uint256 timeRemaining) {
        if (block.timestamp < migrationStartTime) {
            return migrationStartTime - block.timestamp;
        } else if (block.timestamp < phaseTwoStartTime) {
            return phaseTwoStartTime - block.timestamp;
        } else {
            return 0; // Phase 2 is indefinite
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
     * @notice Get owner's v2 token balance
     * @return balance Owner's v2 token balance
     */
    function getOwnerV2Balance() external view returns (uint256 balance) {
        return IERC20(v2TokenAddress).balanceOf(owner());
    }

    /**
     * @notice Get owner's allowance to this contract for v2 tokens
     * @return allowance Current allowance from owner to this contract
     */
    function getOwnerV2Allowance() external view returns (uint256 allowance) {
        return IERC20(v2TokenAddress).allowance(owner(), address(this));
    }

    /**
     * @notice Get collected v1 tokens that can be withdrawn by owner
     * @return collected Amount of v1 tokens in contract
     */
    function getCollectedV1Tokens() external view returns (uint256 collected) {
        return IERC20(v1TokenAddress).balanceOf(address(this));
    }

    /**
     * @notice Calculate proportional v2 amount based on total supplies
     * @param v1Amount Amount of v1 tokens
     * @return v2Amount Proportional amount of v2 tokens
     */
    function calculateV2Amount(uint256 v1Amount) public view returns (uint256 v2Amount) {
        // Formula: v2Amount = (v1Amount * v2TotalSupply) / v1TotalSupply
        // This maintains the proportional relationship based on total supplies
        return (v1Amount * v2TotalSupply) / v1TotalSupply;
    }

    /**
     * @notice Get the migration ratio (how many v2 tokens per v1 token)
     * @return ratio Migration ratio scaled by 1e18 for precision
     */
    function getMigrationRatio() external view returns (uint256 ratio) {
        // Returns ratio with 18 decimal precision
        // Example: if 1 v1 = 10 v2, returns 10 * 1e18
        return (v2TotalSupply * 1e18) / v1TotalSupply;
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
        require(ownerBalance >= v2Amount, "TokenMigrator: Owner has insufficient v2 token balance");
        
        // Check owner's allowance to this contract
        uint256 allowance = IERC20(v2TokenAddress).allowance(owner(), address(this));
        require(allowance >= v2Amount, "TokenMigrator: Insufficient v2 token allowance from owner");
        
        // Transfer v2 tokens from owner to user (v1 tokens already received by contract)
        IERC20(v2TokenAddress).transferFrom(owner(), msg.sender, v2Amount);
        
        // Update tracking variables
        totalV1Migrated += amount;
        totalV2Distributed += v2Amount;
        
        emit PhaseOneMigration(msg.sender, amount, v2Amount);
    }

    /**
     * @dev Execute phase 2 migration (DEX-based swap)
     * @param amount Amount of v1 tokens to migrate
     * @param minV2Amount Minimum v2 tokens to receive
     */
    function _migratePhaseTwo(uint256 amount, uint256 minV2Amount) internal {
        // Approve router to spend v1 tokens
        IERC20 v1Token = IERC20(v1TokenAddress);
        IERC20 weth = IERC20(IUniswapV2Router(routerV2Address).WETH());
        v1Token.approve(routerV2Address, amount);

        uint256 PrevWETHBalance = weth.balanceOf(address(this));

        // Execute swap: V1 -> WETH -> V2
        (address[] memory path, address[] memory path2) = _getSwapPaths();
        IUniswapV2Router(routerV2Address).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount,
            minV2Amount,
            path,
            address(this),
            block.timestamp + 300 // 5 minute deadline
        );

        uint256 newWETHBalance = weth.balanceOf(address(this));
        uint256 wethReceived = newWETHBalance - PrevWETHBalance;

        IERC20 v2Token = IERC20(v2TokenAddress);
        uint256 previousV2Balance = v2Token.balanceOf(msg.sender);

        if(wethReceived == 0) {
            revert("TokenMigrator: No WETH received from swap");
        }

        // Approve router to spend WETH
        weth.approve(routerV2Address, wethReceived);
        IUniswapV2Router(routerV2Address).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            wethReceived,
            minV2Amount,
            path2,
            msg.sender,
            block.timestamp + 300 // 5 minute deadline
        );

        uint256 newV2Balance = v2Token.balanceOf(msg.sender);
        uint256 v2Received = newV2Balance - previousV2Balance;

        // uint256 v2Received = amounts[amounts.length - 1];
        emit PhaseTwoMigration(msg.sender, amount, v2Received, minV2Amount);
    }

    /**
     * @dev Get swap path for DEX router (V1 -> WETH -> V2)
     * @return path Array of token addresses for the swap
     */
    function _getSwapPath() internal view returns (address[] memory path) {
        address weth = IUniswapV2Router(routerV2Address).WETH();
        path = new address[](3);
        path[0] = v1TokenAddress;
        path[1] = weth;
        path[2] = v2TokenAddress;
    }

    function _getSwapPaths() internal view returns (address[] memory path, address[] memory path2) {
        address weth = IUniswapV2Router(routerV2Address).WETH();
        path = new address[](2);
        path[0] = v1TokenAddress;
        path[1] = weth;

        path2 = new address[](2);
        path2[0] = weth;
        path2[1] = v2TokenAddress;
    }
}