// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "@uniswap-core/interfaces/IHooks.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


// Here, we will launch the hook for the Birr token on Unichain at 0x0135c25Bd3e88b1aac5FDC6f16FEe2C63d967f9d
// The hook will be used to prevent blacklisted addresses from executing swaps.
// Customers can compare the central bank rate (on scroll) with the market rate on Unichain
/**
 * @title Birr Blacklist Hook
 * @dev A Uniswap V4 hook that prevents blacklisted addresses from executing swaps.
 */
contract BirrHook is IHooks, Ownable {
    address public blacklister;
    mapping(address => bool) private _blacklisted;

    event Blacklisted(address indexed account);
    event UnBlacklisted(address indexed account);
    event BlacklisterChanged(address indexed newBlacklister);

    function initialize(address initialOwner) public initializer {
        __Ownable_init();
        transferOwnership(initialOwner);
    }

    modifier onlyBlacklister() {
        require(msg.sender == blacklister, "Caller is not the blacklister");
        _;
    }

    modifier notBlacklisted(address account) {
        require(!_blacklisted[account], "Account is blacklisted");
        _;
    }

    function isBlacklisted(address account) external view returns (bool) {
        return _blacklisted[account];
    }

    function blacklist(address account) external onlyBlacklister {
        _blacklisted[account] = true;
        emit Blacklisted(account);
    }

    function unBlacklist(address account) external onlyBlacklister {
        _blacklisted[account] = false;
        emit UnBlacklisted(account);
    }

    function updateBlacklister(address newBlacklister) external onlyOwner {
        require(newBlacklister != address(0), "New blacklister is the zero address");
        blacklister = newBlacklister;
        emit BlacklisterChanged(newBlacklister);
    }

    // Implementing the beforeSwap hook
    function beforeSwap(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.SwapParams calldata params
    ) external override notBlacklisted(sender) returns (bytes4) {
        return IHooks.beforeSwap.selector;
    }
}