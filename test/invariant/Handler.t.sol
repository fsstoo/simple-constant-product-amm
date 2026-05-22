// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {SimpleAMM} from "../../src/SimpleAMM.sol";
import {TokenA, TokenB} from "../../src/TokenContracts.sol";

interface IOwnerForwarder {
    function forwardSkim() external;
    function forwardSync() external;
}

/**
 * @title Handler
 * @notice Stateful fuzz handler for AMM invariant testing.
 */
contract Handler is Test {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    SimpleAMM public immutable amm;

    TokenA public immutable tokenA;
    TokenB public immutable tokenB;

    IOwnerForwarder public immutable ownerContract;

    address public immutable alice = makeAddr("alice");
    address public immutable bob = makeAddr("bob");

    uint256 public kLast;

    uint256 private constant AMOUNT_MIN = 1001;
    uint256 private constant AMOUNT_MAX = 1e21;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(SimpleAMM _amm, TokenA _tokenA, TokenB _tokenB, IOwnerForwarder _ownerContract) {
        amm = _amm;
        tokenA = _tokenA;
        tokenB = _tokenB;
        ownerContract = _ownerContract;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _approveIfNeeded(address user) internal {
        vm.startPrank(user);

        if (tokenA.allowance(user, address(amm)) == 0) {
            tokenA.approve(address(amm), type(uint256).max);
        }

        if (tokenB.allowance(user, address(amm)) == 0) {
            tokenB.approve(address(amm), type(uint256).max);
        }

        vm.stopPrank();
    }

    function _poolLive() internal view returns (bool) {
        return amm.reserveA() > 0 && amm.reserveB() > 0;
    }

    /*//////////////////////////////////////////////////////////////
                          ADD LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    function addLiquidityAlice(uint256 amountA) public {
        amountA = bound(amountA, AMOUNT_MIN, AMOUNT_MAX);

        uint256 reserveA = amm.reserveA();
        uint256 reserveB = amm.reserveB();

        uint256 amountB;

        if (reserveA == 0 || reserveB == 0) {
            amountB = amountA;
        } else {
            amountB = (amountA * reserveB) / reserveA;

            if (amountB == 0) return;
        }

        tokenA.mint(alice, amountA);
        tokenB.mint(alice, amountB);

        _approveIfNeeded(alice);

        vm.prank(alice);

        try amm.addLiquidity(amountA, amountB, 0, 0) {} catch {}
    }

    function addLiquidityBob(uint256 amountA) public {
        amountA = bound(amountA, AMOUNT_MIN, AMOUNT_MAX);

        uint256 reserveA = amm.reserveA();
        uint256 reserveB = amm.reserveB();

        uint256 amountB;

        if (reserveA == 0 || reserveB == 0) {
            amountB = amountA;
        } else {
            amountB = (amountA * reserveB) / reserveA;

            if (amountB == 0) return;
        }

        tokenA.mint(bob, amountA);
        tokenB.mint(bob, amountB);

        _approveIfNeeded(bob);

        vm.prank(bob);

        try amm.addLiquidity(amountA, amountB, 0, 0) {} catch {}
    }

    /*//////////////////////////////////////////////////////////////
                        REMOVE LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    function removeLiquidityAlice(uint256 shares) public {
        uint256 balance = amm.balanceOf(alice);

        if (balance <= 1_000) return;

        shares = bound(shares, 1, balance - 1_000);

        vm.prank(alice);

        try amm.removeLiquidity(shares, 0, 0) {} catch {}
    }

    function removeLiquidityBob(uint256 shares) public {
        uint256 balance = amm.balanceOf(bob);

        if (balance <= 1_000) return;

        shares = bound(shares, 1, balance - 1_000);

        vm.prank(bob);

        try amm.removeLiquidity(shares, 0, 0) {} catch {}
    }

    /*//////////////////////////////////////////////////////////////
                                SWAPS
    //////////////////////////////////////////////////////////////*/

    function swapAForB(uint256 amountIn) public {
        if (!_poolLive()) return;

        amountIn = bound(amountIn, 1, amm.reserveA() / 10 + 1);

        tokenA.mint(alice, amountIn);

        _approveIfNeeded(alice);

        kLast = amm.reserveA() * amm.reserveB();

        vm.prank(alice);

        try amm.swap(address(tokenA), amountIn, 0) {} catch {}
    }

    function swapBForA(uint256 amountIn) public {
        if (!_poolLive()) return;

        amountIn = bound(amountIn, 1, amm.reserveB() / 10 + 1);

        tokenB.mint(alice, amountIn);

        _approveIfNeeded(alice);

        kLast = amm.reserveA() * amm.reserveB();

        vm.prank(alice);

        try amm.swap(address(tokenB), amountIn, 0) {} catch {}
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function skim(uint256 excessA, uint256 excessB) public {
        excessA = bound(excessA, 0, 1e18);
        excessB = bound(excessB, 0, 1e18);

        if (excessA == 0 && excessB == 0) return;

        if (excessA > 0) {
            tokenA.mint(address(amm), excessA);
        }

        if (excessB > 0) {
            tokenB.mint(address(amm), excessB);
        }

        try ownerContract.forwardSkim() {} catch {}
    }

    function sync(uint256 extraA, uint256 extraB) public {
        extraA = bound(extraA, 0, 1e18);
        extraB = bound(extraB, 0, 1e18);

        if (extraA == 0 && extraB == 0) return;

        if (extraA > 0) {
            tokenA.mint(address(amm), extraA);
        }

        if (extraB > 0) {
            tokenB.mint(address(amm), extraB);
        }

        try ownerContract.forwardSync() {} catch {}
    }
}
