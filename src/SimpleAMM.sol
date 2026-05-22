// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "../src/libraries/Math.sol";

/**
 * @title SimpleAMM
 * @author FSTO
 *
 * @notice
 * A minimal constant product Automated Market Maker (AMM)
 * following the x * y = k invariant model similar to Uniswap V2.
 *
 * @dev
 * Features:
 * - Liquidity provisioning
 * - LP token minting/burning
 * - Constant product swaps
 * - 0.3% swap fee
 * - Slippage protection
 * - Reentrancy protection
 *
 * Security Notes:
 * - Fee-on-transfer tokens are NOT supported
 * - Owner can skim excess tokens
 * - Owner can manually sync reserves
 *
 * Mathematical Invariant:
 * reserveA * reserveB = k
 */
contract SimpleAMM is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when both token addresses are the same
    error SimpleAMM__IdenticalTokens();

    /// @notice Thrown when minted liquidity is below minimum threshold
    error SimpleAMM__InsufficientLiquidityMinted();

    /// @notice Thrown when user does not own enough LP shares
    error SimpleAMM__InsufficientLiquidityBalance();

    /// @notice Thrown when provided amount is zero
    error SimpleAMM__ZeroAmount();

    /// @notice Thrown when pool reserves are empty
    error SimpleAMM__InsufficientReserves();

    /// @notice Thrown when attempting to burn zero LP shares
    error SimpleAMM__ZeroShares();

    /// @notice Thrown when token address is invalid
    error SimpleAMM__InvalidToken();

    /// @notice Thrown when constant product invariant is violated
    error SimpleAMM__InvariantViolation();

    /// @notice Thrown when optimal token amount exceeds user input
    error SimpleAMM__OptimalAmountExceeded();

    /// @notice Thrown when output amount is below minimum
    error SimpleAMM__SlippageExceeded();

    /// @notice Thrown when tokenA amount is below minimum threshold
    error SimpleAMM__SlippageA();

    /// @notice Thrown when tokenB amount is below minimum threshold
    error SimpleAMM__SlippageB();

    /// @notice Thrown when initial liquidity ratio is too imbalanced
    error SimpleAMM__ImbalancedInitialDeposit();

    /// @notice Thrown when fee-on-transfer tokens are used
    error SimpleAMM__FeeOnTransferNotSupported();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice First token in the pair
    IERC20 public immutable tokenA;

    /// @notice Second token in the pair
    IERC20 public immutable tokenB;

    /// @notice Current reserve amount of tokenA
    uint256 public reserveA;

    /// @notice Current reserve amount of tokenB
    uint256 public reserveB;

    /// @dev Maximum allowed imbalance ratio for first liquidity deposit
    uint256 private constant MAX_RATIO = 10;

    /// @dev Permanently locked liquidity to prevent division-by-zero attacks
    uint256 private constant MINIMUM_LIQUIDITY = 1_000;

    /// @dev Swap fee numerator (0.3%)
    uint256 private constant FEE_NUMERATOR = 997;

    /// @dev Swap fee denominator
    uint256 private constant FEE_DENOMINATOR = 1000;

    /// @dev Burn address used for permanently locked liquidity
    address private constant BURN_ADDRESS = address(0xdead);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when liquidity is added
     * @param user Address providing liquidity
     * @param amountA Amount of tokenA deposited
     * @param amountB Amount of tokenB deposited
     * @param shares LP shares minted
     */
    event LiquidityAdded(address indexed user, uint256 amountA, uint256 amountB, uint256 shares);

    /**
     * @notice Emitted when liquidity is removed
     * @param user Address removing liquidity
     * @param amountA Amount of tokenA withdrawn
     * @param amountB Amount of tokenB withdrawn
     * @param shares LP shares burned
     */
    event LiquidityRemoved(address indexed user, uint256 amountA, uint256 amountB, uint256 shares);

    /**
     * @notice Emitted after a successful swap
     * @param user Address performing the swap
     * @param tokenIn Input token address
     * @param amountIn Actual amount received
     * @param tokenOut Output token address
     * @param amountOut Amount sent to user
     * @param reserveA Updated reserveA
     * @param reserveB Updated reserveB
     */
    event Swap(
        address indexed user,
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOut,
        uint256 reserveA,
        uint256 reserveB
    );

    /**
     * @notice Emitted when excess tokens are skimmed
     * @param to Recipient address
     * @param excessA Excess tokenA transferred
     * @param excessB Excess tokenB transferred
     */
    event Skim(address indexed to, uint256 excessA, uint256 excessB);

    /**
     * @notice Emitted when reserves are manually synced
     * @param reserveA Updated reserveA
     * @param reserveB Updated reserveB
     */
    event Sync(uint256 reserveA, uint256 reserveB);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the AMM pair
     * @param _tokenA Address of tokenA
     * @param _tokenB Address of tokenB
     */
    constructor(address _tokenA, address _tokenB) ERC20("LP Token", "LPT") Ownable(msg.sender) {
        // Prevent identical token pairs
        if (_tokenA == _tokenB) {
            revert SimpleAMM__IdenticalTokens();
        }

        // Prevent zero address tokens
        if (_tokenA == address(0) || _tokenB == address(0)) {
            revert SimpleAMM__InvalidToken();
        }

        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }

    /*//////////////////////////////////////////////////////////////
                                 EXTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds liquidity to the AMM
     *
     * @dev
     * User supplies desired amounts and contract calculates
     * optimal amounts based on current reserve ratio.
     *
     * LP shares are minted proportionally.
     *
     * @param amountADesired Desired amount of tokenA
     * @param amountBDesired Desired amount of tokenB
     * @param amountAMin Minimum acceptable amount of tokenA
     * @param amountBMin Minimum acceptable amount of tokenB
     *
     * @return amountA Actual tokenA deposited
     * @return amountB Actual tokenB deposited
     * @return shares LP shares minted
     */
    function addLiquidity(uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin)
        external
        nonReentrant
        returns (uint256 amountA, uint256 amountB, uint256 shares)
    {
        if (amountADesired == 0 || amountBDesired == 0) {
            revert SimpleAMM__ZeroAmount();
        }

        // Cache reserves to reduce storage reads
        uint256 _reserveA = reserveA;
        uint256 _reserveB = reserveB;

        // Calculate optimal liquidity amounts
        (amountA, amountB) = _getOptimalAmounts(amountADesired, amountBDesired);

        // Slippage protection checks
        if (amountA < amountAMin) {
            revert SimpleAMM__SlippageA();
        }

        if (amountB < amountBMin) {
            revert SimpleAMM__SlippageB();
        }

        // Transfer liquidity tokens into pool
        tokenA.safeTransferFrom(msg.sender, address(this), amountA);

        tokenB.safeTransferFrom(msg.sender, address(this), amountB);

        // Mint LP shares
        shares = _mintShares(amountA, amountB, _reserveA, _reserveB);

        // Read updated balances
        uint256 balanceA = tokenA.balanceOf(address(this));

        uint256 balanceB = tokenB.balanceOf(address(this));

        // Update reserves
        _update(balanceA, balanceB);

        emit LiquidityAdded(msg.sender, amountA, amountB, shares);
    }

    /**
     * @notice Removes liquidity from the AMM
     *
     * @param shares Amount of LP shares to burn
     * @param amountAMin Minimum acceptable tokenA amount
     * @param amountBMin Minimum acceptable tokenB amount
     *
     * @return amountA Amount of tokenA returned
     * @return amountB Amount of tokenB returned
     */
    function removeLiquidity(uint256 shares, uint256 amountAMin, uint256 amountBMin)
        external
        nonReentrant
        returns (uint256 amountA, uint256 amountB)
    {
        if (shares == 0) {
            revert SimpleAMM__ZeroShares();
        }

        if (balanceOf(msg.sender) < shares) {
            revert SimpleAMM__InsufficientLiquidityBalance();
        }

        uint256 supply = totalSupply();

        // Calculate proportional withdrawal amounts
        amountA = (shares * reserveA) / supply;
        amountB = (shares * reserveB) / supply;

        // Slippage checks
        if (amountA < amountAMin) {
            revert SimpleAMM__SlippageA();
        }

        if (amountB < amountBMin) {
            revert SimpleAMM__SlippageB();
        }

        // Burn LP tokens
        _burn(msg.sender, shares);

        // Transfer underlying assets back to user
        tokenA.safeTransfer(msg.sender, amountA);
        tokenB.safeTransfer(msg.sender, amountB);

        // Fetch updated balances
        uint256 balanceA = tokenA.balanceOf(address(this));

        uint256 balanceB = tokenB.balanceOf(address(this));

        // Update reserves
        _update(balanceA, balanceB);

        emit LiquidityRemoved(msg.sender, amountA, amountB, shares);
    }

    /**
     * @notice Swaps tokenIn for the opposite token
     *
     * @dev
     * Uses constant product formula:
     * x * y = k
     *
     * Includes:
     * - 0.3% swap fee
     * - invariant enforcement
     * - slippage protection
     *
     * @param tokenIn Address of input token
     * @param amountIn Amount of tokenIn sent
     * @param amountOutMin Minimum acceptable output amount
     *
     * @return amountOut Amount of output token received
     */
    function swap(address tokenIn, uint256 amountIn, uint256 amountOutMin)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        // Validate token
        if (tokenIn != address(tokenA) && tokenIn != address(tokenB)) {
            revert SimpleAMM__InvalidToken();
        }

        if (amountIn == 0) {
            revert SimpleAMM__ZeroAmount();
        }

        // Cache reserves
        uint256 _reserveA = reserveA;
        uint256 _reserveB = reserveB;

        bool isA = tokenIn == address(tokenA);

        // Determine input/output tokens and reserves
        (IERC20 tIn, IERC20 tOut, uint256 rIn, uint256 rOut) =
            isA ? (tokenA, tokenB, _reserveA, _reserveB) : (tokenB, tokenA, _reserveB, _reserveA);

        if (rIn == 0 || rOut == 0) {
            revert SimpleAMM__InsufficientReserves();
        }

        // Record balance before transfer
        uint256 balanceBefore = tIn.balanceOf(address(this));

        // Pull tokens from user
        tIn.safeTransferFrom(msg.sender, address(this), amountIn);

        // Record balance after transfer
        uint256 balanceAfter = tIn.balanceOf(address(this));

        // Calculate actual amount received
        uint256 actualAmountIn = balanceAfter - balanceBefore;

        // Reject fee-on-transfer tokens
        if (actualAmountIn != amountIn) {
            revert SimpleAMM__FeeOnTransferNotSupported();
        }

        // Apply swap fee
        uint256 amountInWithFee = actualAmountIn * FEE_NUMERATOR;

        // Calculate output amount using AMM formula
        amountOut = (rOut * amountInWithFee) / (rIn * FEE_DENOMINATOR + amountInWithFee);

        // Slippage protection
        if (amountOut < amountOutMin) {
            revert SimpleAMM__SlippageExceeded();
        }

        // Transfer output token to user
        tOut.safeTransfer(msg.sender, amountOut);

        uint256 balanceA;
        uint256 balanceB;

        // Calculate new balances
        if (isA) {
            balanceA = rIn + actualAmountIn;
            balanceB = rOut - amountOut;
        } else {
            balanceA = rOut - amountOut;
            balanceB = rIn + actualAmountIn;
        }

        uint256 adjustedA;
        uint256 adjustedB;

        // Apply fee-adjusted invariant check
        if (isA) {
            adjustedA = balanceA * FEE_DENOMINATOR - (actualAmountIn * (FEE_DENOMINATOR - FEE_NUMERATOR));

            adjustedB = balanceB * FEE_DENOMINATOR;
        } else {
            adjustedA = balanceA * FEE_DENOMINATOR;

            adjustedB = balanceB * FEE_DENOMINATOR - (actualAmountIn * (FEE_DENOMINATOR - FEE_NUMERATOR));
        }

        // Ensure invariant is preserved
        if (adjustedA * adjustedB < _reserveA * _reserveB * (FEE_DENOMINATOR ** 2)) {
            revert SimpleAMM__InvariantViolation();
        }

        // Update reserves
        _update(balanceA, balanceB);

        emit Swap(msg.sender, address(tIn), actualAmountIn, address(tOut), amountOut, reserveA, reserveB);
    }

    /**
     * @notice Transfers excess tokens above reserves
     *
     * @dev
     * Excess tokens may exist because of:
     * - accidental transfers
     * - rebasing tokens
     * - direct token sends
     *
     * Only owner can recover them.
     *
     * @param to Recipient address
     */
    function skim(address to) external onlyOwner nonReentrant {
        if (to == address(0)) {
            revert SimpleAMM__InvalidToken();
        }

        // Calculate excess balances
        uint256 excessA = tokenA.balanceOf(address(this)) - reserveA;

        uint256 excessB = tokenB.balanceOf(address(this)) - reserveB;

        // Transfer excess tokens
        tokenA.safeTransfer(to, excessA);
        tokenB.safeTransfer(to, excessB);

        emit Skim(to, excessA, excessB);
    }

    /**
     * @notice Syncs reserves with actual token balances
     *
     * @dev
     * Useful if balances become inconsistent due to:
     * - accidental transfers
     * - rebasing tokens
     */
    function sync() external onlyOwner {
        uint256 balA = tokenA.balanceOf(address(this));

        uint256 balB = tokenB.balanceOf(address(this));

        _update(balA, balB);

        emit Sync(balA, balB);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns optimal liquidity amounts
     *
     * @param amountADesired Desired tokenA amount
     * @param amountBDesired Desired tokenB amount
     *
     * @return amountA Optimal tokenA amount
     * @return amountB Optimal tokenB amount
     */
    function getOptimalAmounts(uint256 amountADesired, uint256 amountBDesired)
        external
        view
        returns (uint256 amountA, uint256 amountB)
    {
        (amountA, amountB) = _getOptimalAmounts(amountADesired, amountBDesired);
    }

    /**
     * @notice Calculates output amount for a swap
     *
     * @param _tokenIn Address of input token
     * @param amountIn Amount of input token
     *
     * @return amountOut Estimated output amount
     */
    function getAmountOut(address _tokenIn, uint256 amountIn) external view returns (uint256 amountOut) {
        if (_tokenIn != address(tokenA) && _tokenIn != address(tokenB)) {
            revert SimpleAMM__InvalidToken();
        }

        if (amountIn == 0) {
            revert SimpleAMM__ZeroAmount();
        }

        bool isAtoB = (_tokenIn == address(tokenA));

        (uint256 rIn, uint256 rOut) = isAtoB ? (reserveA, reserveB) : (reserveB, reserveA);

        if (rIn == 0 || rOut == 0) {
            revert SimpleAMM__InsufficientReserves();
        }

        // Apply fee to amountIn
        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;

        // Calculate amountOut using AMM formula
        amountOut = (rOut * amountInWithFee) / (rIn * FEE_DENOMINATOR + amountInWithFee);
    }

    /*//////////////////////////////////////////////////////////////
                                 INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates optimal liquidity deposit amounts
     *
     * @dev
     * Maintains current reserve ratio for existing pools.
     *
     * For initial liquidity:
     * - prevents extremely imbalanced deposits
     *
     * @param amountADesired Desired tokenA amount
     * @param amountBDesired Desired tokenB amount
     *
     * @return amountA Optimal tokenA amount
     * @return amountB Optimal tokenB amount
     */
    function _getOptimalAmounts(uint256 amountADesired, uint256 amountBDesired)
        internal
        view
        returns (uint256 amountA, uint256 amountB)
    {
        if (amountADesired == 0 || amountBDesired == 0) {
            revert SimpleAMM__ZeroAmount();
        }

        // Initial liquidity case
        if (reserveA == 0 && reserveB == 0) {
            // Prevent extremely imbalanced first deposits
            if (amountADesired > amountBDesired * MAX_RATIO || amountBDesired > amountADesired * MAX_RATIO) {
                revert SimpleAMM__ImbalancedInitialDeposit();
            }

            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            // Calculate optimal tokenB amount
            uint256 amountBOptimal = (amountADesired * reserveB) / reserveA;

            // Use full tokenA amount and trim tokenB
            if (amountBOptimal <= amountBDesired) {
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                // Calculate optimal tokenA amount
                uint256 amountAOptimal = (amountBDesired * reserveA) / reserveB;

                if (amountAOptimal > amountADesired) {
                    revert SimpleAMM__OptimalAmountExceeded();
                }

                // Use full tokenB amount and trim tokenA
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    /**
     * @notice Mints LP shares for liquidity providers
     *
     * @dev
     * First liquidity provider:
     * - permanently locks MINIMUM_LIQUIDITY
     *
     * Existing liquidity:
     * - shares minted proportionally
     *
     * @param amountA Amount of tokenA deposited
     * @param amountB Amount of tokenB deposited
     * @param _reserveA Cached reserveA
     * @param _reserveB Cached reserveB
     *
     * @return shares Amount of LP shares minted
     */
    function _mintShares(uint256 amountA, uint256 amountB, uint256 _reserveA, uint256 _reserveB)
        internal
        returns (uint256 shares)
    {
        uint256 supply = totalSupply();

        // Initial liquidity case
        if (supply == 0) {
            // Geometric mean calculation
            uint256 liquidity = Math.sqrt(amountA * amountB);

            if (liquidity < MINIMUM_LIQUIDITY) {
                revert SimpleAMM__InsufficientLiquidityMinted();
            }

            // Lock minimum liquidity forever
            shares = liquidity - MINIMUM_LIQUIDITY;

            _mint(BURN_ADDRESS, MINIMUM_LIQUIDITY);
        } else {
            // Calculate shares from both assets
            uint256 sharesFromA = (amountA * supply) / _reserveA;

            uint256 sharesFromB = (amountB * supply) / _reserveB;

            // Mint minimum proportional shares
            shares = Math.min(sharesFromA, sharesFromB);

            if (shares == 0) {
                revert SimpleAMM__InsufficientLiquidityBalance();
            }
        }

        // Mint LP tokens to liquidity provider
        _mint(msg.sender, shares);
    }

    /*//////////////////////////////////////////////////////////////
                                 PRIVATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates AMM reserves
     *
     * @param balanceA New tokenA balance
     * @param balanceB New tokenB balance
     */
    function _update(uint256 balanceA, uint256 balanceB) private {
        reserveA = balanceA;
        reserveB = balanceB;
    }
}
