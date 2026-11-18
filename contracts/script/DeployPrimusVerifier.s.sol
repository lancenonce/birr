// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PrimusZKTLS} from "@primuslabs/zktls-contracts/src/PrimusZKTLS.sol";
import {Attestor} from "@primuslabs/zktls-contracts/src/IPrimusZKTLS.sol";
import {Chains} from "./lib/Chains.sol";

/// @notice Deploys Primus's own PrimusZKTLS verifier (behind an ERC1967 proxy), trusting the current Primus
///         production attestor.
/// @dev Needed because Primus's Sepolia verifier (0x3760aB354507a29a9F5c65A66C74353fd86393FA) still only
///      trusts the old attestor 0xDB736B13...8eF6, while js-sdk 0.3.15 signs with 0x5Ed3...C14d.
///      If Primus updates their verifier, skip this and point PRIMUS_VERIFIER at theirs instead.
///
/// forge script script/DeployPrimusVerifier.s.sol --rpc-url sepolia --broadcast --verify
/// Env: PRIVATE_KEY, optional PRIMUS_ATTESTOR (defaults to Chains.PRIMUS_ATTESTOR).
contract DeployPrimusVerifier is Script {
    function run() external returns (address verifier) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address attestor = vm.envOr("PRIMUS_ATTESTOR", Chains.PRIMUS_ATTESTOR);

        Attestor[] memory attestors = new Attestor[](1);
        attestors[0] = Attestor({attestorAddr: attestor, url: "https://primuslabs.xyz"});

        vm.startBroadcast(pk);
        PrimusZKTLS impl = new PrimusZKTLS();
        verifier = address(
            new ERC1967Proxy(
                address(impl), abi.encodeCall(PrimusZKTLS.initialize, (vm.addr(pk), attestors))
            )
        );
        vm.stopBroadcast();

        console.log("PrimusZKTLS implementation:", address(impl));
        console.log("PrimusZKTLS verifier (proxy):", verifier);
        console.log("Trusted attestor:", attestor);
        console.log("-> set PRIMUS_VERIFIER=%s in contracts/.env", verifier);
    }
}
