// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// Importing required interfaces and security features from OpenZeppelin library
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// Interface for interacting with Uniswap V3 pool
interface IUniswapV3Pool {
    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol);
}

// Defining the pepeDex contract
contract pepeDex is ReentrancyGuard {
    using SafeMath for uint256;

    // State variables
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
    uint256 public constant TWAP_PERIOD = 5 minutes; // TWAP period set to 5 minutes
    uint256 public constant MINIMUM_TIME_BETWEEN_SWAPS = 3 minutes; // Minimum time between swaps by a user

    address public uniswapPool;

    // Variables for TWAP calculation
    uint256 public lastPrice;
    uint256 public lastPriceUpdateTime;

    // Tracks the last swap time of each user
    mapping(address => uint256) public lastSwapTime;

    // Events
    event Swapped(address indexed user, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed user, uint256 amountETH, uint256 amountToken);
    event LiquidityRemoved(address indexed user, uint256 amountETH, uint256 amountToken);
    event FeesClaimed(address indexed user, uint256 amount);

    // Constructor initializes the contract
    constructor(IERC20 _token, address _uniswapPool) {
        token = _token;
        uniswapPool = _uniswapPool;
    }

    // Fetches the latest price from Uniswap
    function getLatestPrice() public view returns (uint256) {
        IUniswapV3Pool pool = IUniswapV3Pool(uniswapPool);
        (uint160 sqrtPriceX96, , , , , ) = pool.slot0();
        uint256 price = uint256(sqrtPriceX96);
        price = price.mul(price).mul(1e18).div(1 << 192).div(1 << 192);
        return price;
    }

    // Calculates the Time-Weighted Average Price (TWAP)
    function getTwapPrice() public view returns (uint256) {
        uint256 currentTime = block.timestamp;
        uint256 timeElapsed = currentTime.sub(lastPriceUpdateTime);
        uint256 currentPrice = getLatestPrice();
        if (timeElapsed > TWAP_PERIOD) {
            timeElapsed = TWAP_PERIOD;
        }
        return (lastPrice.mul(TWAP_PERIOD.sub(timeElapsed)).add(currentPrice.mul(timeElapsed))).div(TWAP_PERIOD);
    }

    // Internal function to update the TWAP
    function updateTwap() internal {
        lastPrice = getLatestPrice();
        lastPriceUpdateTime = block.timestamp;
    }

    // Allows users to add liquidity to the pool
    function addLiquidity(uint256 amountToken) external payable nonReentrant {
        uint256 ethAmount = msg.value;
        require(amountToken > 0, "Token amount should be greater than 0");
        require(ethAmount > 0, "ETH amount should be greater than 0");

        uint256 liquidityAmount = (ethAmount.mul(totalLiquidity)).div(reserves.reserveETH).add(1);

        liquidityBalance[msg.sender] = liquidityBalance[msg.sender].add(liquidityAmount);
        totalLiquidity = totalLiquidity.add(liquidityAmount);
        reserves.reserveETH = reserves.reserveETH.add(ethAmount);
        reserves.reserveToken = reserves.reserveToken.add(amountToken);

        token.transferFrom(msg.sender, address(this), amountToken);

        // Update TWAP after liquidity is added
        updateTwap();

        emit LiquidityAdded(msg.sender, ethAmount, amountToken);
    }

// Allows users to swap ETH for tokens
function swap(uint256 amountIn, uint256 amountOutMin, uint256 /* maxSlippage */, uint256 /* maxTwapDeviation */, uint256 deadline) external payable nonReentrant {
    // Ensure that the transaction is not expired
    require(block.timestamp <= deadline, "Transaction expired");

    // Rate limiting: Ensure that the user cannot swap too frequently
    require(block.timestamp >= lastSwapTime[msg.sender] + MINIMUM_TIME_BETWEEN_SWAPS, "Swap too soon");

    uint256 amountOut = getAmountOut(amountIn);
    require(amountOut >= amountOutMin, "Slippage tolerance exceeded");

    reserves.reserveToken -= amountOut;
    reserves.reserveETH += amountIn;

    // Update the last swap time for the user
    lastSwapTime[msg.sender] = block.timestamp;

    // Update TWAP after swap
    updateTwap();

    emit Swapped(msg.sender, amountIn, amountOut);
}

    // Calculates the amount of tokens a user receives for a given amount of ETH
    function getAmountOut(uint256 amountIn) internal view returns (uint256) {
        uint256 amountInWithFee = amountIn.mul(1000 - FEE_PERCENTAGE);
        uint256 numerator = amountInWithFee.mul(reserves.reserveETH);
        uint256 denominator = reserves.reserveToken.mul(1000).add(amountInWithFee);
        return numerator.div(denominator);
    }

    // Allows users to remove liquidity
    function removeLiquidity(uint256 liquidityAmount) external nonReentrant {
        require(liquidityBalance[msg.sender] >= liquidityAmount, "Not enough liquidity");

        uint256 ethAmount = (reserves.reserveETH.mul(liquidityAmount)).div(totalLiquidity);
        uint256 tokenAmount = (reserves.reserveToken.mul(liquidityAmount)).div(totalLiquidity);

        reserves.reserveETH = reserves.reserveETH.sub(ethAmount);
        reserves.reserveToken = reserves.reserveToken.sub(tokenAmount);
        liquidityBalance[msg.sender] = liquidityBalance[msg.sender].sub(liquidityAmount);
        totalLiquidity = totalLiquidity.sub(liquidityAmount);

        payable(msg.sender).transfer(ethAmount);
        token.transfer(msg.sender, tokenAmount);

        // Update TWAP after liquidity is removed
        updateTwap();

        emit LiquidityRemoved(msg.sender, ethAmount, tokenAmount);
    }

    // Allows liquidity providers to claim fees
    function claimFees() external nonReentrant {
        uint256 newAccumulatedFees = accumulatedFees.mul(liquidityBalance[msg.sender]).div(totalLiquidity);
        uint256 feesToClaim = newAccumulatedFees.sub(lastAccumulatedFees[msg.sender]);

        require(feesToClaim > 0, "No fees to claim");

        lastAccumulatedFees[msg.sender] = newAccumulatedFees;
        reserves.reserveETH = reserves.reserveETH.sub(feesToClaim);

        payable(msg.sender).transfer(feesToClaim);

        emit FeesClaimed(msg.sender, feesToClaim);
    }

    // Fallback function to accept ETH
    receive() external payable {}

    // Helper function to ensure slippage and TWAP deviation are within limits
    function validateSwap(uint256 amountIn, uint256 amountOut, uint8 maxSlippage, uint256 maxTwapDeviation) internal view {
        uint256 amountOutExpected = getAmountOut(amountIn);
        uint256 amountOutMinimum = amountOutExpected.mul(1000 - maxSlippage).div(1000);

        require(amountOut >= amountOutMinimum, "Slippage tolerance exceeded");

        uint256 currentTwap = getTwapPrice();
        uint256 deviation = (lastPrice > currentTwap) ? lastPrice.sub(currentTwap) : currentTwap.sub(lastPrice);

        require(deviation <= maxTwapDeviation, "TWAP deviation exceeded");
    }
}
