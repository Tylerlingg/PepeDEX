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

    event SwapRateChanged(uint256 oldRate, uint256 newRate);
    event Swapped(address indexed user, uint256 amountIn, uint256 amountOut);
    event TokensWithdrawn(address account, uint256 amount, uint256 remainingBalance);

    constructor(IERC20 _token, uint256 _swapRate, uint256 _minimumSwapAmount, uint256 _maximumSwapAmount) {
        require(_swapRate > 0, "Swap rate must be greater than 0");
        require(_minimumSwapAmount < _maximumSwapAmount, "Minimum must be less than maximum");

        token = _token;
        swapRate = _swapRate;
        minimumSwapAmount = _minimumSwapAmount;
        maximumSwapAmount = _maximumSwapAmount;
    }

    function swap(uint256 amount) external whenNotPaused {
        require(amount >= minimumSwapAmount, "Amount too low");
        require(amount <= maximumSwapAmount, "Amount too high");

        uint256 amountToSendBack = calculateSwap(amount);
        require(token.balanceOf(address(this)) >= amountToSendBack, "Not enough tokens in contract");

        require(token.transferFrom(msg.sender, address(this), amount), "Transfer from sender failed");
        require(token.transfer(msg.sender, amountToSendBack), "Transfer to sender failed");

        emit Swapped(msg.sender, amount, amountToSendBack);
    }

    function calculateSwap(uint256 amount) internal view returns (uint256) {
        return amount.mul(swapRate);
    }

    function setSwapRate(uint256 _swapRate) external onlyOwner {
        require(_swapRate > 0, "Swap rate must be greater than 0");
        uint256 oldRate = swapRate;
        swapRate = _swapRate;

        emit SwapRateChanged(oldRate, _swapRate);
    }

    function setSwapLimits(uint256 _minimumSwapAmount, uint256 _maximumSwapAmount) external onlyOwner {
        require(_minimumSwapAmount < _maximumSwapAmount, "Minimum must be less than maximum");

        minimumSwapAmount = _minimumSwapAmount;
        maximumSwapAmount = _maximumSwapAmount;
    }

    function withdrawTokens(uint256 amount) external onlyOwner whenNotPaused {
        require(token.balanceOf(address(this)) >= amount, "Not enough tokens");

        require(token.transfer(owner(), amount), "Transfer failed");
        uint256 remainingBalance = token.balanceOf(address(this));
        
        emit TokensWithdrawn(msg.sender, amount, remainingBalance);
    }
}
