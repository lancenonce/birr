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

import "./Ownable.sol";
import "./Blacklistable.sol";
import "./Pausable.sol";
import "./Rescuable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

contract EthiopianBirrV0 is ERC20Upgradeable, Ownable, Blacklistable, Pausable, Rescuable, Initializable, UUPSUpgradeable {
    uint256 private _totalSupply;

    function initialize(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply,
        address owner
    ) public initializer {
        __ERC20_init(name, symbol);

        _mint(owner, initialSupply * 10**decimals);
        Ownable.transferOwnership(owner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(ERC20) whenNotPaused {
        require(!Blacklistable.isBlacklisted(from), "Sender is blacklisted");
        require(!Blacklistable.isBlacklisted(to), "Recipient is blacklisted");
        super._beforeTokenTransfer(from, to, amount);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }

    function rescueTokens(address tokenAddress, address recipient, uint256 amount) external onlyOwner {
        Rescuable.rescueTokens(tokenAddress, recipient, amount);
    }

    function pause() external onlyOwner {
        Pausable.pause();
    }

    function unpause() external onlyOwner {
        Pausable.unpause();
    }
}