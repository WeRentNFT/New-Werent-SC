// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;

interface IStakingEarn {
    event CreatePool(
        uint256 poolId,
        string poolName,
        uint64 apr,
        uint256 cap,
        uint256 lockDuration,
        uint256 startTime,
        uint256 endTime,
        uint256 personalCap,
        uint256 minInvest
    );
    event Stake(uint256 poolId, address account, uint256 amount);
    event Unstake(uint256 poolId, address account, uint256 withdrawBalance);
    event SetAcceptedToken(address acceptedToken);
    event SetRewardDistributor(address rewardDistributor);
    event RewardsHarvested(uint256 indexed poolId, address indexed account, uint256 reward);
    event SetAprPercentage(uint32 percentage);
    event SetBlacklistContract(address blacklistContractAddress);
    event EmergencyWithdraw(address beneficiary, uint256 totalWithdrawBalance);

    // Functions

    function createPool(
        uint256 _cap,
        uint64 _apr,
        uint256 _lockDuration,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _personalCap,
        uint256 _minInvest,
        string memory _poolName
    ) external;

    function stake(uint128 _poolId, uint128 _amount) external;

    function unstake(uint256 _poolId, uint256 _amount) external;

    function claimReward(uint256 _poolId) external;

    function pendingReward(uint256 _poolId, address _account) external view returns (uint256 reward);

    function setAcceptedToken(address _address) external;

    function setRewardDistributor(address _address) external;

    function setAprPercentage(uint32 _percentage) external;

    function setBlacklistContract(address _address) external;

    function emergencyWithdraw(address _address) external;

    function getAcceptedTokenAddress() external view returns (address);
}
