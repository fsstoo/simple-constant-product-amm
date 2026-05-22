// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {SimpleAMM} from "../../src/SimpleAMM.sol";
import {TokenA, TokenB} from "../../src/TokenContracts.sol";

import {Handler, IOwnerForwarder} from "./Handler.t.sol";

/**
 * @title SimpleAMMInvariant
 * @notice Stateful invariant suite for SimpleAMM.
 */
contract SimpleAMMInvariant is StdInvariant, Test, IOwnerForwarder {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    SimpleAMM internal amm;

    TokenA internal tokenA;
    TokenB internal tokenB;

    Handler internal handler;

    uint256 internal constant MINIMUM_LIQUIDITY = 1_000;

    address internal constant BURN_ADDRESS = address(0xdead);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        tokenA = new TokenA(address(this));
        tokenB = new TokenB(address(this));

        amm = new SimpleAMM(address(tokenA), address(tokenB));

        handler = new Handler(amm, tokenA, tokenB, IOwnerForwarder(address(this)));

        // Seed initial liquidity
        uint256 seedAmount = 100_000;

        tokenA.mint(handler.alice(), seedAmount);
        tokenB.mint(handler.alice(), seedAmount);

        vm.startPrank(handler.alice());

        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);

        amm.addLiquidity(seedAmount, seedAmount, seedAmount, seedAmount);

        vm.stopPrank();

        // Target handler selectors
        bytes4[] memory selectors = new bytes4[](8);

        selectors[0] = handler.addLiquidityAlice.selector;
        selectors[1] = handler.addLiquidityBob.selector;
        selectors[2] = handler.removeLiquidityAlice.selector;
        selectors[3] = handler.removeLiquidityBob.selector;
        selectors[4] = handler.swapAForB.selector;
        selectors[5] = handler.swapBForA.selector;
        selectors[6] = handler.skim.selector;
        selectors[7] = handler.sync.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        targetContract(address(handler));
    }

    /*//////////////////////////////////////////////////////////////
                        OWNER FORWARDERS
    //////////////////////////////////////////////////////////////*/

    function forwardSkim() external {
        amm.skim(address(this));
    }

    function forwardSync() external {
        amm.sync();
    }

    /*//////////////////////////////////////////////////////////////
                            INVARIANTS
    //////////////////////////////////////////////////////////////*/

    function invariant_ReservesMatchBalances() public view {
        assertEq(tokenA.balanceOf(address(amm)), amm.reserveA());
        assertEq(tokenB.balanceOf(address(amm)), amm.reserveB());
    }

    function invariant_TotalSupplyAboveMinimumLiquidity() public view {
        if (amm.totalSupply() == 0) return;

        assertGe(amm.totalSupply(), MINIMUM_LIQUIDITY);
    }

    function invariant_ReservesEitherBothZeroOrBothNonZero() public view {
        bool aZero = amm.reserveA() == 0;
        bool bZero = amm.reserveB() == 0;

        assertTrue((aZero && bZero) || (!aZero && !bZero));
    }

    function invariant_KNeverDecreasesAfterSwap() public view {
        if (amm.reserveA() == 0 || amm.reserveB() == 0) return;

        assertGe(amm.reserveA() * amm.reserveB(), handler.kLast());
    }

    function invariant_LPSupplyAccountingCorrect() public view {
        uint256 tracked = amm.balanceOf(address(this)) + amm.balanceOf(handler.alice()) + amm.balanceOf(handler.bob())
            + amm.balanceOf(BURN_ADDRESS);

        assertEq(tracked, amm.totalSupply());
    }

    function invariant_ZeroAddressHoldsNoLPTokens() public view {
        assertEq(amm.balanceOf(address(0)), 0);
    }
}
