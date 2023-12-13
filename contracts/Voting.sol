// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import "./interfaces/IVoting.sol";
import "./interfaces/IBlacklist.sol";

contract Voting is IVoting, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeCastUpgradeable for uint256;

    IERC20Upgradeable public feeToken;
    IERC20Upgradeable public weToken;
    IBlacklist private blacklistContract;
    uint128 private proposalId;
    uint256 public minProposeBalance;
    uint256 public proposalFee;
    uint256 public minVoteBalance;
    uint128 public minNumberOfVote;
    uint256 public duration;
    uint128 public passPercentage;
    struct Proposal {
        address proposer;
        uint256 startProposal;
        uint256 endProposal;
        uint256 duration;
        uint256 minVoteBalance;
        uint128 numberOfUpvote;
        uint128 numberOfDownvote;
        uint128 passPercentage;
        uint128 minNumberOfVote;
    }

    mapping(uint128 => Proposal) public proposals;

    mapping(uint128 => mapping(address => bool)) public voter;

    function initialize(
        address _feeToken,
        address _weToken,
        address _blacklistContractAddress,
        uint256 _minProposeBalance,
        uint256 _proposalFee,
        uint256 _minVoteBalance,
        uint128 _minNumberOfVote,
        uint256 _duration
    ) public initializer {
        __Ownable_init();
        setFeeToken(_feeToken);
        setWeToken(_weToken);
        setBlacklistContract(_blacklistContractAddress);
        setMinProposeBalance(_minProposeBalance);
        setProposalFee(_proposalFee);
        setMinVoteBalance(_minVoteBalance);
        setMinNumberOfVote(_minNumberOfVote);
        setDuration(_duration);
        setPassPercentage(50);
        proposalId = 0;
    }

    modifier notBlacklisted() {
        require(blacklistContract.isBlacklisted(msg.sender) == false, "System: account is blacklisted");
        require(!blacklistContract.isContract(msg.sender), "System: unable to call by contract");
        _;
    }

    function createProposal(string memory _key) public override notBlacklisted {
        require(weToken.balanceOf(msg.sender) >= minProposeBalance, "Voting: insufficient WE token");

        feeToken.transferFrom(msg.sender, address(this), proposalFee);
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + duration;
        proposals[proposalId] = Proposal(
            msg.sender,
            startTime,
            endTime,
            duration,
            minVoteBalance,
            0,
            0,
            passPercentage,
            minNumberOfVote
        );
        emit ProposalCreated(proposalId, msg.sender, _key, duration, startTime, endTime);
        proposalId++;
    }

    function vote(uint128 _proposalId, VoteType _voteType) public override notBlacklisted {
        require(
            weToken.balanceOf(msg.sender) >= proposals[_proposalId].minVoteBalance,
            "Voting: not have enough WE token"
        );
        require(proposals[_proposalId].endProposal > block.timestamp, "Voting: time to vote expired");
        require(voter[_proposalId][msg.sender] == false, "Voting: already voted");

        if (_voteType == VoteType.UpVote) {
            proposals[_proposalId].numberOfUpvote++;
        } else {
            proposals[_proposalId].numberOfDownvote++;
        }
        voter[_proposalId][msg.sender] = true;
        emit Voted(_proposalId, msg.sender, _voteType);
    }

    function withdraw(uint256 _amount, address _to) external override onlyOwner {
        require(_amount <= feeToken.balanceOf(address(this)), "Voting: exceed maximum token");
        feeToken.safeTransfer(_to, _amount);
        emit Withdraw(_amount, _to);
    }

    function setMinVoteBalance(uint256 _minVoteBalance) public override onlyOwner {
        require(_minVoteBalance > 0, "Voting: minimum voting balance must greater than zero");
        minVoteBalance = _minVoteBalance;
        emit SetMinVoteBalance(_minVoteBalance);
    }

    function setMinProposeBalance(uint256 _minProposeBalance) public override onlyOwner {
        require(_minProposeBalance > 0, "Voting: minimum proposing balance must greater than zero");
        minProposeBalance = _minProposeBalance;
        emit SetMinProposeBalance(_minProposeBalance);
    }

    function setMinNumberOfVote(uint128 _minNumberOfVote) public override onlyOwner {
        require(_minNumberOfVote > 0, "Voting: minimum number of vote must greater than zero");
        minNumberOfVote = _minNumberOfVote;
        emit SetMinNumberOfVote(_minNumberOfVote);
    }

    function setFeeToken(address _address) public override onlyOwner {
        require(_address != address(0), "Voting: invalid token address");
        feeToken = IERC20Upgradeable(_address);
        emit SetFeeToken(_address);
    }

    function setBlacklistContract(address _address) public override onlyOwner {
        require(_address != address(0), "Voting: invalid token address");
        blacklistContract = IBlacklist(_address);
        emit SetBlacklistContract(_address);
    }

    function setWeToken(address _address) public override onlyOwner {
        require(_address != address(0), "Voting: invalid token address");
        weToken = IERC20Upgradeable(_address);
        emit SetWeToken(_address);
    }

    function setProposalFee(uint256 _proposalFee) public override onlyOwner {
        require(_proposalFee > 0, "Voting: proposal fee must greater than zero");
        proposalFee = _proposalFee;
        emit SetProposalFee(_proposalFee);
    }

    function setDuration(uint256 _duration) public override onlyOwner {
        require(_duration > 0, "Voting: duration must greater than zero");
        duration = _duration;
        emit SetDuration(_duration);
    }

    function setPassPercentage(uint128 _passPercentage) public override onlyOwner {
        require(_passPercentage > 0 && _passPercentage < 101, "Voting: invalid pass percentage");
        passPercentage = _passPercentage;
        emit SetPassPercentage(passPercentage);
    }

    function updateProposal(
        uint128 _proposalId,
        uint256 _duration,
        uint256 _minVoteBalance,
        uint128 _passPercentage,
        uint128 _minNumberOfVote
    ) public override onlyOwner {
        require(_minNumberOfVote > 0, "Voting: minimum number of vote must greater than zero");
        require(_passPercentage >= 0 && _passPercentage < 101, "Voting: invalid pass percentage");
        require(_minNumberOfVote > 0, "Voting: minimum number of vote must greater than zero");

        Proposal storage proposal = proposals[_proposalId];
        (ProposalStatus currentStatus, , ) = getProposalStatus(_proposalId);
        require(currentStatus == ProposalStatus.Voting, "Voting: this proposal ended");

        require(_duration > 0 && proposal.startProposal + _duration > block.timestamp, "Voting: Invalid duration");

        proposal.duration = _duration;
        proposal.endProposal = proposal.startProposal + _duration;
        proposal.minVoteBalance = _minVoteBalance;
        proposal.passPercentage = _passPercentage;
        proposal.minNumberOfVote = _minNumberOfVote;

        emit UpdateProposal(_proposalId, _duration, _minVoteBalance, _passPercentage, _minNumberOfVote);
    }

    function getProposalStatus(
        uint128 _proposalId
    ) public view override returns (ProposalStatus proposalStatus, uint128 numberOfUpvote, uint128 numberOfDownvote) {
        Proposal storage proposal = proposals[_proposalId];
        uint256 currentTime = block.timestamp;
        numberOfUpvote = proposal.numberOfUpvote;
        numberOfDownvote = proposal.numberOfDownvote;
        if (currentTime <= proposal.endProposal) {
            proposalStatus = ProposalStatus.Voting;
        } else {
            uint128 totalVote = proposal.numberOfUpvote + proposal.numberOfDownvote;
            if (totalVote < proposal.minNumberOfVote) {
                proposalStatus = ProposalStatus.Invalid;
            } else if ((proposal.numberOfUpvote * 100) / totalVote < proposal.passPercentage) {
                proposalStatus = ProposalStatus.Failed;
            } else {
                proposalStatus = ProposalStatus.Passed;
            }
        }
    }
}
