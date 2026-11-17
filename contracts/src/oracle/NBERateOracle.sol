// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IPrimusZKTLS,
    Attestation,
    AttNetworkResponseResolve
} from "@primuslabs/zktls-contracts/src/IPrimusZKTLS.sol";
import {JsonParser} from "@primuslabs/zktls-contracts/src/utils/JsonParser.sol";
import {DecimalParser} from "../lib/DecimalParser.sol";

/// @title NBERateOracle
/// @notice Stores the National Bank of Ethiopia USD/ETB exchange rate, updated permissionlessly by anyone
///         who submits a valid Primus zkTLS attestation of the NBE exchange-rate API response.
/// @dev The Primus verifier only checks the attestor signature. Everything else that makes the attestation
///      meaningful (which URL, which JSON fields, freshness, replay) is enforced here.
contract NBERateOracle is Ownable {
    /// @notice What a valid attestation must look like. Set by the owner to match the Primus template.
    struct Spec {
        string url; // exact request URL, e.g. https://api.nbe.gov.et/api/get-selected-exchange-rates
        string codeKey; // keyName whose value must be "USD"
        string sellingKey; // keyName of the bank's USD selling rate (ETB per USD)
        string buyingKey; // keyName of the bank's USD buying rate (ETB per USD)
        bytes32 resolvesHash; // keccak256(abi.encode(AttNetworkResponseResolve[])) of the template's resolves
    }

    struct Rate {
        uint128 selling; // ETB per 1 USD, 1e18 fixed point
        uint128 buying; // ETB per 1 USD, 1e18 fixed point
        uint64 updatedAt; // attestation time, unix seconds
    }

    bytes32 private constant GET = keccak256("GET");
    bytes32 private constant USD = keccak256("USD");

    /// @notice Allowed clock skew between the attestor and the chain.
    uint256 public constant MAX_FUTURE_SKEW = 5 minutes;

    IPrimusZKTLS public verifier;
    Spec internal _spec;
    Rate internal _rate;

    /// @notice Attestations older than this (relative to block.timestamp) are rejected.
    uint256 public maxAttestationAge;
    /// @notice Sanity bounds on accepted rates (1e18 fixed point, ETB per USD).
    uint256 public minRate;
    uint256 public maxRate;
    /// @notice Timestamp (ms, as attested) of the last accepted attestation. Enforces monotonicity / no replay.
    uint64 public lastAttestationTimestampMs;

    event RateUpdated(uint256 selling, uint256 buying, uint64 attestedAt, address indexed submitter);
    event VerifierUpdated(address verifier);
    event SpecUpdated(string url, bytes32 resolvesHash);
    event ParamsUpdated(uint256 maxAttestationAge, uint256 minRate, uint256 maxRate);

    error WrongUrl();
    error WrongMethod();
    error WrongResolves();
    error NotUSD();
    error StaleAttestation();
    error FutureAttestation();
    error NotNewer();
    error RateOutOfBounds(uint256 rate);
    error SellingBelowBuying();
    error InvalidParams();

    constructor(
        address initialOwner,
        IPrimusZKTLS _verifier,
        Spec memory spec_,
        uint256 _maxAttestationAge,
        uint256 _minRate,
        uint256 _maxRate
    ) Ownable(initialOwner) {
        _setVerifier(_verifier);
        _setSpec(spec_);
        _setParams(_maxAttestationAge, _minRate, _maxRate);
    }

    // ---------------------------------------------------------------------
    // Permissionless update
    // ---------------------------------------------------------------------

    /// @notice Verify a Primus attestation of the NBE API and store the USD rate it proves.
    function submitRate(Attestation calldata att) external {
        verifier.verifyAttestation(att);

        if (keccak256(bytes(att.request.url)) != keccak256(bytes(_spec.url))) revert WrongUrl();
        if (keccak256(bytes(att.request.method)) != GET) revert WrongMethod();
        if (hashResolves(att.reponseResolve) != _spec.resolvesHash) revert WrongResolves();

        uint64 tsMs = att.timestamp;
        uint256 ts = tsMs / 1000;
        if (ts > block.timestamp + MAX_FUTURE_SKEW) revert FutureAttestation();
        if (block.timestamp > ts && block.timestamp - ts > maxAttestationAge) revert StaleAttestation();
        if (tsMs <= lastAttestationTimestampMs) revert NotNewer();

        string[] memory keys = new string[](3);
        keys[0] = _spec.codeKey;
        keys[1] = _spec.sellingKey;
        keys[2] = _spec.buyingKey;
        string[] memory values = JsonParser.extractArrayValue(att.data, keys);

        if (keccak256(bytes(values[0])) != USD) revert NotUSD();
        uint256 selling = DecimalParser.parse18(values[1]);
        uint256 buying = DecimalParser.parse18(values[2]);
        _checkBounds(selling);
        _checkBounds(buying);
        if (selling < buying) revert SellingBelowBuying();

        lastAttestationTimestampMs = tsMs;
        _rate = Rate({selling: uint128(selling), buying: uint128(buying), updatedAt: uint64(ts)});

        emit RateUpdated(selling, buying, uint64(ts), msg.sender);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @return selling ETB per USD (1e18) the bank sells USD at — use this when converting ETB -> USD.
    /// @return buying  ETB per USD (1e18) the bank buys USD at.
    /// @return updatedAt unix seconds of the attestation (0 if never set).
    function getRate() external view returns (uint256 selling, uint256 buying, uint256 updatedAt) {
        Rate memory r = _rate;
        return (r.selling, r.buying, r.updatedAt);
    }

    function spec() external view returns (Spec memory) {
        return _spec;
    }

    /// @notice Hash used to pin the template's response resolves (keyName, parseType, parsePath, in order).
    function hashResolves(AttNetworkResponseResolve[] memory resolves) public pure returns (bytes32) {
        return keccak256(abi.encode(resolves));
    }

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------

    function setVerifier(IPrimusZKTLS _verifier) external onlyOwner {
        _setVerifier(_verifier);
    }

    function setSpec(Spec calldata spec_) external onlyOwner {
        _setSpec(spec_);
    }

    function setParams(uint256 _maxAttestationAge, uint256 _minRate, uint256 _maxRate)
        external
        onlyOwner
    {
        _setParams(_maxAttestationAge, _minRate, _maxRate);
    }

    function _setVerifier(IPrimusZKTLS _verifier) internal {
        if (address(_verifier) == address(0)) revert InvalidParams();
        verifier = _verifier;
        emit VerifierUpdated(address(_verifier));
    }

    function _setSpec(Spec memory spec_) internal {
        if (
            bytes(spec_.url).length == 0 || bytes(spec_.codeKey).length == 0
                || bytes(spec_.sellingKey).length == 0 || bytes(spec_.buyingKey).length == 0
                || spec_.resolvesHash == bytes32(0)
        ) revert InvalidParams();
        _spec = spec_;
        emit SpecUpdated(spec_.url, spec_.resolvesHash);
    }

    function _setParams(uint256 _maxAttestationAge, uint256 _minRate, uint256 _maxRate) internal {
        if (_maxAttestationAge == 0 || _minRate == 0 || _minRate >= _maxRate || _maxRate > type(uint128).max) {
            revert InvalidParams();
        }
        maxAttestationAge = _maxAttestationAge;
        minRate = _minRate;
        maxRate = _maxRate;
        emit ParamsUpdated(_maxAttestationAge, _minRate, _maxRate);
    }

    function _checkBounds(uint256 rate) internal view {
        if (rate < minRate || rate > maxRate) revert RateOutOfBounds(rate);
    }
}
