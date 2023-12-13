// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;

interface IStakingTier {
    // Events
    event Deposit(address indexed account, uint256 amount);

    event Withdraw(address indexed account, uint256 amount);

    event SetPenaltyPercentage(uint128 percentage);

    event SetAcceptedToken(address indexed acceptedToken);

    event SetBlacklistContract(address indexed blacklistContractAddress);

    event SetRentDiscountForTier(uint128 red, uint128 purple, uint128 black);

    event SetStakingLevelForTier(uint128 red, uint128 purple, uint128 black);

    event SetRequiredTimeForTier(uint128 red, uint128 purple, uint128 black);

    event SetWithdrawDelayForTier(uint128 red, uint128 purple, uint128 black);

    event EmergencyWithdraw(address indexed account, uint256 amount);

    // Functions

    function deposit(uint128 _amount) external;

    function withdraw(uint128 _amount) external;

    function emergencyWithdraw(address _address) external;

    function getUserTotalStaked(address _address) external view returns (uint128);

    function getAcceptedTokenAddress() external view returns (address);

    function getPenaltyPercentage() external view returns (uint128);

    function getTotalStakedBalance() external view returns (uint128);

    function setAcceptedToken(address _address) external;

    function setBlacklistContract(address _address) external;

    function getRentDiscountByAddress(address _address) external view returns (uint128);

    function setRentDiscount(uint128[] memory _rentDiscount) external;

    function setStakingLevel(uint128[] memory _stakingLevel) external;

    function setRequiredStakingDays(uint128[] memory _requiredStakingDays) external;

    function setWithdrawDelay(uint128[] memory _withdrawDelayTier) external;

    function setPenaltyPercentage(uint128 _penaltyPercentage) external;
}
