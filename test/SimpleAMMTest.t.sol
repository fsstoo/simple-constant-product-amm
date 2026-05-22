// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {SimpleAMM} from "../src/SimpleAMM.sol";
import {Math} from "../src/libraries/Math.sol";

import {TokenA, TokenB} from "../src/TokenContracts.sol";
import {MockERC20, MockFeeOnTransferToken} from "./mocks/MockERC20.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SimpleAMMTest_Missing
 * @notice Covers all test cases absent from the original SimpleAMMTest suite.
 *
 * Sections
 * --------
 * 1.  Constructor
 * 2.  addLiquidity
 * 3.  removeLiquidity
 * 4.  swap
 * 5.  skim
 * 6.  sync
 * 7.  getAmountOut
 */

contract SimpleAMMTest is Test {
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    SimpleAMM internal simpleAMM;

    TokenA internal tokenA;
    TokenB internal tokenB;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    address internal constant BURN_ADDRESS = address(0xdead);

    uint256 internal constant MINIMUM_LIQUIDITY = 1_000;

    uint256 internal constant MAX_RATIO = 10;

    uint256 internal constant FEE_NUMERATOR = 997;
    uint256 internal constant FEE_DENOMINATOR = 1_000;

    uint256 internal constant USER_BALANCE = 10_000e18;

    uint256 internal constant INITIAL_LIQUIDITY = 100_000;
    uint256 internal constant DOUBLE_LIQUIDITY = 200_000;

    uint256 internal constant MEDIUM_AMOUNT = 10_000;
    uint256 internal constant LARGE_AMOUNT = 50_000;

    uint256 internal constant MIN_DEPOSIT = 1_001;
    uint256 internal constant MAX_DEPOSIT = 500_000;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        tokenA = new TokenA(address(this));
        tokenB = new TokenB(address(this));

        simpleAMM = new SimpleAMM(address(tokenA), address(tokenB));

        tokenA.mint(alice, USER_BALANCE);
        tokenB.mint(alice, USER_BALANCE);

        tokenA.mint(bob, USER_BALANCE);
        tokenB.mint(bob, USER_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _approveTokens(address user, uint256 amountA, uint256 amountB) internal {
        vm.startPrank(user);
        tokenA.approve(address(simpleAMM), amountA);
        tokenB.approve(address(simpleAMM), amountB);
        vm.stopPrank();
    }

    function _addLiquidity(address user, uint256 amountA, uint256 amountB)
        internal
        returns (uint256 usedA, uint256 usedB, uint256 shares)
    {
        _approveTokens(user, amountA, amountB);

        vm.prank(user);

        return simpleAMM.addLiquidity(amountA, amountB, amountA, amountB);
    }

    function _provideInitialLiquidity() internal {
        _addLiquidity(alice, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);
    }

    function _mintForFuzz(address user, uint256 amountA, uint256 amountB) internal {
        tokenA.mint(user, amountA);
        tokenB.mint(user, amountB);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function testConstructorInitializesCorrectly() public view {
        assertEq(address(simpleAMM.tokenA()), address(tokenA));
        assertEq(address(simpleAMM.tokenB()), address(tokenB));
    }

    function testConstructorRevertsIfIdenticalTokens() public {
        vm.expectRevert(SimpleAMM.SimpleAMM__IdenticalTokens.selector);
        new SimpleAMM(address(tokenA), address(tokenA));
    }

    function testConstructorRevertsIfTokenAIsZeroAddress() public {
        vm.expectRevert(SimpleAMM.SimpleAMM__InvalidToken.selector);
        new SimpleAMM(address(0), address(tokenB));
    }

    function testConstructorRevertsIfTokenBIsZeroAddress() public {
        vm.expectRevert(SimpleAMM.SimpleAMM__InvalidToken.selector);
        new SimpleAMM(address(tokenA), address(0));
    }

    function testConstructorSetsLPTokenNameAndSymbol() public view {
        assertEq(simpleAMM.name(), "LP Token");
        assertEq(simpleAMM.symbol(), "LPT");
    }

    function testConstructorReservesAreZero() public view {
        assertEq(simpleAMM.reserveA(), 0);
        assertEq(simpleAMM.reserveB(), 0);
    }

    function testConstructorOwnerIsDeployer() public view {
        assertEq(simpleAMM.owner(), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            ADD LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    function testFirstLPCanAddLiquidity() public {
        uint256 amountA = INITIAL_LIQUIDITY;
        uint256 amountB = INITIAL_LIQUIDITY;

        (uint256 usedA, uint256 usedB, uint256 shares) = _addLiquidity(alice, amountA, amountB);

        uint256 liquidity = Math.sqrt(amountA * amountB);

        assertEq(usedA, amountA);
        assertEq(usedB, amountB);

        assertEq(simpleAMM.reserveA(), amountA);
        assertEq(simpleAMM.reserveB(), amountB);

        assertEq(simpleAMM.totalSupply(), liquidity);
        assertEq(simpleAMM.balanceOf(alice), liquidity - MINIMUM_LIQUIDITY);
        assertEq(simpleAMM.balanceOf(BURN_ADDRESS), MINIMUM_LIQUIDITY);
        assertEq(shares, liquidity - MINIMUM_LIQUIDITY);
    }

    function testAddLiquidityRevertsIfAmountAIsZero() public {
        uint256 amountA = 0;
        uint256 amountB = INITIAL_LIQUIDITY;

        _approveTokens(alice, amountA, amountB);

        vm.prank(alice);
        vm.expectRevert(SimpleAMM.SimpleAMM__ZeroAmount.selector);
        simpleAMM.addLiquidity(amountA, amountB, amountA, amountB);
    }

    function testAddLiquidityRevertsIfAmountBIsZero() public {
        uint256 amountA = INITIAL_LIQUIDITY;
        uint256 amountB = 0;

        _approveTokens(alice, amountA, amountB);

        vm.prank(alice);
        vm.expectRevert(SimpleAMM.SimpleAMM__ZeroAmount.selector);
        simpleAMM.addLiquidity(amountA, amountB, amountA, amountB);
    }

    function testAddLiquidityRevertsIfImbalancedInitialDepositForAmountA() public {
        uint256 amountB = INITIAL_LIQUIDITY;
        uint256 amountA = INITIAL_LIQUIDITY + amountB * MAX_RATIO;

        _approveTokens(alice, amountA, amountB);

        vm.prank(alice);
        vm.expectRevert(SimpleAMM.SimpleAMM__ImbalancedInitialDeposit.selector);
        simpleAMM.addLiquidity(amountA, amountB, 0, 0);
    }

    function testAddLiquidityRevertsIfImbalancedInitialDepositForAmountB() public {
        uint256 amountA = INITIAL_LIQUIDITY;
        uint256 amountB = INITIAL_LIQUIDITY + amountA * MAX_RATIO;

        _approveTokens(alice, amountA, amountB);

        vm.prank(alice);
        vm.expectRevert(SimpleAMM.SimpleAMM__ImbalancedInitialDeposit.selector);
        simpleAMM.addLiquidity(amountA, amountB, 0, 0);
    }

    function testAddLiquidityAllowsExactMaxRatio() public {
        uint256 amountA = INITIAL_LIQUIDITY;
        uint256 amountB = amountA * MAX_RATIO;

        uint256 expectedLiquidity = Math.sqrt(amountA * amountB);

        _approveTokens(alice, amountA, amountB);

        vm.prank(alice);
        (uint256 usedA, uint256 usedB, uint256 shares) = simpleAMM.addLiquidity(amountA, amountB, 0, 0);

        assertEq(usedA, amountA);
        assertEq(usedB, amountB);

        assertEq(simpleAMM.reserveA(), amountA);
        assertEq(simpleAMM.reserveB(), amountB);

        assertEq(simpleAMM.totalSupply(), expectedLiquidity);
        assertEq(simpleAMM.balanceOf(alice), expectedLiquidity - MINIMUM_LIQUIDITY);
        assertEq(shares, expectedLiquidity - MINIMUM_LIQUIDITY);
    }

    function testAddLiquidityRevertsIfSlippageAExceeded() public {
        uint256 amountA = INITIAL_LIQUIDITY;
        uint256 amountB = INITIAL_LIQUIDITY;

        _approveTokens(alice, amountA, amountB);

        vm.prank(alice);
        vm.expectRevert(SimpleAMM.SimpleAMM__SlippageA.selector);
        simpleAMM.addLiquidity(amountA, amountB, amountA + 1, amountB);
    }

    function testAddLiquidityRevertsIfSlippageBExceeded() public {
        uint256 amountA = INITIAL_LIQUIDITY;
        uint256 amountB = INITIAL_LIQUIDITY;

        _approveTokens(alice, amountA, amountB);

        vm.prank(alice);
        vm.expectRevert(SimpleAMM.SimpleAMM__SlippageB.selector);
        simpleAMM.addLiquidity(amountA, amountB, amountA, amountB + 1);
    }

    function testAddLiquidityRevertsIfFirstDepositIsLessThanMinimumLiquidity() public {
        uint256 amountA = MINIMUM_LIQUIDITY - 1;
        uint256 amountB = MINIMUM_LIQUIDITY - 1;

        _approveTokens(alice, amountA, amountB);

        vm.prank(alice);

        vm.expectRevert(SimpleAMM.SimpleAMM__InsufficientLiquidityMinted.selector);
        simpleAMM.addLiquidity(amountA, amountB, amountA, amountB);
    }

    function testAddLiquidityRevertsIfInsufficientShares() public {
        _addLiquidity(alice, MEDIUM_AMOUNT, MEDIUM_AMOUNT + MEDIUM_AMOUNT / 2);

        uint256 amountA = 1;
        uint256 amountB = 1;

        _approveTokens(bob, amountA, amountB);

        vm.prank(bob);

        vm.expectRevert(SimpleAMM.SimpleAMM__InsufficientLiquidityBalance.selector);
        simpleAMM.addLiquidity(amountA, amountB, amountA, amountB);
    }

    function testAddLiquidityRevertsWithoutApproval() public {
        uint256 amountA = INITIAL_LIQUIDITY;
        uint256 amountB = INITIAL_LIQUIDITY;

        vm.prank(alice);
        vm.expectRevert(); //ERC20InsufficientAllowance
        simpleAMM.addLiquidity(amountA, amountB, amountA, amountB);
    }

    function testSecondLPCanAddLiquidity() public {
        _provideInitialLiquidity();

        uint256 reserveABefore = simpleAMM.reserveA();
        uint256 reserveBBefore = simpleAMM.reserveB();
        uint256 totalSupplyBefore = simpleAMM.totalSupply();

        uint256 amountADesired = INITIAL_LIQUIDITY;
        uint256 amountBDesired = INITIAL_LIQUIDITY + INITIAL_LIQUIDITY / 2; // 150_000

        (uint256 amountAOptimal, uint256 amountBOptimal) = simpleAMM.getOptimalAmounts(amountADesired, amountBDesired);

        _approveTokens(bob, amountAOptimal, amountBOptimal);

        vm.prank(bob);
        (uint256 amountAUsed, uint256 amountBUsed, uint256 shares) =
            simpleAMM.addLiquidity(amountADesired, amountBDesired, 0, 0);

        uint256 expectedShares = Math.min(
            (amountAUsed * totalSupplyBefore) / reserveABefore, (amountBUsed * totalSupplyBefore) / reserveBBefore
        );

        assertEq(shares, expectedShares);
        assertEq(amountAUsed, amountAOptimal);
        assertEq(amountBUsed, amountBOptimal);
        assertEq(simpleAMM.reserveA(), reserveABefore + amountAUsed);
        assertEq(simpleAMM.reserveB(), reserveBBefore + amountBUsed);
        assertEq(simpleAMM.totalSupply(), totalSupplyBefore + shares);
    }

    function testAddLiquidityTrimsTokenAWhenBIsLimitingFactor() public {
        // Pool ratio B/A = 2 : 1
        _addLiquidity(alice, INITIAL_LIQUIDITY, DOUBLE_LIQUIDITY);

        uint256 reserveABefore = simpleAMM.reserveA();
        uint256 reserveBBefore = simpleAMM.reserveB();

        uint256 amountADesired = MEDIUM_AMOUNT + LARGE_AMOUNT; // 60_000
        uint256 amountBDesired = INITIAL_LIQUIDITY; // 100_000 — the B limit

        // amountBOptimal = (60_000 * 200_000) / 100_000  = 120_000 > amountBDesired (100_000)
        // amountAOptimal = (100_000 * 100_000) / 200_000 = 50_000 < 60_000 (amountADesired)
        uint256 expectedA = (amountBDesired * reserveABefore) / reserveBBefore;
        uint256 expectedB = amountBDesired;

        _approveTokens(bob, amountADesired, amountBDesired);

        vm.prank(bob);
        (uint256 usedA, uint256 usedB,) = simpleAMM.addLiquidity(amountADesired, amountBDesired, 0, 0);

        assertEq(usedA, expectedA);
        assertEq(usedB, expectedB);
    }

    function testAddLiquidityTransfersTokensFromUser() public {
        uint256 amountA = INITIAL_LIQUIDITY;
        uint256 amountB = INITIAL_LIQUIDITY;

        uint256 aliceABefore = tokenA.balanceOf(alice);
        uint256 aliceBBefore = tokenB.balanceOf(alice);

        _addLiquidity(alice, amountA, amountB);

        assertEq(tokenA.balanceOf(alice), aliceABefore - amountA);
        assertEq(tokenB.balanceOf(alice), aliceBBefore - amountB);
    }

    function testAddLiquidityEmitsEvent() public {
        uint256 amountA = INITIAL_LIQUIDITY;
        uint256 amountB = INITIAL_LIQUIDITY;

        uint256 expectedShares = Math.sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;

        _approveTokens(alice, amountA, amountB);

        vm.expectEmit(true, false, false, true, address(simpleAMM));
        emit SimpleAMM.LiquidityAdded(alice, amountA, amountB, expectedShares);

        vm.prank(alice);
        simpleAMM.addLiquidity(amountA, amountB, amountA, amountB);
    }

    function testAddLiquidityExactRatioUsesFullAmounts() public {
        // Seed pool with ratio A:B = 1:2
        _addLiquidity(alice, INITIAL_LIQUIDITY, DOUBLE_LIQUIDITY);

        uint256 amountADesired = LARGE_AMOUNT; // 50_000
        uint256 amountBDesired = INITIAL_LIQUIDITY; // exact ratio

        _approveTokens(bob, amountADesired, amountBDesired);

        vm.prank(bob);
        (uint256 usedA, uint256 usedB,) = simpleAMM.addLiquidity(amountADesired, amountBDesired, 0, 0);

        assertEq(usedA, amountADesired);
        assertEq(usedB, amountBDesired);
    }

    /*//////////////////////////////////////////////////////////////
                        ADD LIQUIDITY — FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_AddLiquidityFirstDeposit(uint256 amountA, uint256 amountB) public {
        amountA = bound(amountA, MIN_DEPOSIT, MAX_DEPOSIT);
        // Keep within MAX_RATIO on both sides
        amountB = bound(amountB, amountA / MAX_RATIO + 1, amountA * MAX_RATIO);

        vm.assume(Math.sqrt(amountA * amountB) > MINIMUM_LIQUIDITY);

        _mintForFuzz(alice, amountA, amountB);

        (uint256 usedA, uint256 usedB, uint256 shares) = _addLiquidity(alice, amountA, amountB);

        uint256 expectedLiquidity = Math.sqrt(amountA * amountB);
        uint256 expectedShares = expectedLiquidity - MINIMUM_LIQUIDITY;

        assertEq(usedA, amountA);
        assertEq(usedB, amountB);
        assertEq(shares, expectedShares);
        assertEq(simpleAMM.totalSupply(), expectedLiquidity);
        assertEq(simpleAMM.balanceOf(BURN_ADDRESS), MINIMUM_LIQUIDITY);
        assertEq(simpleAMM.reserveA(), amountA);
        assertEq(simpleAMM.reserveB(), amountB);
    }

    function testFuzz_AddLiquidity_SubsequentDeposit(uint256 amountADesired, uint256 amountBDesired) public {
        _provideInitialLiquidity();

        amountADesired = bound(amountADesired, MIN_DEPOSIT, MAX_DEPOSIT);
        amountBDesired = bound(amountBDesired, MIN_DEPOSIT, MAX_DEPOSIT);

        _mintForFuzz(bob, amountADesired, amountBDesired);

        uint256 reserveABefore = simpleAMM.reserveA();
        uint256 reserveBBefore = simpleAMM.reserveB();
        uint256 totalSupplyBefore = simpleAMM.totalSupply();

        (uint256 optA, uint256 optB) = simpleAMM.getOptimalAmounts(amountADesired, amountBDesired);

        _approveTokens(bob, amountADesired, amountBDesired);
        vm.prank(bob);
        (uint256 usedA, uint256 usedB, uint256 shares) = simpleAMM.addLiquidity(amountADesired, amountBDesired, 0, 0);

        uint256 expectedShares =
            Math.min((usedA * totalSupplyBefore) / reserveABefore, (usedB * totalSupplyBefore) / reserveBBefore);

        assertEq(usedA, optA);
        assertEq(usedB, optB);
        assertEq(shares, expectedShares);
        assertEq(simpleAMM.reserveA(), reserveABefore + usedA);
        assertEq(simpleAMM.reserveB(), reserveBBefore + usedB);
    }

    function testFuzz_AddLiquiditySlippageReverts(uint256 amountADesired, uint256 amountBDesired) public {
        _provideInitialLiquidity();

        amountADesired = bound(amountADesired, MIN_DEPOSIT, MAX_DEPOSIT);
        amountBDesired = bound(amountBDesired, MIN_DEPOSIT, MAX_DEPOSIT);

        _mintForFuzz(alice, amountADesired, amountBDesired);

        (uint256 optA, uint256 optB) = simpleAMM.getOptimalAmounts(amountADesired, amountBDesired);

        _approveTokens(alice, amountADesired, amountBDesired);

        vm.startPrank(alice);
        if (optA < amountADesired) {
            vm.expectRevert(SimpleAMM.SimpleAMM__SlippageA.selector);
            simpleAMM.addLiquidity(amountADesired, amountBDesired, optA + 1, amountBDesired);
        } else {
            vm.expectRevert(SimpleAMM.SimpleAMM__SlippageB.selector);
            simpleAMM.addLiquidity(amountADesired, amountBDesired, amountADesired, optB + 1);
        }
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            REMOVE LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    function testUserCanRemoveLiquidity() public {
        (,, uint256 shares) = _addLiquidity(alice, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);

        uint256 totalSupplyBefore = simpleAMM.totalSupply();

        uint256 reserveABefore = simpleAMM.reserveA();
        uint256 reserveBBefore = simpleAMM.reserveB();

        uint256 expectedA = (shares * reserveABefore) / totalSupplyBefore;
        uint256 expectedB = (shares * reserveBBefore) / totalSupplyBefore;

        vm.prank(alice);
        (uint256 amountA, uint256 amountB) = simpleAMM.removeLiquidity(shares, expectedA, expectedB);

        assertEq(amountA, expectedA);
        assertEq(amountB, expectedB);

        assertEq(simpleAMM.balanceOf(alice), 0);
    }

    function testRemoveLiquidityTransfersTokensToUser() public {
        (,, uint256 shares) = _addLiquidity(alice, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);

        uint256 expectedA = (shares * simpleAMM.reserveA()) / simpleAMM.totalSupply();
        uint256 expectedB = (shares * simpleAMM.reserveB()) / simpleAMM.totalSupply();

        uint256 aliceABefore = tokenA.balanceOf(alice);
        uint256 aliceBBefore = tokenB.balanceOf(alice);

        vm.prank(alice);
        simpleAMM.removeLiquidity(shares, 0, 0);

        assertEq(tokenA.balanceOf(alice), aliceABefore + expectedA);
        assertEq(tokenB.balanceOf(alice), aliceBBefore + expectedB);
    }

    function testRemoveLiquidityRevertsIfZeroShares() public {
        _addLiquidity(alice, INITIAL_LIQUIDITY, DOUBLE_LIQUIDITY);

        vm.prank(bob);
        vm.expectRevert(SimpleAMM.SimpleAMM__ZeroShares.selector);
        simpleAMM.removeLiquidity(0, 0, 0);
    }

    function testRemoveLiquidityRevertsIfUserHasInsufficientLiquidityBalance() public {
        (,, uint256 shares) = _addLiquidity(bob, INITIAL_LIQUIDITY, DOUBLE_LIQUIDITY);

        // Bob tries to burn more than he owns
        vm.prank(bob);
        vm.expectRevert(SimpleAMM.SimpleAMM__InsufficientLiquidityBalance.selector);
        simpleAMM.removeLiquidity(shares + 1, 0, 0);
    }

    function testRemoveLiquidityRevertsIfSlippageAExceeded() public {
        (,, uint256 shares) = _addLiquidity(alice, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);

        uint256 amountA = (shares * simpleAMM.reserveA()) / simpleAMM.totalSupply();
        uint256 amountB = (shares * simpleAMM.reserveB()) / simpleAMM.totalSupply();

        vm.prank(alice);
        vm.expectRevert(SimpleAMM.SimpleAMM__SlippageA.selector);
        simpleAMM.removeLiquidity(shares, amountA + 1, amountB);
    }

    function testRemoveLiquidityRevertsIfSlippageBExceeded() public {
        (,, uint256 shares) = _addLiquidity(alice, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);

        uint256 amountA = (shares * simpleAMM.reserveA()) / simpleAMM.totalSupply();
        uint256 amountB = (shares * simpleAMM.reserveB()) / simpleAMM.totalSupply();

        vm.prank(alice);
        vm.expectRevert(SimpleAMM.SimpleAMM__SlippageB.selector);
        simpleAMM.removeLiquidity(shares, amountA, amountB + 1);
    }

    function testRemoveLiquidityUpdatesReservesCorrectly() public {
        (,, uint256 shares) = _addLiquidity(alice, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);

        uint256 totalSupplyBefore = simpleAMM.totalSupply();
        uint256 reserveABefore = simpleAMM.reserveA();
        uint256 reserveBBefore = simpleAMM.reserveB();

        uint256 expectedA = (shares * reserveABefore) / totalSupplyBefore;
        uint256 expectedB = (shares * reserveBBefore) / totalSupplyBefore;

        vm.prank(alice);
        simpleAMM.removeLiquidity(shares, 0, 0);

        assertEq(simpleAMM.reserveA(), reserveABefore - expectedA);
        assertEq(simpleAMM.reserveB(), reserveBBefore - expectedB);
        assertEq(simpleAMM.totalSupply(), totalSupplyBefore - shares);
    }

    function testRemoveLiquidityEmitsEvent() public {
        (,, uint256 shares) = _addLiquidity(alice, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);

        uint256 expectedA = (shares * simpleAMM.reserveA()) / simpleAMM.totalSupply();
        uint256 expectedB = (shares * simpleAMM.reserveB()) / simpleAMM.totalSupply();

        vm.expectEmit(true, false, false, true, address(simpleAMM));
        emit SimpleAMM.LiquidityRemoved(alice, expectedA, expectedB, shares);

        vm.prank(alice);
        simpleAMM.removeLiquidity(shares, expectedA, expectedB);
    }

    function testRemoveLiquidityFullExitLeavesBurnLiquidity() public {
        (,, uint256 shares) = _addLiquidity(alice, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);

        vm.prank(alice);
        simpleAMM.removeLiquidity(shares, 0, 0);

        assertEq(simpleAMM.totalSupply(), MINIMUM_LIQUIDITY);
        assertEq(simpleAMM.balanceOf(BURN_ADDRESS), MINIMUM_LIQUIDITY);
        assertEq(simpleAMM.balanceOf(alice), 0);
    }

    function testRemoveLiquidityTwoLPsProportional() public {
        (,, uint256 sharesAlice) = _addLiquidity(alice, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);
        (,, uint256 sharesBob) = _addLiquidity(bob, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);

        uint256 supply = simpleAMM.totalSupply();
        uint256 rA = simpleAMM.reserveA();
        uint256 rB = simpleAMM.reserveB();

        uint256 expectedAliceA = (sharesAlice * rA) / supply;
        uint256 expectedAliceB = (sharesAlice * rB) / supply;
        uint256 expectedBobA = (sharesBob * rA) / supply;
        uint256 expectedBobB = (sharesBob * rB) / supply;

        vm.prank(alice);
        (uint256 aliceA, uint256 aliceB) = simpleAMM.removeLiquidity(sharesAlice, expectedAliceA, expectedAliceB);

        vm.prank(bob);
        (uint256 bobA, uint256 bobB) = simpleAMM.removeLiquidity(sharesBob, expectedBobA, expectedBobB);

        assertEq(aliceA, expectedAliceA);
        assertEq(aliceB, expectedAliceB);
        assertEq(bobA, expectedBobA);
        assertEq(bobB, expectedBobB);
    }

    /*//////////////////////////////////////////////////////////////
                        REMOVE LIQUIDITY — FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_RemoveLiquidity(uint256 shareFraction) public {
        (,, uint256 totalShares) = _addLiquidity(alice, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);

        shareFraction = bound(shareFraction, 1, totalShares);

        uint256 supply = simpleAMM.totalSupply();
        uint256 reserveABefore = simpleAMM.reserveA();
        uint256 reserveBBefore = simpleAMM.reserveB();

        uint256 expectedA = (shareFraction * reserveABefore) / supply;
        uint256 expectedB = (shareFraction * reserveBBefore) / supply;

        vm.prank(alice);
        (uint256 amountA, uint256 amountB) = simpleAMM.removeLiquidity(shareFraction, expectedA, expectedB);

        assertEq(amountA, expectedA);
        assertEq(amountB, expectedB);
        assertEq(simpleAMM.reserveA(), reserveABefore - expectedA);
        assertEq(simpleAMM.reserveB(), reserveBBefore - expectedB);
        assertEq(simpleAMM.totalSupply(), supply - shareFraction);
    }

    function testFuzz_RemoveLiquiditySlippageReverts(uint256 shareFraction) public {
        (,, uint256 totalShares) = _addLiquidity(alice, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);

        shareFraction = bound(shareFraction, 1, totalShares);

        uint256 supply = simpleAMM.totalSupply();
        uint256 amountA = (shareFraction * simpleAMM.reserveA()) / supply;
        uint256 amountB = (shareFraction * simpleAMM.reserveB()) / supply;

        vm.startPrank(alice);
        if (shareFraction % 2 == 0) {
            vm.expectRevert(SimpleAMM.SimpleAMM__SlippageA.selector);
            simpleAMM.removeLiquidity(shareFraction, amountA + 1, amountB);
        } else {
            vm.expectRevert(SimpleAMM.SimpleAMM__SlippageB.selector);
            simpleAMM.removeLiquidity(shareFraction, amountA, amountB + 1);
        }
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                SWAP
    //////////////////////////////////////////////////////////////*/

    function testUserCanSwapAToB() public {
        _provideInitialLiquidity();

        uint256 amountIn = MEDIUM_AMOUNT;
        uint256 expectedOut = simpleAMM.getAmountOut(address(tokenA), amountIn);

        vm.startPrank(bob);
        tokenA.approve(address(simpleAMM), amountIn);

        simpleAMM.swap(address(tokenA), amountIn, expectedOut);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(bob), USER_BALANCE - amountIn);
        assertEq(tokenB.balanceOf(bob), USER_BALANCE + expectedOut);
    }

    function testUserCanSwapBToA() public {
        _provideInitialLiquidity();

        uint256 amountIn = MEDIUM_AMOUNT;
        uint256 expectedOut = simpleAMM.getAmountOut(address(tokenB), amountIn);

        vm.startPrank(bob);
        tokenB.approve(address(simpleAMM), amountIn);

        simpleAMM.swap(address(tokenB), amountIn, expectedOut);
        vm.stopPrank();

        assertEq(tokenB.balanceOf(bob), USER_BALANCE - amountIn);
        assertEq(tokenA.balanceOf(bob), USER_BALANCE + expectedOut);
    }

    function testSwapRevertsWithInvalidToken() public {
        _provideInitialLiquidity();

        MockERC20 invalidToken = new MockERC20("Mock", "MOCK");

        vm.expectRevert(SimpleAMM.SimpleAMM__InvalidToken.selector);
        simpleAMM.swap(address(invalidToken), MEDIUM_AMOUNT, 0);
    }

    function testSwapRevertsWithZeroAmount() public {
        _provideInitialLiquidity();

        vm.expectRevert(SimpleAMM.SimpleAMM__ZeroAmount.selector);
        simpleAMM.swap(address(tokenA), 0, 0);
    }

    function testSwapRevertsIfReservesEmpty() public {
        vm.expectRevert(SimpleAMM.SimpleAMM__InsufficientReserves.selector);
        simpleAMM.swap(address(tokenA), MEDIUM_AMOUNT, 0);
    }

    function testSwapRevertsIfFeeOnTransferToken() public {
        MockFeeOnTransferToken feeToken = new MockFeeOnTransferToken();

        SimpleAMM feeAMM = new SimpleAMM(address(feeToken), address(tokenB));

        feeToken.mint(alice, USER_BALANCE);
        tokenB.mint(alice, USER_BALANCE);

        vm.startPrank(alice);
        feeToken.approve(address(feeAMM), USER_BALANCE);
        tokenB.approve(address(feeAMM), USER_BALANCE);
        vm.stopPrank();

        deal(address(feeToken), address(feeAMM), INITIAL_LIQUIDITY);
        deal(address(tokenB), address(feeAMM), INITIAL_LIQUIDITY);
        vm.prank(feeAMM.owner());
        feeAMM.sync();

        uint256 amountIn = MEDIUM_AMOUNT;
        feeToken.mint(bob, amountIn);

        vm.startPrank(bob);
        feeToken.approve(address(feeAMM), amountIn);

        vm.expectRevert(SimpleAMM.SimpleAMM__FeeOnTransferNotSupported.selector);
        feeAMM.swap(address(feeToken), amountIn, 0);
        vm.stopPrank();
    }

    function testSwapRevertsIfSlippageExceeded() public {
        _provideInitialLiquidity();

        uint256 amountIn = MEDIUM_AMOUNT;
        uint256 expectedOut = simpleAMM.getAmountOut(address(tokenA), amountIn);

        _approveTokens(bob, amountIn, expectedOut);

        vm.prank(bob);
        vm.expectRevert(SimpleAMM.SimpleAMM__SlippageExceeded.selector);
        simpleAMM.swap(address(tokenA), amountIn, expectedOut + 1);
    }

    function testSwapRevertsWithoutApproval() public {
        _provideInitialLiquidity();

        uint256 amountIn = MEDIUM_AMOUNT;

        vm.prank(bob);
        vm.expectRevert(); //ERC20InsufficientAllowance
        simpleAMM.swap(address(tokenA), amountIn, 0);
    }

    function testSwapMaintainsInvariant() public {
        _provideInitialLiquidity();

        uint256 kBefore = simpleAMM.reserveA() * simpleAMM.reserveB();
        uint256 amountIn = MEDIUM_AMOUNT;
        uint256 expectedOut = simpleAMM.getAmountOut(address(tokenA), amountIn);

        _approveTokens(bob, amountIn, expectedOut);

        vm.prank(bob);
        simpleAMM.swap(address(tokenA), amountIn, expectedOut);

        uint256 kAfter = simpleAMM.reserveA() * simpleAMM.reserveB();

        // k should grow or stay the same due to the 0.3% fee
        assertGe(kAfter, kBefore);
    }

    function testSwapAForBUpdatesReservesCorrectly() public {
        _provideInitialLiquidity();

        uint256 reserveABefore = simpleAMM.reserveA();
        uint256 reserveBBefore = simpleAMM.reserveB();

        uint256 amountIn = MEDIUM_AMOUNT;
        uint256 amountOut = simpleAMM.getAmountOut(address(tokenA), amountIn);

        _approveTokens(bob, amountIn, amountOut);

        vm.prank(bob);
        simpleAMM.swap(address(tokenA), amountIn, amountOut);

        assertEq(simpleAMM.reserveA(), reserveABefore + amountIn);
        assertEq(simpleAMM.reserveB(), reserveBBefore - amountOut);
    }

    function testSwapBForAUpdatesReservesCorrectly() public {
        _provideInitialLiquidity();

        uint256 reserveABefore = simpleAMM.reserveA();
        uint256 reserveBBefore = simpleAMM.reserveB();

        uint256 amountIn = MEDIUM_AMOUNT;
        uint256 amountOut = simpleAMM.getAmountOut(address(tokenB), amountIn);

        vm.startPrank(bob);
        tokenB.approve(address(simpleAMM), amountIn);
        simpleAMM.swap(address(tokenB), amountIn, amountOut);
        vm.stopPrank();

        assertEq(simpleAMM.reserveB(), reserveBBefore + amountIn);
        assertEq(simpleAMM.reserveA(), reserveABefore - amountOut);
    }

    function testSwapEmitsEvent() public {
        _provideInitialLiquidity();

        uint256 amountIn = MEDIUM_AMOUNT;
        uint256 amountOut = simpleAMM.getAmountOut(address(tokenA), amountIn);

        _approveTokens(bob, amountIn, amountOut);

        vm.expectEmit(true, false, false, true, address(simpleAMM));
        emit SimpleAMM.Swap(
            bob,
            address(tokenA),
            amountIn,
            address(tokenB),
            amountOut,
            simpleAMM.reserveA() + amountIn,
            simpleAMM.reserveB() - amountOut
        );

        vm.prank(bob);
        simpleAMM.swap(address(tokenA), amountIn, amountOut);
    }

    function testSwapSucceedsWithZeroAmountOutMin() public {
        _provideInitialLiquidity();

        uint256 amountIn = MEDIUM_AMOUNT;

        _approveTokens(bob, amountIn, 0);
        vm.prank(bob);
        uint256 amountOut = simpleAMM.swap(address(tokenA), amountIn, 0);

        assertGt(amountOut, 0);
    }

    function testSwapLargeAmountDoesNotDrainPool() public {
        _provideInitialLiquidity();

        // Swap almost all of alice's tokenA supply
        uint256 amountIn = LARGE_AMOUNT + (LARGE_AMOUNT - MEDIUM_AMOUNT); // 90000
        uint256 amountOut = simpleAMM.getAmountOut(address(tokenA), amountIn);

        vm.startPrank(bob);
        tokenA.approve(address(simpleAMM), amountIn);
        simpleAMM.swap(address(tokenA), amountIn, amountOut);
        vm.stopPrank();

        // reserveB must still be positive
        assertGt(simpleAMM.reserveB(), 0);
        assertLt(amountOut, INITIAL_LIQUIDITY); // can never extract the full reserve
    }

    /*//////////////////////////////////////////////////////////////
                            SWAP — FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_SwapAtoBProducesCorrectOutput(uint256 amountIn) public {
        _addLiquidity(alice, DOUBLE_LIQUIDITY, DOUBLE_LIQUIDITY);

        amountIn = bound(amountIn, 1, DOUBLE_LIQUIDITY - INITIAL_LIQUIDITY);

        uint256 expectedOut = simpleAMM.getAmountOut(address(tokenA), amountIn);

        uint256 kBefore = simpleAMM.reserveA() * simpleAMM.reserveB();
        uint256 bobABefore = tokenA.balanceOf(bob);
        uint256 bobBBefore = tokenB.balanceOf(bob);

        tokenA.mint(bob, amountIn);

        vm.startPrank(bob);
        tokenA.approve(address(simpleAMM), amountIn);
        uint256 actualOut = simpleAMM.swap(address(tokenA), amountIn, expectedOut);
        vm.stopPrank();

        assertEq(actualOut, expectedOut);
        assertGt(simpleAMM.reserveB(), 0);
        assertGe(simpleAMM.reserveA() * simpleAMM.reserveB(), kBefore);
        assertEq(tokenA.balanceOf(bob), bobABefore);
        assertEq(tokenB.balanceOf(bob), bobBBefore + expectedOut);
    }

    function testFuzz_SwapBtoAProducesCorrectOutput(uint256 amountIn) public {
        _addLiquidity(alice, DOUBLE_LIQUIDITY, DOUBLE_LIQUIDITY);

        amountIn = bound(amountIn, 1, DOUBLE_LIQUIDITY - INITIAL_LIQUIDITY);

        uint256 expectedOut = simpleAMM.getAmountOut(address(tokenB), amountIn);

        uint256 kBefore = simpleAMM.reserveA() * simpleAMM.reserveB();
        uint256 bobABefore = tokenA.balanceOf(bob);
        uint256 bobBBefore = tokenB.balanceOf(bob);

        tokenB.mint(bob, amountIn);

        vm.startPrank(bob);
        tokenB.approve(address(simpleAMM), amountIn);
        uint256 actualOut = simpleAMM.swap(address(tokenB), amountIn, expectedOut);
        vm.stopPrank();

        assertEq(actualOut, expectedOut);
        assertGt(simpleAMM.reserveA(), 0);
        assertGe(simpleAMM.reserveA() * simpleAMM.reserveB(), kBefore);
        assertEq(tokenB.balanceOf(bob), bobBBefore); // minted then spent
        assertEq(tokenA.balanceOf(bob), bobABefore + expectedOut);
    }

    function testFuzzSwapSlippageReverts(uint256 amountIn) public {
        _addLiquidity(alice, DOUBLE_LIQUIDITY, DOUBLE_LIQUIDITY);

        amountIn = bound(amountIn, 1, DOUBLE_LIQUIDITY - INITIAL_LIQUIDITY);

        uint256 expectedOut = simpleAMM.getAmountOut(address(tokenA), amountIn);

        tokenA.mint(bob, amountIn);

        vm.startPrank(bob);
        tokenA.approve(address(simpleAMM), amountIn);
        vm.expectRevert(SimpleAMM.SimpleAMM__SlippageExceeded.selector);
        simpleAMM.swap(address(tokenA), amountIn, expectedOut + 1);
        vm.stopPrank();
    }

    function testFuzz_SwapInvariantNeverDecreases(uint256 amountIn1, uint256 amountIn2) public {
        _provideInitialLiquidity();

        amountIn1 = bound(amountIn1, 1, simpleAMM.reserveA() / 2);
        amountIn2 = bound(amountIn2, 1, simpleAMM.reserveB() / 2);

        uint256 kBefore = simpleAMM.reserveA() * simpleAMM.reserveB();

        tokenA.mint(bob, amountIn1);
        vm.startPrank(bob);
        tokenA.approve(address(simpleAMM), amountIn1);
        simpleAMM.swap(address(tokenA), amountIn1, 0);
        vm.stopPrank();

        uint256 kAfterFirst = simpleAMM.reserveA() * simpleAMM.reserveB();
        assertGe(kAfterFirst, kBefore);

        tokenB.mint(bob, amountIn2);
        vm.startPrank(bob);
        tokenB.approve(address(simpleAMM), amountIn2);
        simpleAMM.swap(address(tokenB), amountIn2, 0);
        vm.stopPrank();

        uint256 kAfterSecond = simpleAMM.reserveA() * simpleAMM.reserveB();
        assertGe(kAfterSecond, kAfterFirst);
    }

    /*//////////////////////////////////////////////////////////////
                                 SKIM
    //////////////////////////////////////////////////////////////*/

    function testOwnerCanSkim() public {
        _provideInitialLiquidity();

        uint256 excessA = INITIAL_LIQUIDITY / MEDIUM_AMOUNT;
        uint256 excessB = INITIAL_LIQUIDITY / LARGE_AMOUNT;

        // Simulate direct token transfers (accidental sends)
        tokenA.mint(address(simpleAMM), excessA);
        tokenB.mint(address(simpleAMM), excessB);

        uint256 ownerABefore = tokenA.balanceOf(address(this));
        uint256 ownerBBefore = tokenB.balanceOf(address(this));

        simpleAMM.skim(address(this));

        assertEq(tokenA.balanceOf(address(this)), ownerABefore + excessA);
        assertEq(tokenB.balanceOf(address(this)), ownerBBefore + excessB);
    }

    function testSkimRevertsForNonOwner() public {
        _provideInitialLiquidity();

        vm.prank(alice);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        simpleAMM.skim(alice);
    }

    function testSkimRevertsForZeroAddress() public {
        _provideInitialLiquidity();

        vm.expectRevert(SimpleAMM.SimpleAMM__InvalidToken.selector);
        simpleAMM.skim(address(0));
    }

    function testSkimEmitsEvent() public {
        _provideInitialLiquidity();

        uint256 excessA = INITIAL_LIQUIDITY / MEDIUM_AMOUNT + 20;
        uint256 excessB = INITIAL_LIQUIDITY / LARGE_AMOUNT + 20;

        tokenA.mint(address(simpleAMM), excessA);
        tokenB.mint(address(simpleAMM), excessB);

        vm.expectEmit(true, false, false, true, address(simpleAMM));
        emit SimpleAMM.Skim(address(this), excessA, excessB);

        simpleAMM.skim(address(this));
    }

    function testSkimDoesNotChangeReserves() public {
        _provideInitialLiquidity();

        uint256 reserveABefore = simpleAMM.reserveA();
        uint256 reserveBBefore = simpleAMM.reserveB();

        tokenA.mint(address(simpleAMM), INITIAL_LIQUIDITY / 20);
        tokenB.mint(address(simpleAMM), INITIAL_LIQUIDITY / 20);

        simpleAMM.skim(address(this));

        assertEq(simpleAMM.reserveA(), reserveABefore);
        assertEq(simpleAMM.reserveB(), reserveBBefore);
    }

    function testSkimNoOpWhenNoExcess() public {
        _provideInitialLiquidity();

        // No direct transfers — balances equal reserves exactly
        simpleAMM.skim(address(this)); // must not revert
    }

    /*//////////////////////////////////////////////////////////////
                             SKIM — FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Skim(uint256 excessA, uint256 excessB) public {
        _provideInitialLiquidity();

        excessA = bound(excessA, 0, MAX_DEPOSIT);
        excessB = bound(excessB, 0, MAX_DEPOSIT);

        tokenA.mint(address(simpleAMM), excessA);
        tokenB.mint(address(simpleAMM), excessB);

        uint256 reserveABefore = simpleAMM.reserveA();
        uint256 reserveBBefore = simpleAMM.reserveB();
        uint256 recipientABefore = tokenA.balanceOf(address(this));
        uint256 recipientBBefore = tokenB.balanceOf(address(this));

        simpleAMM.skim(address(this));

        assertEq(tokenA.balanceOf(address(this)), recipientABefore + excessA);
        assertEq(tokenB.balanceOf(address(this)), recipientBBefore + excessB);
        assertEq(simpleAMM.reserveA(), reserveABefore);
        assertEq(simpleAMM.reserveB(), reserveBBefore);
    }

    /*//////////////////////////////////////////////////////////////
                                 SYNC
    //////////////////////////////////////////////////////////////*/

    function testOwnerCanSync() public {
        _provideInitialLiquidity();

        uint256 extraA = INITIAL_LIQUIDITY / 14;
        uint256 extraB = INITIAL_LIQUIDITY / 25;

        tokenA.mint(address(simpleAMM), extraA);
        tokenB.mint(address(simpleAMM), extraB);

        uint256 expectedReserveA = simpleAMM.reserveA() + extraA;
        uint256 expectedReserveB = simpleAMM.reserveB() + extraB;

        simpleAMM.sync();

        assertEq(simpleAMM.reserveA(), expectedReserveA);
        assertEq(simpleAMM.reserveB(), expectedReserveB);
    }

    function testSyncRevertsForNonOwner() public {
        _provideInitialLiquidity();

        vm.prank(alice);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        simpleAMM.sync();
    }

    function testSyncEmitsEvent() public {
        _provideInitialLiquidity();

        uint256 extraA = INITIAL_LIQUIDITY / 200;
        tokenA.mint(address(simpleAMM), extraA);

        uint256 expectedReserveA = simpleAMM.reserveA() + extraA;
        uint256 expectedReserveB = simpleAMM.reserveB();

        vm.expectEmit(false, false, false, true, address(simpleAMM));
        emit SimpleAMM.Sync(expectedReserveA, expectedReserveB);

        simpleAMM.sync();
    }

    function testSyncNoOpWhenBalancesMatchReserves() public {
        _provideInitialLiquidity();

        uint256 reserveABefore = simpleAMM.reserveA();
        uint256 reserveBBefore = simpleAMM.reserveB();

        simpleAMM.sync(); // must not revert

        assertEq(simpleAMM.reserveA(), reserveABefore);
        assertEq(simpleAMM.reserveB(), reserveBBefore);
    }

    /*//////////////////////////////////////////////////////////////
                             SYNC — FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Sync(uint256 extraA, uint256 extraB) public {
        _provideInitialLiquidity();

        extraA = bound(extraA, 0, MAX_DEPOSIT);
        extraB = bound(extraB, 0, MAX_DEPOSIT);

        tokenA.mint(address(simpleAMM), extraA);
        tokenB.mint(address(simpleAMM), extraB);

        uint256 balanceA = tokenA.balanceOf(address(simpleAMM));
        uint256 balanceB = tokenB.balanceOf(address(simpleAMM));

        simpleAMM.sync();

        assertEq(simpleAMM.reserveA(), balanceA);
        assertEq(simpleAMM.reserveB(), balanceB);
    }

    /*//////////////////////////////////////////////////////////////
                            GET AMOUNT OUT
    //////////////////////////////////////////////////////////////*/

    function testGetAmountOutAtoBReturnsCorrectValue() public {
        _provideInitialLiquidity();

        uint256 amountIn = MEDIUM_AMOUNT;
        uint256 reserveIn = simpleAMM.reserveA();
        uint256 reserveOut = simpleAMM.reserveB();

        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        uint256 expectedOut = (reserveOut * amountInWithFee) / (reserveIn * FEE_DENOMINATOR + amountInWithFee);

        uint256 actualOut = simpleAMM.getAmountOut(address(tokenA), amountIn);

        assertEq(actualOut, expectedOut);
    }

    function testGetAmountOutBtoAReturnsCorrectValue() public {
        _provideInitialLiquidity();

        uint256 amountIn = MEDIUM_AMOUNT;
        uint256 reserveIn = simpleAMM.reserveB();
        uint256 reserveOut = simpleAMM.reserveA();

        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        uint256 expectedOut = (reserveOut * amountInWithFee) / (reserveIn * FEE_DENOMINATOR + amountInWithFee);

        uint256 actualOut = simpleAMM.getAmountOut(address(tokenB), amountIn);

        assertEq(actualOut, expectedOut);
    }

    function testGetAmountOutRevertsWithInvalidToken() public {
        _provideInitialLiquidity();

        MockERC20 invalidToken = new MockERC20("Mock", "MOCK");

        vm.expectRevert(SimpleAMM.SimpleAMM__InvalidToken.selector);
        simpleAMM.getAmountOut(address(invalidToken), MEDIUM_AMOUNT);
    }

    function testGetAmountOutRevertsWithZeroAmount() public {
        _provideInitialLiquidity();

        vm.expectRevert(SimpleAMM.SimpleAMM__ZeroAmount.selector);
        simpleAMM.getAmountOut(address(tokenA), 0);
    }

    function testGetAmountOutRevertsIfReservesEmpty() public {
        vm.expectRevert(SimpleAMM.SimpleAMM__InsufficientReserves.selector);
        simpleAMM.getAmountOut(address(tokenA), MEDIUM_AMOUNT);
    }

    function testGetAmountOutMatchesActualSwapOutput() public {
        _provideInitialLiquidity();

        uint256 amountIn = MEDIUM_AMOUNT;
        uint256 expectedOut = simpleAMM.getAmountOut(address(tokenA), amountIn);

        uint256 bobBBefore = tokenB.balanceOf(bob);

        _approveTokens(bob, amountIn, expectedOut);
        vm.prank(bob);
        simpleAMM.swap(address(tokenA), amountIn, expectedOut);

        assertEq(tokenB.balanceOf(bob) - bobBBefore, expectedOut);
    }

    /*//////////////////////////////////////////////////////////////
                        GET AMOUNT OUT — FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_GetAmountOut_MatchesFormula(uint256 amountIn, bool aToB) public {
        _provideInitialLiquidity();

        address tIn = aToB ? address(tokenA) : address(tokenB);

        uint256 reserveIn = aToB ? simpleAMM.reserveA() : simpleAMM.reserveB();
        uint256 reserveOut = aToB ? simpleAMM.reserveB() : simpleAMM.reserveA();

        amountIn = bound(amountIn, 1, reserveIn - MEDIUM_AMOUNT);

        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        uint256 expectedOut = (reserveOut * amountInWithFee) / (reserveIn * FEE_DENOMINATOR + amountInWithFee);

        assertEq(simpleAMM.getAmountOut(tIn, amountIn), expectedOut);
    }

    function testFuzz_GetAmountOutNeverExceedsReserve(uint256 amountIn) public {
        _provideInitialLiquidity();

        amountIn = bound(amountIn, 1, type(uint128).max);

        uint256 amountOut = simpleAMM.getAmountOut(address(tokenA), amountIn);

        assertLt(amountOut, simpleAMM.reserveB());
    }
}
