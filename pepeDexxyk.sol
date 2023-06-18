// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title SimpleAMM
 * @dev A simple automated market maker (AMM) that allows users to swap tokens, add liquidity, and remove liquidity.
 * Liquidity providers can also claim their share of accumulated fees. This contract uses the x * y = k formula
 * for swaps.
 */
contract SimpleAMM is ReentrancyGuard {
    // ERC20 token to be used
    IERC20 public immutable token;

    // Mapping of liquidity balances
    mapping(address => uint256) public liquidityBalance;

    // Total liquidity in the pool
    uint256 public totalLiquidity;

    // Accumulated fees
    uint256 public accumulatedFees;

    // Mapping of the last accumulated fees per address
    mapping(address => uint256) public lastAccumulatedFees;

    // Structure holding ETH and token reserves
    struct Reserves {
        uint256 reserveETH;
        uint256 reserveToken;
    }
    Reserves public reserves;

    // Fee percentage (0.3% represented as 3)
    uint256 public constant FEE_PERCENTAGE = 3;

    // Events
    event Swapped(address indexed user, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed user, uint256 amountETH, uint256 amountToken);
    event LiquidityRemoved(address indexed user, uint256 amountETH, uint256 amountToken);
    event FeesClaimed(address indexed user, uint256 amount);

    /**
     * @dev Constructor that initializes the token.
     * @param _token The address of the ERC20 token.
     */
    constructor(IERC20 _token) {
        token = _token;
    }

    /**
     * @dev Add liquidity to the pool.
     * @param amountToken The amount of tokens to add as liquidity.
     */
    function addLiquidity(uint256 amountToken) external payable nonReentrant {
        uint256 ethSent = msg.value;
        require(amountToken > 0 && ethSent > 0, "Cannot add zero liquidity");

        // Calculate liquidity to be added
        uint256 liquidity = ethSent;
        if (totalLiquidity != 0) {
            liquidity = ethSent * reserves.reserveToken / reserves.reserveETH;
        }

        // Update liquidity and reserves
        totalLiquidity += liquidity;
        liquidityBalance[msg.sender] += liquidity;
        lastAccumulatedFees[msg.sender] = accumulatedFees;
        reserves.reserveETH += ethSent;
        reserves.reserveToken += amountToken;

        // Transfer tokens from sender to contract
        require(token.transferFrom(msg.sender, address(this), amountToken), "Failed to transfer tokens to contract");

        // Emit event
        emit LiquidityAdded(msg.sender, ethSent, amountToken);
    }

    /**
     * @dev Remove liquidity from the pool.
     * @param liquidity The amount of liquidity to remove.
     */
    function removeLiquidity(uint256 liquidity) external nonReentrant {
        require(liquidity > 0 && liquidity <= liquidityBalance[msg.sender], "Invalid liquidity amount");

        // Calculate the amount of ETH and tokens to withdraw
        uint256 amountETH = liquidity * reserves.reserveETH / totalLiquidity;
        uint256 amountToken = liquidity * reserves.reserveToken / totalLiquidity;

        // Update liquidity and reserves
        totalLiquidity -= liquidity;
        liquidityBalance[msg.sender] -= liquidity;
        reserves.reserveETH -= amountETH;
        reserves.reserveToken -= amountToken;

        // Transfer ETH and tokens to the sender
        payable(msg.sender).transfer(amountETH);
        require(token.transfer(msg.sender, amountToken), "Failed to transfer tokens to user");

        // Emit event
        emit LiquidityRemoved(msg.sender, amountETH, amountToken);
    }

    /**
     * @dev Swap tokens for ETH using the x * y = k formula.
     * @param amountIn The amount of tokens to be swapped for ETH.
     */
    function swap(uint256 amountIn) external nonReentrant {
        require(amountIn > 0, "Invalid input amount");
        require(token.allowance(msg.sender, address(this)) >= amountIn, "Token allowance too small");

        // x * y = k
        uint256 x = reserves.reserveETH;
        uint256 y = reserves.reserveToken;
        uint256 k = x * y;

        // Calculate amountOut based on the x * y = k formula
        uint256 amountOut = y - (k / (x + amountIn));

        // Apply fee
        uint256 amountOutWithFee = amountOut * (100000 - FEE_PERCENTAGE) / 100000;

        // Update reserves
        reserves.reserveToken -= amountOutWithFee;
        reserves.reserveETH += amountIn;

        // Transfer tokens from sender to contract and ETH from contract to sender
        require(token.transferFrom(msg.sender, address(this), amountIn), "Failed to transfer tokens from sender to contract");
        payable(msg.sender).transfer(amountOutWithFee);

        // Emit event
        emit Swapped(msg.sender, amountIn, amountOutWithFee);
    }

    /**
     * @dev Claim accumulated fees.
     */
    function claimFees() external nonReentrant {
        // Calculate fees to be claimed
        uint256 fees = (accumulatedFees - lastAccumulatedFees[msg.sender]) * liquidityBalance[msg.sender] / totalLiquidity;
        lastAccumulatedFees[msg.sender] = accumulatedFees;

        // Transfer fees to the sender
        require(token.transfer(msg.sender, fees), "Failed to transfer fees");

        // Emit event
        emit FeesClaimed(msg.sender, fees);
    }
}
