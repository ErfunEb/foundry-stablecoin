// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/*
 * @title DSCEngine
 * @author Erfan Ebrahimi
 *
 * The system is designed to be as minimal as possible, and have tokens maintain a 1 token == 1$ pegged.
 * This stablecoin has properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * -Algorithmically Stable
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of all collateral <= the $ backed value of all the DSC
 *
 * @notice This contract is the core of the DSC System. It Handles all the logic for minting and redeeming DSC, as well as depositing and withdrawing collateral
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */
contract DSCEngine {
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesPriceFeedAndAddressesMustBeSameLength();

    mapping(address token => address priceFeed) private priceFeeds;

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    // modifier isAllowedToken(address token) {

    // }

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesPriceFeedAndAddressesMustBeSameLength();
        }
    }

    function depositCollateralAndMintDsc() external {}

    /*
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     *
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) external moreThanZero(amountCollateral) {}

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
