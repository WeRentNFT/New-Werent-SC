// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./../interfaces/IStakingTier.sol";
import "./../interfaces/IBlacklist.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

contract StakingTier is IStakingTier, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeCastUpgradeable for uint256;

    enum TierList {
        White,
        Red,
        Purple,
        Black
    }

    uint256 private constant NUMBER_TIER = 3;

    uint128 private penaltyPercentgage;

    uint128 private totalStakedBalance;

    IERC20Upgradeable public acceptedToken;
    IBlacklist private blacklistContract;

    mapping(address => StakingData) private stakingDatas;

    struct StakingData {
        uint128 balance;
        uint128 startStakedAt;
    }

    struct TierData {
        uint128 stakingTier;
        uint128 rentDiscountTier;
        uint128 requiredStakingDaysTier;
        uint128 withdrawDelayTier;
    }

    mapping(uint128 => TierData) private tierDatas;

    function initialize(
        address _acceptedTokenAddress,
        address _blacklistContractAddress,
        uint128 _penaltyPercentage,
        uint128[] memory _stakingTier,
        uint128[] memory _discountTier,
        uint128[] memory _requiredStakingDaysTier,
        uint128[] memory _withdrawDelayTier
    ) public initializer {
        require(_acceptedTokenAddress != address(0), "Staking: not allow zero address");

        __Ownable_init();

        setAcceptedToken(_acceptedTokenAddress);
        setBlacklistContract(_blacklistContractAddress);
        setPenaltyPercentage(_penaltyPercentage);

        // setting for WHITE tier
        tierDatas[0].stakingTier = 0;
        tierDatas[0].rentDiscountTier = 0;
        tierDatas[0].requiredStakingDaysTier = 0;
        tierDatas[0].withdrawDelayTier = 0;

        setRentDiscount(_discountTier);
        setStakingLevel(_stakingTier);
        setRequiredStakingDays(_requiredStakingDaysTier);
        setWithdrawDelay(_withdrawDelayTier);
    }

    modifier notBlacklisted() {
        require(blacklistContract.isBlacklisted(msg.sender) == false, "System: account is blacklisted");
        require(!blacklistContract.isContract(msg.sender), "System: unable to call by contract");
        _;
    }

    function getRentDiscountByAddress(address _address) public view override returns (uint128) {
        TierList addressTier = getTier(_address);
        return tierDatas[uint128(addressTier)].rentDiscountTier;
    }

    function getLevelStakingNeed(uint128 _level) public view returns (uint128) {
        return tierDatas[_level].stakingTier;
    }

    function setRentDiscount(uint128[] memory _rentDiscount) public override onlyOwner {
        ensureLenTier(_rentDiscount);
        for (uint128 i = 0; i < _rentDiscount.length; i++) {
            require(_rentDiscount[i] < 10001, "StakingTier: cannot set rent discount greather than 100%");
            tierDatas[i + 1].rentDiscountTier = _rentDiscount[i];
        }
        emit SetRentDiscountForTier(_rentDiscount[0], _rentDiscount[1], _rentDiscount[2]);
    }

    function setStakingLevel(uint128[] memory _stakingLevel) public override onlyOwner {
        ensureLenTier(_stakingLevel);
        for (uint128 i = 0; i < _stakingLevel.length; i++) {
            ensureValidData(_stakingLevel[i]);
            tierDatas[i + 1].stakingTier = _stakingLevel[i];
        }
        emit SetStakingLevelForTier(_stakingLevel[0], _stakingLevel[1], _stakingLevel[2]);
    }

    function setRequiredStakingDays(uint128[] memory _requiredStakingDays) public override onlyOwner {
        ensureLenTier(_requiredStakingDays);
        for (uint128 i = 0; i < _requiredStakingDays.length; i++) {
            // ensureValidData(_requiredStakingDays[i]);
            tierDatas[i + 1].requiredStakingDaysTier = _requiredStakingDays[i];
        }
        emit SetStakingLevelForTier(_requiredStakingDays[0], _requiredStakingDays[1], _requiredStakingDays[2]);
    }

    function setWithdrawDelay(uint128[] memory _withdrawDelayTier) public override onlyOwner {
        ensureLenTier(_withdrawDelayTier);
        for (uint128 i = 0; i < _withdrawDelayTier.length; i++) {
            // ensureValidData(_withdrawDelayTier[i]);
            tierDatas[i + 1].withdrawDelayTier = _withdrawDelayTier[i];
        }
        emit SetWithdrawDelayForTier(_withdrawDelayTier[0], _withdrawDelayTier[1], _withdrawDelayTier[2]);
    }

    function multipleConfig(
        uint128[] memory _rentDiscount,
        uint128[] memory _stakingLevel,
        uint128[] memory _requiredStakingDays,
        uint128[] memory _withdrawDelayTier
    ) public onlyOwner {
        setRentDiscount(_rentDiscount);
        setStakingLevel(_stakingLevel);
        setRequiredStakingDays(_requiredStakingDays);
        setWithdrawDelay(_withdrawDelayTier);
    }

    function getAcceptedTokenAddress() public view override returns (address) {
        return address(acceptedToken);
    }

    function setAcceptedToken(address _address) public override onlyOwner {
        require(_address != address(0), "Staking: invalid token address");
        acceptedToken = IERC20Upgradeable(_address);
        emit SetAcceptedToken(_address);
    }

    function setBlacklistContract(address _address) public override onlyOwner {
        require(_address != address(0), "Staking: invalid token address");
        blacklistContract = IBlacklist(_address);
        emit SetBlacklistContract(_address);
    }

    function getPenaltyPercentage() public view override returns (uint128) {
        return penaltyPercentgage;
    }

    function setPenaltyPercentage(uint128 _penaltyPercentage) public override onlyOwner {
        penaltyPercentgage = _penaltyPercentage;
        emit SetPenaltyPercentage(_penaltyPercentage);
    }

    function getTotalStakedBalance() public view override returns (uint128) {
        return totalStakedBalance;
    }

    function deposit(uint128 _amount) external override nonReentrant notBlacklisted {
        address account = msg.sender;
        require(_amount <= acceptedToken.balanceOf(account), "Staking: invalid deposit amount");

        StakingData storage stakingData = stakingDatas[account];

        stakingData.balance += _amount;
        if (stakingData.startStakedAt == 0) {
            stakingData.startStakedAt = block.timestamp.toUint128();
        }

        totalStakedBalance += _amount;

        acceptedToken.safeTransferFrom(account, address(this), _amount);
        emit Deposit(account, _amount);
    }

    function withdraw(uint128 _amount) external override nonReentrant notBlacklisted {
        address account = msg.sender;
        StakingData storage stakingData = stakingDatas[account];

        require(_amount >= 0 && stakingData.balance >= _amount, "Staking: invalid withdraw amount");
        uint128 addressTier = uint128(getTier(account));
        uint128 requiredStakingDays = tierDatas[addressTier].requiredStakingDaysTier;
        uint128 withdrawDelay = tierDatas[addressTier].withdrawDelayTier;

        uint128 withdrawAmount = _amount;

        // calculate penalty for early withdraw
        uint128 penalty;
        bool isWithdrawEarly = false;
        if (block.timestamp < stakingData.startStakedAt + withdrawDelay + requiredStakingDays) {
            isWithdrawEarly = true;
            penalty = (penaltyPercentgage * stakingData.balance) / 10000;

            // early withdraw will be penalized and downgraded to WHITE
            stakingData.startStakedAt = block.timestamp.toUint128();
        }

        uint128 remainAmount = stakingData.balance - _amount;

        if (penalty <= remainAmount) {
            stakingData.balance = stakingData.balance - (_amount + penalty);
            totalStakedBalance = totalStakedBalance - (_amount + penalty);
            remainAmount -= penalty;
        } else {
            stakingData.balance = stakingData.balance - _amount;
            totalStakedBalance -= _amount;
            withdrawAmount -= penalty;
        }

        uint256 currentTimestamp = block.timestamp;
        uint256 delayTime;
        if (isWithdrawEarly == false) {
            if (
                remainAmount < tierDatas[uint128(TierList.Black)].stakingTier &&
                remainAmount >= tierDatas[uint128(TierList.Purple)].stakingTier
            ) {
                delayTime = tierDatas[uint128(TierList.Purple)].requiredStakingDaysTier;
            } else if (
                remainAmount < tierDatas[uint128(TierList.Purple)].stakingTier &&
                remainAmount >= tierDatas[uint128(TierList.Red)].stakingTier
            ) {
                delayTime = tierDatas[uint128(TierList.Red)].requiredStakingDaysTier;
            }
            stakingData.startStakedAt = (currentTimestamp - delayTime).toUint128();
        }

        // withdraw all case
        if (remainAmount == 0) {
            // stakingData.startStakedAt = 0;
            stakingData.startStakedAt = block.timestamp.toUint128();
        }

        acceptedToken.safeTransfer(account, withdrawAmount);

        if (penalty > 0) {
            address owner = owner();
            acceptedToken.safeTransfer(owner, penalty);
        }
        emit Withdraw(account, withdrawAmount);
    }

    function emergencyWithdraw(address _address) external override nonReentrant onlyOwner {
        uint128 totalWithdrawBalance = totalStakedBalance;
        totalStakedBalance = 0;

        acceptedToken.safeTransfer(_address, totalWithdrawBalance);
        emit EmergencyWithdraw(_address, totalWithdrawBalance);
    }

    // View functions

    function getUserTotalStaked(address _address) public view override returns (uint128) {
        return stakingDatas[_address].balance;
    }

    // private functions
    function ensureLenTier(uint128[] memory _data) private pure {
        require(_data.length == NUMBER_TIER, "Data for set isn't fit");
    }

    function ensureValidData(uint128 _data) private pure {
        require(_data > 0, "Data must bigger than 0");
    }

    function getTier(address _address) public view returns (TierList) {
        uint128 totalStaked = getUserTotalStaked(_address);
        uint128 startStakedAt = stakingDatas[_address].startStakedAt;
        uint256 currentTimestamp = block.timestamp;
        if (
            totalStaked >= tierDatas[uint128(TierList.Black)].stakingTier &&
            currentTimestamp >= tierDatas[uint128(TierList.Black)].requiredStakingDaysTier + startStakedAt
        ) return TierList.Black;
        if (
            totalStaked >= tierDatas[uint128(TierList.Purple)].stakingTier &&
            currentTimestamp >= tierDatas[uint128(TierList.Purple)].requiredStakingDaysTier + startStakedAt
        ) return TierList.Purple;
        if (
            totalStaked >= tierDatas[uint128(TierList.Red)].stakingTier &&
            currentTimestamp >= tierDatas[uint128(TierList.Red)].requiredStakingDaysTier + startStakedAt
        ) return TierList.Red;
        return TierList.White;
    }

    function getTierDatas()
        public
        view
        returns (
            uint128 redMinWe,
            uint128 redDiscount,
            uint128 redRequiredStakingDays,
            uint128 redWithdrawDelayDays,
            uint128 purpleMinWe,
            uint128 purpleDiscount,
            uint128 purpleRequiredStakingDays,
            uint128 purpleWithdrawDelayDays,
            uint128 blackMinWe,
            uint128 blackDiscount,
            uint128 blackRequiredStakingDays,
            uint128 blackWithdrawDelayDays
        )
    {
        redMinWe = tierDatas[uint128(TierList.Red)].stakingTier;
        redDiscount = tierDatas[uint128(TierList.Red)].rentDiscountTier;
        redRequiredStakingDays = tierDatas[uint128(TierList.Red)].requiredStakingDaysTier;
        redWithdrawDelayDays = tierDatas[uint128(TierList.Red)].withdrawDelayTier;

        purpleMinWe = tierDatas[uint128(TierList.Purple)].stakingTier;
        purpleDiscount = tierDatas[uint128(TierList.Purple)].rentDiscountTier;
        purpleRequiredStakingDays = tierDatas[uint128(TierList.Purple)].requiredStakingDaysTier;
        purpleWithdrawDelayDays = tierDatas[uint128(TierList.Purple)].withdrawDelayTier;

        blackMinWe = tierDatas[uint128(TierList.Black)].stakingTier;
        blackDiscount = tierDatas[uint128(TierList.Black)].rentDiscountTier;
        blackRequiredStakingDays = tierDatas[uint128(TierList.Black)].requiredStakingDaysTier;
        blackWithdrawDelayDays = tierDatas[uint128(TierList.Black)].withdrawDelayTier;
    }

    function timeToUpgrade(address _address) public view returns (uint256 remainTime, TierList currentTier) {
        currentTier = getTier(_address);
        uint128 totalStaked = getUserTotalStaked(_address);
        uint128 startStakedAt = stakingDatas[_address].startStakedAt;
        uint256 currentTimestamp = block.timestamp;

        if (currentTier == TierList.Black) {
            remainTime = 0;
        } else if (currentTier == TierList.Purple) {
            if (totalStaked >= tierDatas[uint128(TierList.Black)].stakingTier) {
                remainTime =
                    tierDatas[uint128(TierList.Black)].requiredStakingDaysTier +
                    startStakedAt -
                    currentTimestamp;
            } else {
                remainTime = 0;
            }
        } else if (currentTier == TierList.Red) {
            if (totalStaked >= tierDatas[uint128(TierList.Black)].stakingTier) {
                remainTime =
                    tierDatas[uint128(TierList.Black)].requiredStakingDaysTier +
                    startStakedAt -
                    currentTimestamp;
            } else if (totalStaked >= tierDatas[uint128(TierList.Purple)].stakingTier) {
                remainTime =
                    tierDatas[uint128(TierList.Purple)].requiredStakingDaysTier +
                    startStakedAt -
                    currentTimestamp;
            } else {
                remainTime = 0;
            }
        } else {
            if (totalStaked >= tierDatas[uint128(TierList.Black)].stakingTier) {
                remainTime =
                    tierDatas[uint128(TierList.Black)].requiredStakingDaysTier +
                    startStakedAt -
                    currentTimestamp;
            } else if (totalStaked >= tierDatas[uint128(TierList.Purple)].stakingTier) {
                remainTime =
                    tierDatas[uint128(TierList.Purple)].requiredStakingDaysTier +
                    startStakedAt -
                    currentTimestamp;
            } else if (totalStaked >= tierDatas[uint128(TierList.Red)].stakingTier) {
                remainTime =
                    tierDatas[uint128(TierList.Red)].requiredStakingDaysTier +
                    startStakedAt -
                    currentTimestamp;
            } else {
                remainTime = 0;
            }
        }
    }
}
