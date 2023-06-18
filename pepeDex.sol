// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title SimpleAMM
 * @dev A simple automated market maker (AMM) that allows users to swap tokens, add liquidity, and remove liquidity.
 * The contract owner can also withdraw accumulated fees.
 */
contract SimpleAMM is ReentrancyGuard {
    IERC20 public immutable token;
    mapping(address => uint256) public liquidityBalance;
    uint256 public totalLiquidity;
    uint256 public accumulatedFees;

    struct Reserves {
        uint256 reserveETH;
        uint256 reserveToken;
    }
    Reserves public reserves;

    uint256 public constant FEE_PERCENTAGE = 3;
    AggregatorV3Interface internal priceFeed;

    address public owner;

    event Swapped(address indexed user, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed user, uint256 amountETH, uint256 amountToken);
    event LiquidityRemoved(address indexed user, uint256 amountETH, uint256 amountToken);
    event FeesWithdrawn(address indexed to, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "You are not the owner");
        _;
    }

    /**
     * @dev Constructor sets the token, owner and Chainlink oracle.
     * @param _token The address of the ERC20 token.
     */
    constructor(IERC20 _token) {
        token = _token;
        owner = msg.sender;
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
       (, , , int price, , , ) = priceFeed.latestRoundData();
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

        reserves.reserveETH -= amountETH;
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

        reserves.reserveToken += amountIn;
        reserves.reserveETH -= amountOutMin;

        uint256 amountOut = (uint256(latestPrice) * amountIn * scaleFactor) / (reserves.reserveToken + amountIn) / scaleFactor;
        uint256 amountOutWithFee = amountOut * (10000 - FEE_PERCENTAGE) / 10000;
        require(amountOutWithFee >= amountOutMin, "Insufficient output amount");

        accumulatedFees += amountOut - amountOutWithFee;

        uint256 slippage = amountOutWithFee * maxSlippage / 100;
        require(amountOutWithFee - slippage <= amountOutMin, "Slippage too high");

        require(token.transferFrom(msg.sender, address(this), amountIn), "Failed to transfer tokens from sender to contract");

        payable(msg.sender).transfer(amountOutWithFee);
        emit Swapped(msg.sender, amountIn, amountOutWithFee);
    }

    /**
     * @dev Withdraw accumulated fees (only owner).
     * @param to The address to send the fees to.
     * @param amount The amount of fees to withdraw.
     */
    function withdrawFees(address to, uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0 && amount <= accumulatedFees, "Invalid amount to withdraw");

        accumulatedFees -= amount;

        (bool success,) = to.call{value: amount}("");
        require(success, "Failed to transfer accumulated fees");

        emit FeesWithdrawn(to, amount);
    }

    /**
     * @dev Fallback function that accepts ETH.
     * This function is called when ETH is sent directly to the contract.
     * The ETH will be added to the contract's reserves.
     */
    receive()    external payable {
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
