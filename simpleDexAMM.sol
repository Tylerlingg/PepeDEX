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

    event Swapped(address indexed user, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed user, uint256 amountETH, uint256 amountToken);

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

    function swap(uint256 amountIn) external payable nonReentrant {
        uint256 amountETHIn = msg.value;
        require(amountETHIn > 0 && amountIn > 0, "Cannot swap zero");

        uint256 amountTokenOut = getAmountOut(amountETHIn);
        require(amountTokenOut <= reserveToken, "Not enough liquidity");

        reserveETH = reserveETH.add(amountETHIn);
        reserveToken = reserveToken.sub(amountTokenOut);

        require(token.transfer(msg.sender, amountTokenOut), "Failed to transfer tokens from contract to sender");
        emit Swapped(msg.sender, amountETHIn, amountTokenOut);
    }

    function getAmountOut(uint256 amountIn) public view returns (uint256) {
        return amountIn.mul(reserveToken).div(reserveETH); // Uniswap's pricing formula
    }
}
