
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract SimpleAMM is ReentrancyGuard {
    using SafeMath for uint256;

    IERC20 public immutable token;
    mapping(address => uint256) public liquidityBalance;
    uint256 public reserveETH;
    uint256 public reserveToken;

    uint256 public constant MAX_SLIPPAGE_PERCENTAGE = 3; // Maximum acceptable slippage percentage

    event Swapped(address indexed user, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed user, uint256 amountETH, uint256 amountToken);
    event LiquidityRemoved(address indexed user, uint256 amountETH, uint256 amountToken);

    constructor(IERC20 _token) {
        token = _token;
    }

    function addLiquidity(uint256 amountToken) external payable nonReentrant {
        require(amountToken > 0 && msg.value > 0, "Cannot add zero liquidity");

        reserveETH = reserveETH.add(msg.value);
        reserveToken = reserveToken.add(amountToken);
        liquidityBalance[msg.sender] = liquidityBalance[msg.sender].add(amountToken);

        require(token.transferFrom(msg.sender, address(this), amountToken), "Failed to transfer tokens from sender to contract");
        emit LiquidityAdded(msg.sender, msg.value, amountToken);
    }

    function removeLiquidity(uint256 amountToken) external nonReentrant {
        require(amountToken > 0 && liquidityBalance[msg.sender] >= amountToken, "Cannot remove zero liquidity or liquidity that you did not add");
        uint256 amountETH = getAmountETHOut(amountToken);
        require(amountETH > 0, "Not enough liquidity");

        reserveETH = reserveETH.sub(amountETH);
        reserveToken = reserveToken.sub(amountToken);
        liquidityBalance[msg.sender] = liquidityBalance[msg.sender].sub(amountToken);

        require(token.transfer(msg.sender, amountToken), "Failed to transfer tokens from contract to sender");
        payable(msg.sender).transfer(amountETH);
        emit LiquidityRemoved(msg.sender, amountETH, amountToken);
    }

    function swap(uint256 amountIn, uint256 maxSlippagePercentage) external payable nonReentrant {
        require(amountIn > 0 && msg.value > 0, "Cannot swap zero");
        require(maxSlippagePercentage <= MAX_SLIPPAGE_PERCENTAGE, "Slippage exceeds maximum acceptable percentage");

        uint256 amountETHIn = msg.value;
        uint256 amountTokenOut = getAmountOut(amountETHIn);
        uint256 slippageAmount = amountTokenOut.mul(maxSlippagePercentage).div(100);
        require(amountTokenOut.sub(slippageAmount) <= reserveToken, "Not enough liquidity");

        reserveETH = reserveETH.add(amountETHIn);
        reserveToken = reserveToken.sub(amountTokenOut);

        require(token.transfer(msg.sender, amountTokenOut), "Failed to transfer tokens from contract to sender");
        emit Swapped(msg.sender, amountETHIn, amountTokenOut);
    }

    function getAmountOut(uint256 amountIn) public view returns (uint256) {
        require(reserveETH > 0 && reserveToken > 0, "Insufficient liquidity");
        return amountIn.mul(reserveToken).div(reserveETH); // Uniswap's pricing formula
    }

    function getAmountETHOut(uint256 amountToken) public view returns (uint256) {
        require(reserveETH > 0 && reserveToken > 0, "Insufficient liquidity");
        return amountToken.mul(reserveETH).div(reserveToken); // Reverse calculation for removing liquidity
    }
}
