// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import "./../interfaces/IBlacklist.sol";
import "./../interfaces/IStakingEarn.sol";

contract StakingEarn is IStakingEarn, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeCastUpgradeable for uint256;

    uint32 private constant ONE_YEAR_IN_SECONDS = 365 days;
    uint32 public aprPercentage;

    address public rewardDistributor;
    IERC20Upgradeable public acceptedToken;
    IBlacklist private blacklistContract;

    struct PoolData {
        uint256 cap;
        uint256 totalStaked;
        uint256 lockDuration;
        uint256 startTime;
        uint256 endTime;
        uint256 personalCap;
        uint256 minInvest;
        uint64 apr; // 100 is 1%
    }

    PoolData[] public pools;

    struct UserInfo {
        uint256 balance;
        uint256 joinTime; // for calculating pending rewards
        uint256 updatedTime; // for calculating pending rewards
        uint256 reward;
    }

    // poolId => (staker address => UserInfo)
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // staker address => total amount staked in every pools
    mapping(address => uint256) public userStakingData;

    function initialize(
        address _acceptedToken,
        address _rewardDistributor,
        address _blacklistContractAddress
    ) public initializer {
        require(
            _rewardDistributor != address(0) && _acceptedToken != address(0),
            "StakingEarn: not allow zero address"
        );

        __Ownable_init();

        setAcceptedToken(_acceptedToken);
        setRewardDistributor(_rewardDistributor);
        setBlacklistContract(_blacklistContractAddress);
        aprPercentage = 10000;
    }

    modifier notBlacklisted() {
        require(blacklistContract.isBlacklisted(msg.sender) == false, "System: account is blacklisted");
        require(!blacklistContract.isContract(msg.sender), "System: unable to call by contract");
        _;
    }

    function createPool(
        uint256 _cap,
        uint64 _apr,
        uint256 _lockDuration,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _personalCap,
        uint256 _minInvest,
        string memory _poolName
    ) external override onlyOwner {
        require(_endTime >= block.timestamp && _endTime > _startTime, "StakingEarn: invalid end join time");
        require(_minInvest < _personalCap && _minInvest > 0, "StakingEarn: invalid minimum investment");
        pools.push(
            PoolData({
                cap: _cap,
                totalStaked: 0,
                apr: _apr,
                lockDuration: _lockDuration,
                startTime: _startTime,
                endTime: _endTime,
                personalCap: _personalCap,
                minInvest: _minInvest
            })
        );
        emit CreatePool(
            pools.length - 1,
            _poolName,
            _apr,
            _cap,
            _lockDuration,
            _startTime,
            _endTime,
            _personalCap,
            _minInvest
        );
    }

    function stake(uint128 _poolId, uint128 _amount) external override nonReentrant notBlacklisted {
        ensurePoolIdIsCorect(_poolId);

        address account = msg.sender;
        PoolData storage pool = pools[_poolId];

        require(_amount >= pool.minInvest, "StakingEarn: must stake more than pool's min invest");

        UserInfo storage stakingData = userInfo[_poolId][account];
        require(stakingData.balance + _amount <= pool.personalCap, "StakingEarn: exceed pool personal cap");

        require(block.timestamp >= pool.startTime, "StakingEarn: pool is not started yet");

        require(block.timestamp <= pool.endTime, "StakingEarn: pool is already closed");

        if (pool.cap > 0) {
            require(pool.totalStaked + _amount <= pool.cap, "StakingEarn: pool is full");
        }

        _harvest(_poolId, account);

        stakingData.balance += _amount;
        stakingData.joinTime = block.timestamp;
        pool.totalStaked += _amount;
        acceptedToken.safeTransferFrom(account, address(this), _amount);

        // update userStakingData
        userStakingData[msg.sender] = userStakingData[msg.sender] + _amount;

        emit Stake(_poolId, account, _amount);
    }

    function unstake(uint256 _poolId, uint256 _amount) external override nonReentrant notBlacklisted {
        ensurePoolIdIsCorect(_poolId);
        address account = msg.sender;
        PoolData storage pool = pools[_poolId];
        UserInfo storage stakingData = userInfo[_poolId][account];

        require(block.timestamp >= stakingData.joinTime + pool.lockDuration, "StakingEarn: still locked");

        require(stakingData.balance >= 0 && _amount <= stakingData.balance, "StakingEarn: invalid withdraw amount");

        _harvest(_poolId, account);

        pool.totalStaked -= _amount;
        stakingData.balance = stakingData.balance - _amount;

        // update userStakingData
        userStakingData[msg.sender] -= _amount;

        acceptedToken.safeTransfer(account, _amount);

        emit Unstake(_poolId, account, _amount);
    }

    function claimReward(uint256 _poolId) external override nonReentrant notBlacklisted {
        ensurePoolIdIsCorect(_poolId);
        address account = msg.sender;
        PoolData storage pool = pools[_poolId];
        UserInfo storage stakingData = userInfo[_poolId][account];

        require(block.timestamp >= pool.endTime, "StakingEarn: reward still locked");
        require(stakingData.reward >= 0, "StakingEarn: invalid withdraw amount");

        _harvest(_poolId, msg.sender);

        uint256 reward = stakingData.reward;

        if (stakingData.reward > 0) {
            require(rewardDistributor != address(0), "StakingEarn: invalid reward distributor");

            stakingData.reward = 0;
            acceptedToken.safeTransferFrom(rewardDistributor, account, reward);
        }
        emit RewardsHarvested(_poolId, account, reward);
    }

    function pendingReward(uint256 _poolId, address _account) public view override returns (uint256 reward) {
        ensurePoolIdIsCorect(_poolId);
        PoolData storage pool = pools[_poolId];
        UserInfo storage stakingData = userInfo[_poolId][_account];

        uint256 startTime = stakingData.updatedTime > 0 ? stakingData.updatedTime : block.timestamp;

        uint256 endTime = block.timestamp < pool.endTime ? block.timestamp : pool.endTime;

        uint256 stakedTimeInSeconds = endTime > startTime ? endTime - startTime : 0;

        uint256 pendingRewards = ((stakingData.balance * stakedTimeInSeconds * pool.apr) / ONE_YEAR_IN_SECONDS) /
            aprPercentage;

        reward = stakingData.reward + pendingRewards;
    }

    function setAcceptedToken(address _address) public override onlyOwner {
        require(_address != address(0), "StakingEarn: not allow zero address");
        acceptedToken = IERC20Upgradeable(_address);
        emit SetAcceptedToken(_address);
    }

    function setRewardDistributor(address _address) public override onlyOwner {
        require(_address != address(0), "StakingEarn: not allow zero address");
        rewardDistributor = _address;
        emit SetRewardDistributor(_address);
    }

    function setAprPercentage(uint32 _percentage) public override onlyOwner {
        aprPercentage = _percentage;
        emit SetAprPercentage(_percentage);
    }

    function setBlacklistContract(address _address) public override onlyOwner {
        require(_address != address(0), "StakingEarn: not allow zero address");
        blacklistContract = IBlacklist(_address);
        emit SetBlacklistContract(_address);
    }

    function emergencyWithdraw(address _address) external override nonReentrant onlyOwner {
        uint256 totalWithdrawBalance = acceptedToken.balanceOf(address(this));
        acceptedToken.safeTransfer(_address, totalWithdrawBalance);
        emit EmergencyWithdraw(_address, totalWithdrawBalance);
    }

    // View functions
    function getAcceptedTokenAddress() public view override returns (address) {
        return address(acceptedToken);
    }

    function getPoolInfo(
        uint256 _poolId
    ) public view returns (uint256, uint64, uint256, uint256, uint256, uint256, uint256) {
        ensurePoolIdIsCorect(_poolId);
        PoolData storage pool = pools[_poolId];
        return (
            pool.cap,
            pool.apr,
            pool.lockDuration,
            pool.startTime,
            pool.endTime,
            pool.personalCap,
            pool.totalStaked
        );
    }

    // Private functions
    function ensurePoolIdIsCorect(uint256 _poolId) private view {
        require(_poolId < pools.length, "StakingEarn: Pool are not exist");
    }

    function _harvest(uint256 _poolId, address _account) private {
        UserInfo storage stakingData = userInfo[_poolId][_account];

        stakingData.reward = pendingReward(_poolId, _account);
        stakingData.updatedTime = block.timestamp;
    }
}
