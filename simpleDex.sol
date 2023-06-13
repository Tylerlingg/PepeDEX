// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SimpleTokenSwap is Ownable {
    using SafeMath for uint256;

    IERC20 public immutable token;
    uint256 public swapRate;
    uint256 public minimumSwapAmount;
    uint256 public maximumSwapAmount;

    event Swapped(address indexed user, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed user, uint256 amount);
    event SwapRateUpdated(uint256 newRate);

    constructor(IERC20 _token, uint256 _swapRate, uint256 _minimumSwapAmount, uint256 _maximumSwapAmount) {
        require(_swapRate > 0, "Swap rate must be greater than 0");
        require(_minimumSwapAmount < _maximumSwapAmount, "Minimum swap amount must be less than maximum swap amount");

        token = _token;
        swapRate = _swapRate;
        minimumSwapAmount = _minimumSwapAmount;
        maximumSwapAmount = _maximumSwapAmount;
    }

    function swap(uint256 amount) external {
        require(amount >= minimumSwapAmount, "Swap amount too low");
        require(amount <= maximumSwapAmount, "Swap amount too high");

        uint256 amountToSendBack = calculateSwap(amount);
        uint256 contractBalance = token.balanceOf(address(this));

        require(contractBalance >= amountToSendBack, "Not enough tokens in the contract for swap");
        require(token.transferFrom(msg.sender, address(this), amount), "Failed to transfer tokens from sender to contract");
        require(token.transfer(msg.sender, amountToSendBack), "Failed to transfer tokens from contract to sender");

        emit Swapped(msg.sender, amount, amountToSendBack);
    }

    function addLiquidity(uint256 amount) external {
        require(token.transferFrom(msg.sender, address(this), amount), "Failed to transfer tokens from sender to contract");
        emit LiquidityAdded(msg.sender, amount);
    }

    function updateSwapRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "New swap rate must be greater than 0");
        swapRate = newRate;
        emit SwapRateUpdated(newRate);
    }

    function calculateSwap(uint256 amount) internal view returns (uint256) {
        return amount.mul(swapRate);
    }
}
