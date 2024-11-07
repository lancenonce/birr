pragma solidity =0.8.17;

import "@vialabs-io/npm-contracts/MessageClient.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract ETB is ERC20Burnable, MessageClient {
    constructor() ERC20("Ethiopian Birr", "ETB") {
        MESSAGE_OWNER = msg.sender;
    }

    function testMint(address _to, uint _amount) external {
        require(msg.sender == MESSAGE_OWNER, "ETB: Only owner can call this function");
        _mint(_to, _amount);
    }

    function bridge(uint _destChainId, address _recipient, uint _amount) external onlyActiveChain(_destChainId) {
        // burn tokens
        _burn(msg.sender, _amount);

        // send cross chain message
        _sendMessage(_destChainId, abi.encode(_recipient, _amount));
    }

    function messageProcess(uint, uint _sourceChainId, address _sender, address, uint, bytes calldata _data) external override  onlySelf(_sender, _sourceChainId)  {
        // decode message
        (address _recipient, uint _amount) = abi.decode(_data, (address, uint));

        // mint tokens
        _mint(_recipient, _amount);
    }
}
