// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "@vialabs/MessageClient.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPoolManager} from "@uniswap-core/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap-core/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap-core/types/PoolKey.sol";
import {Currency} from "@uniswap-core/types/Currency.sol";
import {NBERateOracle} from "./oracle/NBERateOracle.sol";

/// @title ETB (sETB)
/// @notice Cross-chain Ethiopian Birr token. Holders can redeem sETB for USDC at the official
///         National Bank of Ethiopia rate, proven on-chain via Primus zkTLS (see NBERateOracle).
contract ETB is ERC20Burnable, MessageClient, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IPoolManager public poolManager;

    /// @notice Source of the zkTLS-verified NBE USD rate.
    NBERateOracle public oracle;
    /// @notice Token paid out by official-rate swaps (USDC). Held by this contract as a reserve.
    IERC20 public usdc;
    uint8 public usdcDecimals;
    /// @notice Official swaps revert (or, cross-chain, fall back to minting sETB) if the rate is older than this.
    uint256 public maxRateAge;

    event SwapExecuted(uint256 amountSwapped, address outputToken);
    event OfficialSwap(
        address indexed from, address indexed to, uint256 etbIn, uint256 usdcOut, uint256 sellingRate
    );
    event OfficialSwapFallback(address indexed recipient, uint256 etbAmount);
    event OracleUpdated(address oracle);
    event UsdcUpdated(address usdc, uint8 decimals);
    event MaxRateAgeUpdated(uint256 maxRateAge);
    event ReserveWithdrawn(address indexed token, address indexed to, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error OfficialRateNotConfigured();
    error RateUnavailable();
    error StaleRate(uint256 updatedAt);
    error InsufficientReserve(uint256 needed, uint256 available);

    constructor(IPoolManager _poolManager, address initialOwner)
        ERC20("Ethiopian Birr", "ETB")
        Ownable(initialOwner)
    {
        MESSAGE_OWNER = msg.sender;
        poolManager = _poolManager;
        maxRateAge = 1 days;
    }

    function testMint(address _to, uint256 _amount) external {
        require(msg.sender == MESSAGE_OWNER, "ETB: Only owner can call this function");
        _mint(_to, _amount);
    }

    // ---------------------------------------------------------------------
    // Official-rate swap (same chain)
    // ---------------------------------------------------------------------

    /// @notice Burn `etbAmount` sETB from the caller and send USDC to `to` at the NBE selling rate.
    /// @return usdcOut USDC (in its native decimals) sent to `to`.
    function swapAtOfficialRate(uint256 etbAmount, address to)
        external
        nonReentrant
        returns (uint256 usdcOut)
    {
        if (to == address(0)) revert ZeroAddress();
        if (etbAmount == 0) revert ZeroAmount();

        uint256 selling;
        (usdcOut, selling) = quoteOfficial(etbAmount);
        if (usdcOut == 0) revert ZeroAmount();
        uint256 available = usdc.balanceOf(address(this));
        if (available < usdcOut) revert InsufficientReserve(usdcOut, available);

        _burn(msg.sender, etbAmount);
        usdc.safeTransfer(to, usdcOut);

        emit OfficialSwap(msg.sender, to, etbAmount, usdcOut, selling);
    }

    /// @notice USDC out for `etbAmount` sETB at the current official rate. Reverts if the rate is unusable.
    /// @dev usdcOut = etbAmount[1e18] * 10^usdcDecimals / sellingRate[1e18 ETB per USD]. Rounds down.
    function quoteOfficial(uint256 etbAmount)
        public
        view
        returns (uint256 usdcOut, uint256 sellingRate)
    {
        if (address(oracle) == address(0) || address(usdc) == address(0)) {
            revert OfficialRateNotConfigured();
        }
        uint256 updatedAt;
        (sellingRate,, updatedAt) = oracle.getRate();
        if (sellingRate == 0) revert RateUnavailable();
        if (block.timestamp > updatedAt + maxRateAge) revert StaleRate(updatedAt);
        usdcOut = etbAmount * 10 ** usdcDecimals / sellingRate;
    }

    // ---------------------------------------------------------------------
    // Cross-chain (VIA Labs)
    // ---------------------------------------------------------------------

    // pass desired output token here
    function bridge(
        uint256 _destChainId,
        address _recipient,
        uint256 _amount,
        address _desiredOutputToken,
        bool officialRate
    ) external onlyActiveChain(_destChainId) {
        _burn(msg.sender, _amount);
        _sendMessage(
            _destChainId, abi.encode(_recipient, _amount, _desiredOutputToken, officialRate)
        );
    }

    function messageProcess(
        uint256,
        uint256 _sourceChainId,
        address _sender,
        address,
        uint256,
        bytes calldata _data
    ) external override onlySelf(_sender, _sourceChainId) {
        (address _recipient, uint256 _amount, address _desiredOutputToken, bool _officialRate) =
            abi.decode(_data, (address, uint256, address, bool));

        if (_desiredOutputToken == address(this)) {
            _mint(_recipient, _amount);
        } else if (_officialRate) {
            _officialPayoutOrMint(_recipient, _amount, _desiredOutputToken);
        } else {
            marketSwap(_amount, _desiredOutputToken);
        }
    }

    /// @dev Cross-chain official swap. The sETB was already burned on the source chain, so this must never
    ///      revert in a way that strands value: if the official payout can't be made, re-mint sETB instead.
    function _officialPayoutOrMint(address recipient, uint256 etbAmount, address outputToken) internal {
        if (outputToken == address(usdc) && address(oracle) != address(0)) {
            (uint256 selling,, uint256 updatedAt) = oracle.getRate();
            if (selling != 0 && block.timestamp <= updatedAt + maxRateAge) {
                uint256 usdcOut = etbAmount * 10 ** usdcDecimals / selling;
                if (usdcOut != 0 && usdc.balanceOf(address(this)) >= usdcOut) {
                    usdc.safeTransfer(recipient, usdcOut);
                    emit OfficialSwap(address(0), recipient, etbAmount, usdcOut, selling);
                    return;
                }
            }
        }
        _mint(recipient, etbAmount);
        emit OfficialSwapFallback(recipient, etbAmount);
    }

    // ---------------------------------------------------------------------
    // Market swap (Uniswap v4) — out of scope for the official-rate work; unchanged.
    // ---------------------------------------------------------------------

    function marketSwap(uint256 _amount, address desiredOutputToken) internal {
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

        poolManager.swap(poolKey, params, "");

        emit SwapExecuted(_amount, desiredOutputToken);
    }

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------

    function setOracle(NBERateOracle _oracle) external onlyOwner {
        if (address(_oracle) == address(0)) revert ZeroAddress();
        oracle = _oracle;
        emit OracleUpdated(address(_oracle));
    }

    function setUsdc(IERC20 _usdc) external onlyOwner {
        if (address(_usdc) == address(0)) revert ZeroAddress();
        usdc = _usdc;
        usdcDecimals = IERC20Metadata(address(_usdc)).decimals();
        emit UsdcUpdated(address(_usdc), usdcDecimals);
    }

    function setMaxRateAge(uint256 _maxRateAge) external onlyOwner {
        if (_maxRateAge == 0) revert ZeroAmount();
        maxRateAge = _maxRateAge;
        emit MaxRateAgeUpdated(_maxRateAge);
    }

    /// @notice Withdraw reserve tokens (e.g. USDC). The reserve is funded by plain transfers to this contract.
    function withdrawReserve(IERC20 token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        token.safeTransfer(to, amount);
        emit ReserveWithdrawn(address(token), to, amount);
    }
}
