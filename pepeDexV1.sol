// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IUniswapV3Pool {
    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol);
}

/**
 * @title pepeDex
 * @dev A simple automated market maker (AMM) that allows users to swap tokens, add liquidity, and remove liquidity.
 * Liquidity providers can also claim their share of accumulated fees.
 */
contract pepeDex is ReentrancyGuard {
    IERC20 public immutable token;
    mapping(address => uint256) public liquidityBalance;
    uint256 public totalLiquidity;
    uint256 public accumulatedFees;
    mapping(address => uint256) public lastAccumulatedFees;

    struct Reserves {
        uint256 reserveETH;
        uint256 reserveToken;
    }
    Reserves public reserves;

    uint256 public constant FEE_PERCENTAGE = 3; // Represents 0.3%

    address public uniswapPool;

    event Swapped(address indexed user, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed user, uint256 amountETH, uint256 amountToken);
    event LiquidityRemoved(address indexed user, uint256 amountETH, uint256 amountToken);
    event FeesClaimed(address indexed user, uint256 amount);

    /**
     * @dev Constructor sets the token and Uniswap pool.
     * @param _token The address of the ERC20 token.
     * @param _uniswapPool The address of the Uniswap V3 pool for Pepe/ETH.
     */
    constructor(IERC20 _token, address _uniswapPool) {
        token = _token;
        uniswapPool = _uniswapPool;
    }

    /**
     * @dev Retrieve the latest price from Uniswap V3.
     * @return The latest price.
     */
    function getLatestPrice() public view returns (uint256) {
        IUniswapV3Pool pool = IUniswapV3Pool(uniswapPool);
        (uint160 sqrtPriceX96, , , , , ) = pool.slot0();
        // The price is represented as the square root of the ratio between token amounts,
        // adjusted by a factor of 2^96. To get the price, square the value and scale it down.
        uint256 price = uint256(sqrtPriceX96);
        price = price * price * 1e18 / (1 << 192) / (1 << 192);
        return price;
    }

    /**
     * @dev Adds liquidity to the exchange.
     * @param amountToken Amount of tokens to add as liquidity.
     */
    function addLiquidity(uint256 amountToken) external payable nonReentrant {
        uint256 ethSent = msg.value;
        require(amountToken > 0 && ethSent > 0, "Cannot add zero liquidity");

        uint256 liquidity = ethSent;
        if (totalLiquidity != 0) {
            uint256 latestPrice = getLatestPrice();
            liquidity = latestPrice * amountToken * 1e18 / reserves.reserveToken;
        }

        totalLiquidity += liquidity;
        liquidityBalance[msg.sender] += liquidity;
        reserves.reserveETH += ethSent;
       reserves.reserveToken += amountToken;
        lastAccumulatedFees[msg.sender] = accumulatedFees * liquidity / totalLiquidity;

        token.transferFrom(msg.sender, address(this), amountToken);

        emit LiquidityAdded(msg.sender, ethSent, amountToken);
    }

    /**
     * @dev Removes liquidity from the exchange.
     * @param amountLiquidity Amount of liquidity to remove.
     */
    function removeLiquidity(uint256 amountLiquidity) external nonReentrant {
        require(amountLiquidity > 0 && liquidityBalance[msg.sender] >= amountLiquidity, "Invalid liquidity amount");

        uint256 ethAmount = reserves.reserveETH * amountLiquidity / totalLiquidity;
        uint256 tokenAmount = reserves.reserveToken * amountLiquidity / totalLiquidity;

        reserves.reserveETH -= ethAmount;
        reserves.reserveToken -= tokenAmount;
        liquidityBalance[msg.sender] -= amountLiquidity;
        totalLiquidity -= amountLiquidity;

        (bool ethSuccess,) = msg.sender.call{value: ethAmount}("");
        require(ethSuccess, "ETH transfer failed");
        token.transfer(msg.sender, tokenAmount);

        emit LiquidityRemoved(msg.sender, ethAmount, tokenAmount);
    }

    /**
     * @dev Swaps ETH for tokens.
     * @param amountOutMin Minimum amount of tokens expected to receive.
     * @param maxSlippage Maximum acceptable slippage in percentage points (e.g., 5 for 5%).
     */
    function swap(uint256 amountOutMin, uint256 maxSlippage) external payable nonReentrant {
        uint256 ethIn = msg.value;
        require(ethIn > 0, "Cannot swap zero ETH");

        uint256 amountOut = getAmountOut(ethIn);
        uint256 slippage = amountOut * maxSlippage / 1000; // maxSlippage is in percentage points scaled by 10 (e.g., 5 for 0.5%)
        uint256 amountOutWithSlippage = amountOut - slippage;
        require(amountOutWithSlippage >= amountOutMin, "Slippage too high");

        reserves.reserveETH += ethIn;
        reserves.reserveToken -= amountOut;
        accumulatedFees += ethIn * FEE_PERCENTAGE / 1000;

        token.transfer(msg.sender, amountOutWithSlippage);

        emit Swapped(msg.sender, ethIn, amountOutWithSlippage);
    }

    /**
     * @dev Claims the accumulated fees.
     */
    function claimFees() external nonReentrant {
        uint256 userLiquidity = liquidityBalance[msg.sender];
        require(userLiquidity > 0, "No liquidity provided");

        uint256 claimableFees = accumulatedFees * userLiquidity / totalLiquidity - lastAccumulatedFees[msg.sender];

        lastAccumulatedFees[msg.sender] = accumulatedFees * userLiquidity / totalLiquidity;

        token.transfer(msg.sender, claimableFees);

        emit FeesClaimed(msg.sender, claimableFees);
    }

    /**
     * @dev Calculates the amount of tokens that can be bought with a given amount of ETH.
     * @param amountIn Amount of ETH.
     * @return Amount of tokens.
     */
    function getAmountOut(uint256 amountIn) public view returns (uint256) {
        uint256 amountInWithFee = amountIn * (1000 - FEE_PERCENTAGE);
        uint256 numerator = amountInWithFee * reserves.reserveToken;
        uint256 denominator = reserves.reserveETH * 1000 + amountInWithFee;
        return numerator / denominator;
    }

    /**
     * @dev Reverts the transaction if the call is not successful.
     * Used as a low level call to implement transfer of ETH.
     * @param to Address to transfer ETH to.
     * @param value Amount of ETH to transfer.
     */
    function safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}("");
        require(success, "ETH transfer failed");
    }

    /**
     * @dev Function to allow contract to receive ETH.
     */
    receive() external payable {}
}
