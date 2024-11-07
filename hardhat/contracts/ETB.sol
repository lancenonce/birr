pragma solidity =0.8.17;

import "@vialabs-io/npm-contracts/MessageClient.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract ETB is ERC20Burnable, MessageClient {
    constructor() ERC20("Ethiopian Birr", "ETB") {
        MESSAGE_OWNER = msg.sender;
    }

    function testMint(address _to, uint _amount) external {
        require(
            msg.sender == MESSAGE_OWNER,
            "ETB: Only owner can call this function"
        );
        _mint(_to, _amount);
    }

    // pass desired output token here
    function bridge(
        uint _destChainId,
        address _recipient,
        uint _amount,
        address _desiredOutputToken,
        bool officialRate
    ) external onlyActiveChain(_destChainId) {
        // burn tokens
        _burn(msg.sender, _amount);

        // send cross chain message
        _sendMessage(
            _destChainId,
            abi.encode(_recipient, _amount, _desiredOutputToken, officialRate)
        );
    }

    // add a desired output token to the data
    function messageProcess(
        uint,
        uint _sourceChainId,
        address _sender,
        address,
        uint,
        bytes calldata _data
    ) external override onlySelf(_sender, _sourceChainId) {
        // decode message
        (address _recipient, uint _amount, address _desiredOutputToken, bool _officialRate) = abi
            .decode(_data, (address, uint, address, bool));

        // mint tokens
        // if desired token is not this one, swap to the desired token
        if (_desiredOutputToken != address(this)) {
            swap(_amount, _desiredOutputToken, _officialRate);
        } else {
            _mint(_recipient, _amount);
        }
    }

    // WARNING: For now, the desiredOutputToken is USDC by default, so the param is not used
    function swap(uint _amount, address _desiredOutputToken, bool _useOfficialRate) internal {
        if (_useOfficialRate) {
            officialSwap(_amount);
        } else {
            marketSwap(_amount);
        }
    }

    function officialSwap(uint _amount) internal {
        // Implement official swap logic here
    }

    function marketSwap(uint _amount) internal {
        // Implement market swap logic here
    }
}
