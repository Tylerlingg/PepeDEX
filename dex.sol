// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract SimpleTokenSwap is Ownable, Pausable {
    using SafeMath for uint256;

    IERC20 public token;
    uint256 public swapRate;
    uint256 public minimumSwapAmount;
    uint256 public maximumSwapAmount;

    event SwapRateChanged(address indexed changer, uint256 oldRate, uint256 newRate);
    event SwapLimitsChanged(address indexed changer, uint256 oldMinAmount, uint256 oldMaxAmount, uint256 newMinAmount, uint256 newMaxAmount);
    event Swapped(address indexed user, uint256 amountIn, uint256 amountOut);
    event TokensWithdrawn(address account, uint256 amount, uint256 remainingBalance);

    constructor(IERC20 _token, uint256 _swapRate, uint256 _minimumSwapAmount, uint256 _maximumSwapAmount) {
        require(_swapRate > 0, "Swap rate must be greater than 0");
        require(_minimumSwapAmount < _maximumSwapAmount, "Minimum swap amount must be less than maximum swap amount");

        token = _token;
        swapRate = _swapRate;
        minimumSwapAmount = _minimumSwapAmount;
        maximumSwapAmount = _maximumSwapAmount;
    }

    function swap(uint256 amount) external whenNotPaused {
        require(amount >= minimumSwapAmount, "Swap amount too low");
        require(amount <= maximumSwapAmount, "Swap amount too high");

        uint256 amountToSendBack = calculateSwap(amount);
        require(token.balanceOf(address(this)) >= amountToSendBack, "Not enough tokens in the contract for swap");

        require(token.transferFrom(msg.sender, address(this), amount), "Failed to transfer tokens from sender to contract");
        require(token.transfer(msg.sender, amountToSendBack), "Failed to transfer tokens from contract to sender");

        emit Swapped(msg.sender, amount, amountToSendBack);
    }

    function calculateSwap(uint256 amount) internal view returns (uint256) {
        return amount.mul(swapRate);
    }

    function setSwapRate(uint256 _swapRate) external onlyOwner {
        require(_swapRate > 0, "Swap rate must be greater than 0");
        uint256 oldRate = swapRate;
        swapRate = _swapRate;

        emit SwapRateChanged(msg.sender, oldRate, _swapRate);
    }

    function setSwapLimits(uint256 _minimumSwapAmount, uint256 _maximumSwapAmount) external onlyOwner {
        require(_minimumSwapAmount < _maximumSwapAmount, "Minimum swap amount must be less than maximum swap amount");

        uint256 oldMinAmount = minimumSwapAmount;
        uint256 oldMaxAmount = maximumSwapAmount;
        
        minimumSwapAmount = _minimumSwapAmount;
        maximumSwapAmount = _maximumSwapAmount;

        emit SwapLimitsChanged(msg.sender, oldMinAmount, oldMaxAmount, _minimumSwapAmount, _maximumSwapAmount);
    }

    function withdrawTokens(uint256 amount) external onlyOwner whenNotPaused {
        require(token.balanceOf(address(this)) >= amount, "Not enough tokens in the contract to withdraw");

        require(token.transfer(owner(), amount), "Failed to transfer tokens from contract to owner");
        uint256 remainingBalance = token.balanceOf(address(this));
        
        emit TokensWithdrawn(msg.sender, amount, remainingBalance);
    }
}
