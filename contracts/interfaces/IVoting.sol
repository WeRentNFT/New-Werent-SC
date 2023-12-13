// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;

interface IVoting {
    enum VoteType {
        DownVote,
        UpVote
    }

    enum ProposalStatus {
        Passed,
        Voting,
        Failed,
        Invalid
    }

    // Events
    event ProposalCreated(
        uint128 proposalId,
        address proposer,
        string _key,
        uint256 duration,
        uint256 startProposal,
        uint256 endProposal
    );

    event Voted(uint128 idProposal, address voter, VoteType voteType);

    event SetMinVoteBalance(uint256 minVoteBalance);

    event SetMinProposeBalance(uint256 minProposeBalance);

    event SetMinNumberOfVote(uint128 minNumberOfVote);

    event SetFeeToken(address feeTokenAddress);

    event SetWeToken(address weTokenAddress);

    event SetBlacklistContract(address blacklistContractAddress);

    event UpdateProposal(
        uint128 proposalId,
        uint256 duration,
        uint256 minVoteBalance,
        uint128 passPercentage,
        uint128 minNumberOfVote
    );

    event SetProposalFee(uint256 proposalFee);

    event Withdraw(uint256 amount, address to);

    event SetDuration(uint256 duration);

    event SetPassPercentage(uint128 passPercentage);

    // Functions

    function createProposal(string memory _key) external;

    function vote(uint128 _proposalId, VoteType _voteType) external;

    function withdraw(uint256 _amount, address _to) external;

    function setMinVoteBalance(uint256 _minVoteBalance) external;

    function setMinProposeBalance(uint256 _minProposeBalance) external;

    function setFeeToken(address _address) external;

    function setBlacklistContract(address _address) external;

    function setMinNumberOfVote(uint128 _minNumberOfVote) external;

    function setWeToken(address _address) external;

    function setDuration(uint256 _duration) external;

    function setProposalFee(uint256 _proposalFee) external;

    function updateProposal(
        uint128 _proposalId,
        uint256 _duration,
        uint256 _minVoteBalance,
        uint128 _passPercentage,
        uint128 _minNumberOfVote
    ) external;

    function setPassPercentage(uint128 _passPercentage) external;

    function getProposalStatus(uint128 _proposalId) external view returns (ProposalStatus, uint128, uint128);
}
