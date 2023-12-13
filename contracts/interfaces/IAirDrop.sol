// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;

interface IAirDrop {
    event Airdrop(uint256 indexed airdropId, bytes32 merkleRoot);

    event Claim(address indexed beneficiary, address indexed tokenAddress, uint256 tokenId, uint256 airdropId);

    event SetBlacklistContract(address blacklistContractAddress);

    event InactiveUser(
        address indexed account,
        address indexed collectionAddress,
        uint256 indexed airdropId,
        uint256 tokenId
    );

    event ActiveUser(
        address indexed account,
        address indexed collectionAddress,
        uint256 indexed airdropId,
        uint256 tokenId
    );

    event SetTreasuryAddress(address treasuryAddress);

    function airdrop(bytes32 _merkleRoot) external;

    function claim(uint256 _airdropId, address collectionAddress, uint256 tokenId, bytes32[] calldata proof) external;

    function setInactiveUser(
        uint256 _airdropId,
        address _account,
        address _collectionAddress,
        uint256 _tokenId
    ) external;
}
