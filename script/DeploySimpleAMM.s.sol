// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";
import {TokenA, TokenB} from "../src/TokenContracts.sol";

/**
 * @title DeployAMM
 * @author FSTO
 *
 * @notice
 * Deployment script for:
 * - TokenA
 * - TokenB
 * - SimpleAMM
 *
 * @dev
 * Uses Foundry keystore accounts.
 *
 * Example:
 * forge script script/DeployAMM.s.sol \
 *     --rpc-url <RPC_URL> \
 *     --account defaultKey \
 *     --sender 0x... \
 *     --broadcast
 */

contract DeployAMM is Script {
    function run() external returns (SimpleAMM, TokenA, TokenB) {
        address deployer = msg.sender;

        vm.startBroadcast(deployer);

        TokenA tokenA = new TokenA(deployer);
        TokenB tokenB = new TokenB(deployer);

        SimpleAMM simpleAMM = new SimpleAMM(address(tokenA), address(tokenB));

        vm.stopBroadcast();

        return (simpleAMM, tokenA, tokenB);
    }
}
