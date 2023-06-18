// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract pepeDex is ReentrancyGuard {
    IERC20 public immutable token; // ERC20 token that the contract will use
    mapping(address => uint256) public liquidityBalance; // Mapping to keep track of liquidity added by an address
    uint256 public totalLiquidity; // Total liquidity in the pool
    struct Reserves {
        uint256 reserveETH;
        uint256 reserveToken;
    }
    Reserves public reserves; // Reserves of ETH and tokens
    uint256 public constant MAX_SLIPPAGE_PERCENTAGE = 3; // Maximum acceptable slippage percentage
    uint256 public constant FEE_PERCENTAGE = 3; // 0.3% fee (basis points)
    AggregatorV3Interface internal priceFeed; // Chainlink price feed

    // Events to log important contract activities
    event Swapped(address indexed user, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed user, uint256 amountETH, uint256 amountToken);
    event LiquidityRemoved(address indexed user, uint256 amountETH, uint256 amountToken);
    event TransferFailed(address indexed from, address indexed to, uint256 amount);

    constructor(IERC20 _token) {
        token = _token;
        priceFeed = AggregatorV3Interface(0x9326BFA02ADD2366b30bacB125260Af641031331); // Replace this with the Chainlink oracle address for your token
    }

    // Add liquidity to the pool
    function addLiquidity(uint256 amountToken) external payable nonReentrant {
        require(amountToken > 0 && msg.value > 0, "Cannot add zero liquidity");
        require(token.allowance(msg.sender, address(this)) >= amountToken, "Token allowance too small");

        uint256 liquidity = msg.value;
        if (totalLiquidity != 0) {
            int latestPrice = getLatestPrice();
            liquidity = uint256(latestPrice) * amountToken * 1e18 / reserves.reserveToken;
        }

        totalLiquidity += liquidity;
        liquidityBalance[msg.sender] += liquidity;
        reserves.reserveETH += msg.value;
        reserves.reserveToken += amountToken;

        if (!token.transferFrom(msg.sender, address(this), amountToken)) {
            emit TransferFailed(msg.sender, address(this), amountToken);
            revert("Failed to transfer tokens from sender to contract");
        }

        emit LiquidityAdded(msg.sender, msg.value, amountToken);
    }

    // Get the latest price from Chainlink oracle
    function getLatestPrice() public view returns (int) {
        (
            uint80 roundID,
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price data from oracle");
        return price;
    }

    // Remove liquidity from the pool
    function removeLiquidity(uint256 liquidity) external nonReentrant {
        require(liquidity > 0 && liquidityBalance[msg.sender] >= liquidity, "Cannot remove zero liquidity or liquidity that you did not add");

        uint256 scaleFactor = 1e18; // scale factor to increase precision
        uint256 amountETH= (liquidity * reserves.reserveETH * scaleFactor) / totalLiquidity / scaleFactor;
        uint256 amountToken = (liquidity * reserves.reserveToken * scaleFactor) / totalLiquidity / scaleFactor;
        require(amountETH > 0 && amountToken > 0, "Not enough liquidity");

        reserves.reserveETH -= amountETH;
        reserves.reserveToken -= amountToken;
        liquidityBalance[msg.sender] -= liquidity;
        totalLiquidity -= liquidity;

        if (!token.transfer(msg.sender, amountToken)) {
            emit TransferFailed(address(this), msg.sender, amountToken);
            revert("Failed to transfer tokens from contract to sender");
        }

        payable(msg.sender).transfer(amountETH);
        emit LiquidityRemoved(msg.sender, amountETH, amountToken);
    }
    /**
     * @notice Allows a user to swap ETH for Tokens.
     * @param amountIn The amount of tokens the user expects to receive at minimum.
     * @param maxSlippagePercentage The maximum percentage of slippage the user is willing to tolerate.
     * @param deadline The latest timestamp the transaction is valid for.
     *
     * Slippage is the difference between the expected price of the trade and the price at which the trade is executed.
     * High slippage usually happens in illiquid markets. To protect yourself from unexpected price changes during
     * the execution of your trade, you can set a maximum acceptable slippage percentage. If the slippage exceeds
     * this percentage, the transaction will fail.
     * maxSlippagePercentage should be an integer value representing the percentage. For example, for a 1% slippage,
     * maxSlippagePercentage should be set to 1. The contract has a global maximum slippage percentage set by
     * MAX_SLIPPAGE_PERCENTAGE.
     */
    // Swap ETH for tokens
    function swap(uint256 amountIn, uint256 amountOutMin, uint256 deadline) external nonReentrant {
        require(block.timestamp <= deadline, "Transaction expired");
        require(amountIn > 0 && amountOutMin > 0, "Invalid amounts");
        require(token.allowance(msg.sender, address(this)) >= amountIn, "Token allowance too small");

        int latestPrice = getLatestPrice(); // Latest price from Chainlink Oracle

        uint256 scaleFactor = 1e18; // Scale factor to increase precision

        // Update the reserves first
        reserves.reserveToken += amountIn;
        reserves.reserveETH -= amountOutMin;

        // Calculate the amountOut based on updated reserves
        uint256 amountOut = (uint256(latestPrice) * amountIn * scaleFactor) / (reserves.reserveToken + amountIn) / scaleFactor;
        uint256 amountOutWithFee = amountOut * (10000 - FEE_PERCENTAGE) / 10000;
        require(amountOutWithFee >= amountOutMin, "Insufficient output amount");

        uint256 slippage = amountOutWithFee * MAX_SLIPPAGE_PERCENTAGE / 100;
        require(amountOutWithFee - slippage <= amountOutMin, "Slippage too high");

        if (!token.transferFrom(msg.sender, address(this), amountIn)) {
            emit TransferFailed(msg.sender, address(this), amountIn);
            revert("Failed to transfer tokens from sender to contract");
        }

        payable(msg.sender).transfer(amountOutWithFee);
        emit Swapped(msg.sender, amountIn, amountOutWithFee);
    }

    // Fallback function to prevent direct ETH transfer
    receive() external payable {
        require(msg.sender != tx.origin, "Cannot send ETH directly");
    }
}
