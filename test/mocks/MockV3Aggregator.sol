// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract MockV3Aggregator {
    uint8 public decimals;
    uint256 private priceData;
    uint256 private updatedAt;

    constructor(uint8 _decimals, uint256 _priceData) {
        decimals = _decimals;
        priceData = _priceData;
        updatedAt = block.timestamp;
    }

    function setPriceData(uint256 _priceData) external {
        priceData = _priceData;
    }

    function setUpdatedAt(uint256 _updatedAt) external {
        updatedAt = _updatedAt;
    }

    function latestAnswer() external pure returns (int256) {
        return 0;
    }

    function latestTimestamp() external pure returns (uint256) {
        return 0;
    }

    function latestRound() external pure returns (uint256) {
        return 0;
    }

    function getAnswer(uint256) external pure returns (int256) {
        return 0;
    }

    function getTimestamp(uint256 roundId) external pure returns (uint256) {
        return roundId;
    }

    function description() external pure returns (string memory) {
        return "";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(
        uint80
    )
        external
        pure
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 _updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, 0, 0, 0, 0);
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 _updatedAt,
            uint80 answeredInRound
        )
    {
        return (
            uint80(73786976294838220258),
            // forge-lint: disable-next-line(unsafe-typecast)
            int256(priceData * 10 ** decimals),
            uint256(163826896),
            uint256(updatedAt),
            uint80(73786976294838220258)
        );
    }
}
