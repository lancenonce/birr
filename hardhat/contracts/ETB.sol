pragma solidity =0.8.17;

import "@vialabs-io/npm-contracts/MessageClient.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "./lib/uniswap-v4-core/src/interfaces/IPoolManager.sol";
import "./lib/uniswap-v4-core/src/interfaces/IHooks.sol";
import "./hooks/BirrHook.sol";

contract ETB is ERC20Burnable, MessageClient, Ownable {
    address public constant NOTARY_PUBLIC_KEY =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // dummy
    uint256 public rate;

    event SwapExecuted(uint amountSwapped, address outputToken);

    IPoolManager public poolManager;

    constructor(
        IPoolManager _poolManager,
        address initialOwner
    ) ERC20("Ethiopian Birr", "ETB") Ownable(initialOwner) {
        transferOwnership(initialOwner);
        MESSAGE_OWNER = msg.sender;
        poolManager = _poolManager;
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

    // Process cross-chain messages
    function messageProcess(
        uint,
        uint _sourceChainId,
        address _sender,
        address,
        uint,
        bytes calldata _data
    ) external override onlySelf(_sender, _sourceChainId) {
        // decode message
        (
            address _recipient,
            uint _amount,
            address _desiredOutputToken,
            bool _officialRate
        ) = abi.decode(_data, (address, uint, address, bool));

        // mint tokens
        // if desired token is not this one, swap to the desired token
        if (_desiredOutputToken != address(this)) {
            swap(_amount, _desiredOutputToken, _officialRate);
        } else {
            _mint(_recipient, _amount);
        }
    }

    function swap(
        uint _amount,
        address _desiredOutputToken,
        bool _useOfficialRate
    ) internal {
        if (_useOfficialRate) {
            officialSwap(_amount, _desiredOutputToken);
        } else {
            marketSwap(_amount, _desiredOutputToken);
        }
    }

    function officialSwap(uint _amount, address _desiredOutputToken) internal {
        IERC20 token = IERC20(_desiredOutputToken);
        uint256 usdcAmount = (_amount * rate) / 1e18;
        require(
            token.balanceOf(address(this)) >= usdcAmount,
            "Insufficient USDC balance"
        );
        token.transfer(msg.sender, usdcAmount);
    }

    // This is the swap function for the uniswap AMM rate
    function marketSwap(uint _amount, address desiredOutputToken) internal {
        // Implement market swap logic here
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(this)),
            currency1: Currency.wrap(desiredOutputToken),
            fee: 3500,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: int256(_amount),
            sqrtPriceLimitX96: 0
        });

        // SWAP!
         poolManager.swap(poolKey, params, "");

        emit SwapExecuted(_amount, desiredOutputToken);
    }

    function updateRate(
        uint256 _rate,
        bytes32 _messageHash,
        bytes memory _signature
    ) external onlyOwner {
        require(verifySignature(_messageHash, _signature), "Invalid signature");
        rate = _rate;
    }

    function verifySignature(
        bytes32 _messageHash,
        bytes memory _signature
    ) internal view returns (bool) {
        // bytes32 ethSignedMessageHash = getEthSignedMessageHash(_messageHash);
        // (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);
        // address signer = ecrecover(ethSignedMessageHash, v, r, s);
        // return signer == PUBLIC_KEY;
        return true;
    }

    function getEthSignedMessageHash(
        bytes32 _messageHash
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    _messageHash
                )
            );
    }

    function splitSignature(
        bytes memory _signature
    ) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(_signature.length == 65, "Invalid signature length");
        assembly {
            r := mload(add(_signature, 32))
            s := mload(add(_signature, 64))
            v := byte(0, mload(add(_signature, 96)))
        }
    }
}
