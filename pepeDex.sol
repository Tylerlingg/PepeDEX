// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
    AggregatorV3Interface internal priceFeed;

    event Swapped(address indexed user, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed user, uint256 amountETH, uint256 amountToken);
    event LiquidityRemoved(address indexed user, uint256 amountETH, uint256 amountToken);
    event FeesClaimed(address indexed user, uint256 amount);

    /**
     * @dev Constructor sets the token and Chainlink oracle.
     * @param _token The address of the ERC20 token.
     */
    constructor(IERC20 _token) {
        token = _token;
        priceFeed = AggregatorV3Interface(0x9326BFA02ADD2366b30bacB125260Af641031331);
    }

    /**
     * @dev Add liquidity to the pool.
     * @param amountToken The amount of tokens to add as liquidity.
     */
    function addLiquidity(uint256 amountToken) external payable nonReentrant {
        uint256 ethSent = msg.value;
        require(amountToken > 0 && ethSent > 0, "Cannot add zero liquidity");

        uint256 liquidity = ethSent;
        if (totalLiquidity != 0) {
            int latestPrice = getLatestPrice();
            liquidity = uint256(latestPrice) * amountToken * 1e18 / reserves.reserveToken;
        }

        totalLiquidity += liquidity;
        liquidityBalance[msg.sender] += liquidity;
        reserves.reserveETH += ethSent;
        reserves.reserveToken += amountToken;

        require(token.transferFrom(msg.sender, address(this), amountToken), "Failed to transfer tokens");

        emit LiquidityAdded(msg.sender, ethSent, amountToken);
    }

    /**
     * @dev Retrieve the latest price from the Chainlink oracle.
     * @return The latest price.
     */
    function getLatestPrice() public view returns (int) {
        (, int price, , , ) = priceFeed.latestRoundData();
        return price;
    }

    /**
     * @dev Remove liquidity from the pool.
     * @param liquidity The amount of liquidity to remove.
     */
    function removeLiquidity(uint256 liquidity) external nonReentrant {
        require(liquidity > 0 && liquidity <= liquidityBalance[msg.sender], "Invalid liquidity amount");

        uint256 amountETH = liquidity * reserves.reserveETH / totalLiquidity;
        uint256 amountToken = liquidity * reserves.reserveToken / totalLiquidity;
        require(amountETH > 0 && amountToken > 0, "Not enough liquidity");

        reserves.reserveETH-= amountETH;
        reserves.reserveToken -= amountToken;
        liquidityBalance[msg.sender] -= liquidity;
        totalLiquidity -= liquidity;

        require(token.transfer(msg.sender, amountToken), "Failed to transfer tokens from contract to sender");

        payable(msg.sender).transfer(amountETH);
        emit LiquidityRemoved(msg.sender, amountETH, amountToken);
    }

    /**
     * @dev Swap ETH for tokens.
     * @param amountIn Amount of tokens to swap in.
     * @param amountOutMin Minimum amount of ETH to receive.
     * @param maxSlippage Maximum slippage percentage.
     * @param deadline Transaction deadline timestamp.
     */
    function swap(uint256 amountIn, uint256 amountOutMin, uint256 maxSlippage, uint256 deadline) external nonReentrant {
    require(block.timestamp <= deadline, "Transaction expired");
    require(amountIn > 0 && amountOutMin > 0, "Invalid amounts");
    require(maxSlippage <= 100, "Maximum slippage percentage cannot be more than 100");
    require(token.allowance(msg.sender, address(this)) >= amountIn, "Token allowance too small");

    int latestPrice = getLatestPrice();
    uint256 scaleFactor = 1e18;

    uint256 amountOut = (uint256(latestPrice) * amountIn * scaleFactor) / (reserves.reserveToken) / scaleFactor;
    uint256 amountOutWithFee = amountOut * (100000 - FEE_PERCENTAGE) / 100000;
    require(amountOutWithFee >= amountOutMin, "Insufficient output amount");

    accumulatedFees += amountOut - amountOutWithFee;

    uint256 slippage = amountOutWithFee * maxSlippage / 100;
    require(amountOutWithFee - slippage <= amountOutMin, "Slippage too high");

    reserves.reserveToken += amountIn;
    reserves.reserveETH -= amountOutWithFee;

    require(token.transferFrom(msg.sender, address(this), amountIn), "Failed to transfer tokens from sender to contract");

    payable(msg.sender).transfer(amountOutWithFee);
    emit Swapped(msg.sender, amountIn, amountOutWithFee);
}


    /**
     * @dev Claims accumulated fees for the liquidity provider.
     */
    function claimFees() external nonReentrant {
        uint256 totalUnclaimedFees = accumulatedFees - lastAccumulatedFees[msg.sender];
        uint256 claimableFees = totalUnclaimedFees * liquidityBalance[msg.sender] / totalLiquidity;

        require(claimableFees > 0, "No fees to claim");

        lastAccumulatedFees[msg.sender] = accumulatedFees;

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
