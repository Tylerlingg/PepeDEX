// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract SimpleTokenSwap {
    using SafeMath for uint256;

    IERC20 public immutable token;
    AggregatorV3Interface internal priceFeed;
    uint256 public minimumSwapAmount;
    uint256 public maximumSwapAmount;

    event Swapped(address indexed user, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed user, uint256 amount);

    constructor(IERC20 _token, uint256 _minimumSwapAmount, uint256 _maximumSwapAmount, address _priceFeed) {
        require(_minimumSwapAmount < _maximumSwapAmount, "Minimum swap amount must be less than maximum swap amount");

        token = _token;
        priceFeed = AggregatorV3Interface(_priceFeed);
        minimumSwapAmount = _minimumSwapAmount;
        maximumSwapAmount = _maximumSwapAmount;
    }

    function swap(uint256 amount) external {
        require(amount >= minimumSwapAmount, "Swap amount too low");
        require(amount <= maximumSwapAmount, "Swap amount too high");

        uint256 contractBalance = token.balanceOf(address(this));
        uint256 swapRate = getLatestSwapRate();
        uint256 amountToSendBack = amount.mul(swapRate);

        require(token.transferFrom(msg.sender, address(this), amount), "Failed to transfer tokens from sender to contract");
        require(contractBalance >= amountToSendBack, "Not enough tokens in the contract for swap");

        require(token.transfer(msg.sender, amountToSendBack), "Failed to transfer tokens from contract to sender");

        emit Swapped(msg.sender, amount, amountToSendBack);
    }

    function addLiquidity(uint256 amount) external {
        require(token.transferFrom(msg.sender, address(this), amount), "Failed to transfer tokens from sender to contract");
        emit LiquidityAdded(msg.sender, amount);
    }

    function getLatestSwapRate() public view returns (uint256) {
        (,int price,,,) = priceFeed.latestRoundData();
        return uint256(price);
    }
}
