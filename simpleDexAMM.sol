// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract SimpleAMM is ReentrancyGuard {
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
        emit LiquidityRemoved(msg.sender, amountETH, amountToken);
    }

    function swap(uint256 amountIn, uint256 maxSlippagePercentage, uint256 deadline) external payable nonReentrant {
        require(amountIn > 0 && msg.value > 0, "Cannot swap zero");
        require(maxSlippagePercentage <= MAX_SLIPPAGE_PERCENTAGE, "Slippage exceeds maximum acceptable percentage");
        require(block.timestamp <= deadline, "Transaction expired");

        uint256 amountETHIn = msg.value;
        uint256 amountTokenOut = amountETHIn.mul(reserveToken).div(reserveETH);
        uint256 slippage = amountTokenOut.mul(maxSlippagePercentage).div(100);
        require(amountIn >= amountTokenOut.sub(slippage), "Input amount too small due to slippage");

        reserveETH = reserveETH.add(amountETHIn);
        reserveToken = reserveToken.sub(amountTokenOut);

        require(token.transfer(msg.sender, amountTokenOut), "Failed to transfer tokens from contract to sender");
        emit Swapped(msg.sender, amountIn, amountTokenOut);
    }

    function getReserves() external view returns (uint256, uint256) {
        return (reserveETH, reserveToken);
    }

    function getLiquidity(address user) external view returns (uint256) {
        return liquidityBalance[user];
    }

    function getTotalLiquidity() external view returns (uint256) {
        return totalLiquidity;
    }

    function calculateOutgoingAmount(uint256 amountIn) external view returns (uint256) {
        return amountIn.mul(reserveToken).div(reserveETH);
    }
}
