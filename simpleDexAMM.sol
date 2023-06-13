// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface ISimpleAMM {
    function addLiquidity(uint256 amountToken) external payable;
    function removeLiquidity(uint256 liquidity) external;
    function swap(uint256 amountIn, uint256 maxSlippagePercentage, uint256 deadline) external payable;
    function getAmountOut(uint256 amountIn) external view returns (uint256);
    function getAmountETHOut(uint256 amountToken) external view returns (uint256);
    function calculatePriceImpact(uint256 amountIn) external view returns (uint256);
}

contract SimpleAMM is ISimpleAMM, ReentrancyGuard {
    using SafeMath for uint256;

    IERC20 public immutable token;
    mapping(address => uint256) public liquidityBalance;
    uint256 public totalLiquidity;
    uint256 public reserveETH;
    uint256 public reserveToken;

    uint256 public constant MAX_SLIPPAGE_PERCENTAGE = 3; // Maximum acceptable slippage percentage

    event Swapped(address indexed user, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed user, uint256 amountETH, uint256 amountToken);
    event LiquidityRemoved(address indexed user, uint256 amountETH, uint256 amountToken);

    constructor(IERC20 _token) {
        token = _token;
    }

    // Allow the contract to spend tokens on behalf of the user
    function approveToken(uint256 amount) external {
        require(token.approve(address(this), amount), "Token approval failed");
    }

    function addLiquidity(uint256 amountToken) external payable nonReentrant {
        require(amountToken > 0 && msg.value > 0, "Cannot add zero liquidity");
        require(token.allowance(msg.sender, address(this)) >= amountToken, "Token allowance too small");

        uint256 liquidity = msg.value;
        if (totalLiquidity != 0) {
            liquidity = msg.value.mul(totalLiquidity).div(reserveETH);
        }
        totalLiquidity = totalLiquidity.add(liquidity);
        liquidityBalance[msg.sender] = liquidityBalance[msg.sender].add(liquidity);
        reserveETH = reserveETH.add(msg.value);
        reserveToken = reserveToken.add(amountToken);

        require(token.transferFrom(msg.sender, address(this), amountToken), "Failed to transfer tokens from sender to contract");
        emit LiquidityAdded(msg.sender, msg.value, amountToken);
    }

    function removeLiquidity(uint256 liquidity) external nonReentrant {
        require(liquidity > 0 && liquidityBalance[msg.sender] >= liquidity, "Cannot remove zero liquidity or liquidity that you did not add");

        uint256 amountETH = liquidity.mul(reserveETH).div(totalLiquidity);
        uint256 amountToken = liquidity.mul(reserveToken).div(totalLiquidity);
        require(amountETH > 0 && amountToken > 0, "Not enough liquidity");

        reserveETH = reserveETH.sub(amountETH);
        reserveToken = reserveToken.sub(amountToken);
        liquidityBalance[msg.sender] = liquidityBalance[msg.sender].sub(liquidity);
        totalLiquidity = totalLiquidity.sub(liquidity);

        require(token.transfer(msg.sender, amountToken), "Failed to transfer tokens from contract to sender");
        payable(msg.sender).transfer(amountETH);
        emit LiquidityRemoved(msg.sender, amountETH,Sorry, the response was cut off. Here's the continuation of the contract:

```solidity
        amountToken);
    }

    function swap(uint256 amountIn, uint256 maxSlippagePercentage, uint256 deadline) external payable nonReentrant {
        require(amountIn > 0 && msg.value > 0, "Cannot swap zero");
        require(maxSlippagePercentage <= MAX_SLIPPAGE_PERCENTAGE, "Slippage exceeds maximum acceptable percentage");
        require(block.timestamp <= deadline, "Transaction expired");

        uint256 amountETHIn = msg.value;
        uint256 amountTokenOut = getAmountOut(amountETHIn);
        uint256 slippageAmount = amountTokenOut.mul(maxSlippagePercentage).div(100);
        uint256 minimumAmountTokenOut = amountTokenOut.sub(slippageAmount);
        require(minimumAmountTokenOut <= reserveToken, "Not enough liquidity");

        reserveETH = reserveETH.add(amountETHIn);
        reserveToken = reserveToken.sub(amountTokenOut);
        require(token.transfer(msg.sender, amountTokenOut), "Failed to transfer tokens from contract to sender");
        emit Swapped(msg.sender, amountETHIn, amountTokenOut);
    }

    function getAmountOut(uint256 amountIn) public view returns (uint256) {
        require(reserveETH > 0 && reserveToken > 0, "Insufficient liquidity");
        uint256 amountInWithFee = amountIn.mul(997);
        uint256 numerator = amountInWithFee.mul(reserveToken);
        uint256 denominator = reserveETH.mul(1000).add(amountInWithFee);
        return numerator / denominator;
    }

    function getAmountETHOut(uint256 amountToken) public view returns (uint256) {
        require(reserveETH > 0 && reserveToken > 0, "Insufficient liquidity");
        return amountToken.mul(reserveETH).div(reserveToken); // Reverse calculation for removing liquidity
    }

    function calculatePriceImpact(uint256 amountIn) public view returns (uint256) {
        require(reserveETH > 0 && reserveToken > 0, "Insufficient liquidity");
        uint256 amountOut = getAmountOut(amountIn);
        uint256 newReserveToken = reserveToken.sub(amountOut);
        uint256 newReserveETH = reserveETH.add(amountIn);
        uint256 newPrice = newReserveETH.mul(1e18).div(newReserveToken); // Scaled by 1e18 to handle decimals
        uint256 oldPrice = reserveETH.mul(1e18).div(reserveToken); // Scaled by 1e18 to handle decimals
        return oldPrice > newPrice ? oldPrice.sub(newPrice) : newPrice.sub(oldPrice); // Absolute value of price difference
    }
}
