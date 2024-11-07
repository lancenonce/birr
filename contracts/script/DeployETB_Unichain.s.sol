// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../src/ETB.sol";

contract DeployETB_Ethereum is Script {
    IPoolManager public poolManager = IPoolManager(	address(0xC81462Fec8B23319F288047f8A03A57682a35C1A));
    function run() external {
        uint256 deployerPKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPKey);

        ETB etb = new ETB(poolManager, vm.addr(deployerPKey));

        console.log("ETB deployed to:", address(etb));

        vm.stopBroadcast();
    }
}