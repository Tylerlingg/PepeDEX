// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title pepeDex
 * @dev A simple decentralized exchange for swapping ERC20 tokens for ETH.
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

    // Interface for interacting with UniswapV3Pool
    interface IUniswapV3Pool {
        function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol);
    }

    /**
     * @dev Contract constructor initializes the token and Uniswap pool address.
     * @param _token Address of the ERC20 token.
     * @param _uniswapPool Address of the Uniswap pool.
     */
    constructor(IERC20 _token, address _uniswapPool) {
        token = _token;
        uniswapPool = _uniswapPool;
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

        require(token.transferFrom(msg.sender, address(this), amountToken), "Failed to transfer tokens");

        emit LiquidityAdded(msg.sender, ethSent, amountToken);
    }

    /**
     * @dev Gets the latest price of the token from the Uniswap pool.
     * @return Latest price of the token.
     */
    function getLatestPrice() public view returns (uint256) {
        IUniswapV3Pool pool = IUniswapV3Pool(uniswapPool);
        (uint160 sqrtPriceX96,,,) = pool.slot0();
        uint256 price = uint256(sqrtPriceX96);
        price = price * price * 1e18 / (1 << 192) / (1 << 192);
        return price;
    }

    /**
     * @dev Swaps tokens for ETH.
    * @param amountIn Amount of tokens to swap.
     * @param amountOutMin Minimum amount of ETH to receive.
     * @param maxSlippage Maximum slippage percentage allowed.
     * @param deadline Timestamp after which the transaction is invalid.
     */
    function swap(uint256 amountIn, uint256 amountOutMin, uint8 maxSlippage, uint256 deadline) external nonReentrant {
        require(block.timestamp <= deadline, "Transaction expired");
        require(amountIn > 0 && amountOutMin > 0, "Invalid amounts");
        require(maxSlippage <= 100, "Maximum slippage percentage cannot be more than 100");
        require(token.allowance(msg.sender, address(this)) >= amountIn, "Token allowance too small");

        uint256 latestPrice = getLatestPrice();
        uint256 scaleFactor = 1e18;

        // Calculate output amount based on input and reserves
        uint256 amountOut = (latestPrice * amountIn * scaleFactor) / (reserves.reserveToken) / scaleFactor;
        uint256 amountOutWithFee = amountOut * (100000 - FEE_PERCENTAGE) / 100000;
        require(amountOutWithFee >= amountOutMin, "Insufficient output amount");

        // Accumulate fees
        accumulatedFees += amountOut - amountOutWithFee;

        // Calculate slippage and ensure it is within the acceptable range
        uint256 slippage = amountOutWithFee * maxSlippage / 100;
        require(amountOutWithFee - slippage <= amountOutMin, "Slippage too high");

        // Update reserves
        reserves.reserveToken += amountIn;
        reserves.reserveETH -= amountOutWithFee;

        // Check if the contract has enough ETH to send
        require(reserves.reserveETH >= amountOutWithFee, "Not enough ETH in reserves");

        // Transfer tokens from sender to contract
        require(token.transferFrom(msg.sender, address(this), amountIn), "Failed to transfer tokens from sender to contract");

        // Transfer ETH to sender
        payable(msg.sender).transfer(amountOutWithFee);
        
        emit Swapped(msg.sender, amountIn, amountOutWithFee);
    }

    /**
     * @dev Allows liquidity providers to claim fees.
     */
    function claimFees() external nonReentrant {
        uint256 totalUnclaimedFees = accumulatedFees - lastAccumulatedFees[msg.sender];
        uint256 claimableFees = totalUnclaimedFees * liquidityBalance[msg.sender] / totalLiquidity;

        require(claimableFees > 0, "No fees to claim");

        // Update the last accumulated fees for the claimer
        lastAccumulatedFees[msg.sender] = accumulatedFees;

        // Transfer the claimable fees to the claimer
        (bool success,) = msg.sender.call{value: claimableFees}("");
        require(success, "Failed to transfer fees");

        emit FeesClaimed(msg.sender, claimableFees);
    }

    /**
     * @dev Fallback function that accepts ETH.
     * This function is called when ETH is sent directly to the contract.
     * The ETH will be added to the contract's reserves.
     */
    receive() external payable {
        require(msg.value > 0, "Cannot deposit zero ETH");
        reserves.reserveETH += msg.value;
    }

    /**
     * @dev This fallback function will be called if the receive() function is not present.
     * It can be used to log that the contract received ETH.
     */
    fallback() external payable {
        revert("Sending ETH directly is not supported, use addLiquidity function.");
    }
}
