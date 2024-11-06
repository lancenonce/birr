/**
 * Copyright 2024 Seree Technologies, Inc. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

pragma solidity ^0.8.0;

import "@openzeppelin-up/contracts/access/OwnableUpgradeable.sol";
// import "./Blacklistable.sol";
// import "./Pausable.sol";
// import "./Rescuable.sol";
import "@openzeppelin-up/contracts/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/Erc20.sol";

contract EthiopianBirrV0 is
    Initializable,
    ERC20Upgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable
    // Blacklistable,
    // Pausable
    // Rescuable
{
    uint256 private _totalSupply;

    function initialize(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _initialSupply
    ) public initializer {
        __ERC20_init(_name, _symbol);

        _mint(msg.sender, _initialSupply * 10 ** _decimals);
        transferOwnership(msg.sender);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }

    // function rescueTokens(
    //     address tokenAddress,
    //     address recipient,
    //     uint256 amount
    // ) external onlyOwner {
    //     Rescuable.rescueTokens(tokenAddress, recipient, amount);
    // }

    // function pause() external override onlyOwner {
    //     Pausable.pause();
    // }

    // function unpause() external override onlyOwner {
    //     Pausable.unpause();
    // }

    function owner()
        public
        view
        virtual
        override(OwnableUpgradeable)
        returns (address)
    {
        return super.owner();
    }

    function transferOwnership(
        address newOwner
    ) public virtual override(OwnableUpgradeable) onlyOwner {
        super.transferOwnership(newOwner);
    }

    // function _isBlacklisted(
    //     address _account
    // ) internal view virtual override returns (bool) {
    //     return super._isBlacklisted(_account);
    // }

    // function _blacklist(address _account) internal virtual override {
    //     super._blacklist(_account);
    // }

    // function _unBlacklist(address _account) internal virtual override {
    //     super._unBlacklist(_account);
    // }
}