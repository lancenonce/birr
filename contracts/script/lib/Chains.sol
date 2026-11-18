// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";

/// @notice Per-chain addresses used by deploy scripts. Every value can be overridden via env.
library Chains {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant SEPOLIA = 11155111;
    uint256 internal constant UNICHAIN_SEPOLIA = 1301;

    /// @notice Primus production attestor used by @primuslabs/zktls-js-sdk >= 0.3.8 / core-sdk >= 0.3.8.
    address internal constant PRIMUS_ATTESTOR = 0x5Ed3176045F68617B0958a61ac1868875C98C14d;

    function poolManager() internal view returns (address) {
        address fromEnv = vm.envOr("POOL_MANAGER", address(0));
        if (fromEnv != address(0)) return fromEnv;
        if (block.chainid == SEPOLIA) return 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
        if (block.chainid == UNICHAIN_SEPOLIA) return 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
        revert("Chains: no PoolManager for this chain; set POOL_MANAGER");
    }

    function usdc() internal view returns (address) {
        address fromEnv = vm.envOr("USDC", address(0));
        if (fromEnv != address(0)) return fromEnv;
        if (block.chainid == SEPOLIA) return 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // Circle test USDC
        revert("Chains: no USDC for this chain; set USDC");
    }
}
