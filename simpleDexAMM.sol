// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract SimpleAMM is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    IERC20 public immutable token;
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
        uint256 amountETH = msg.value;
        require(amountToken > 0 && amountETH > 0, "Cannot add zero liquidity");

        reserveETH = reserveETH.add(amountETH);
        reserveToken = reserveToken.add(amountToken);

        require(token.transferFrom(msg.sender, address(this), amountToken), "Failed to transfer tokens from sender to contract");
        emit LiquidityAdded(msg.sender, amountETH, amountToken);
    }

    function removeLiquidity(uint256 amountToken) external nonReentrant {
        require(amountToken > 0, "Cannot remove zero liquidity");
        uint256 amountETH = getAmountETHOut(amountToken);
        require(amountETH > 0, "Not enough liquidity");

        reserveETH = reserveETH.sub(amountETH);
        reserveToken = reserveToken.sub(amountToken);

        require(token.transfer(msg.sender, amountToken), "Failed to transfer tokens from contract to sender");
        payable(msg.sender).transfer(amountETH);
        emit LiquidityRemoved(msg.sender, amountETH, amountToken);
    }

    function swap(uint256 amountIn, uint256 maxSlippagePercentage) external payable nonReentrant {
        uint256 amountETHIn = msg.value;
        require(amountETHIn > 0 && amountIn > 0, "Cannot swap zero");
        require(maxSlippagePercentage <= MAX_SLIPPAGE_PERCENTAGE, "Slippage exceeds maximum acceptable percentage");

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

    function withdrawToken(IERC20 _token, uint256 amount) external onlyOwner {
        require(address(_token) != address(token), "Cannot withdraw Pepe tokens");
        require(_token.transfer(msg.sender, amount), "Failed to transfer tokens");
    }
}
