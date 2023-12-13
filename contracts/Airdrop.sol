// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "./interfaces/IAirDrop.sol";
import "./interfaces/IBlacklist.sol";

contract Airdrop is IAirDrop, Initializable, PausableUpgradeable, OwnableUpgradeable {
    address public treasuryAddress;

    uint256 public airdropId;

    mapping(uint256 => bytes32) private airdropDatas;

    mapping(bytes32 => bool) private airdropCreated;

    mapping(bytes32 => bool) private airdropClaimed;

    mapping(bytes32 => bool) private airdropBlacklist;

    struct AirdropInfo {
        uint256 airdropId;
        address account;
        address collectionAddress;
        uint256 tokenId;
    }

    IBlacklist private blacklistContract;

    function initialize(address _treasuryAddress, address _blacklistContractAddress) public initializer {
        __Pausable_init();
        __Ownable_init();

        setTreasuryAddress(_treasuryAddress);
        setBlacklistContract(_blacklistContractAddress);
    }

    modifier notBlacklisted() {
        require(blacklistContract.isBlacklisted(msg.sender) == false, "System: account is blacklisted");
        require(!blacklistContract.isContract(msg.sender), "System: unable to call by contract");
        _;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function airdrop(bytes32 _merkleRoot) external override onlyOwner whenNotPaused {
        require(!airdropCreated[_merkleRoot], "Airdrop root is created");
        airdropDatas[airdropId] = _merkleRoot;
        airdropCreated[_merkleRoot] = true;
        emit Airdrop(airdropId, _merkleRoot);
        airdropId++;
    }

    function claim(
        uint256 _airdropId,
        address _collectionAddress,
        uint256 _tokenId,
        bytes32[] calldata proof
    ) external override whenNotPaused notBlacklisted {
        require(
            _verify(airdropDatas[_airdropId], _leaf(msg.sender, _collectionAddress, _tokenId), proof),
            "Invalid merkle proof"
        );
        bytes32 airdropKey = _hashUniqueAirdrop(_airdropId, msg.sender, _collectionAddress, _tokenId);
        require(!airdropBlacklist[airdropKey], "User was inactive for this tokenId");
        require(!airdropClaimed[airdropKey], "Airdrop is claimed");
        IERC721Upgradeable(_collectionAddress).safeTransferFrom(treasuryAddress, msg.sender, _tokenId);
        airdropClaimed[airdropKey] = true;
        emit Claim(msg.sender, _collectionAddress, _tokenId, _airdropId);
    }

    function isClaimed(
        uint256 _airdropId,
        address _account,
        address _collectionAddress,
        uint256 _tokenId
    ) public view returns (bool) {
        return airdropClaimed[_hashUniqueAirdrop(_airdropId, _account, _collectionAddress, _tokenId)];
    }

    function setInactiveUser(
        uint256 _airdropId,
        address _account,
        address _collectionAddress,
        uint256 _tokenId
    ) external override onlyOwner whenNotPaused {
        require(!isClaimed(_airdropId, _account, _collectionAddress, _tokenId), "Airdrop is claimed");
        airdropBlacklist[_hashUniqueAirdrop(_airdropId, _account, _collectionAddress, _tokenId)] = true;
        emit InactiveUser(_account, _collectionAddress, _airdropId, _tokenId);
    }

    function setBlacklistContract(address _address) public onlyOwner {
        require(_address != address(0), "Airdrop: not allow zero address");
        blacklistContract = IBlacklist(_address);
        emit SetBlacklistContract(_address);
    }

    function setTreasuryAddress(address _address) public onlyOwner {
        require(_address != address(0), "Airdrop: not allow zero address");
        treasuryAddress = _address;
        emit SetTreasuryAddress(_address);
    }

    function isInactive(
        uint256 _airdropId,
        address _account,
        address _collectionAddress,
        uint256 _tokenId
    ) public view returns (bool) {
        return airdropBlacklist[_hashUniqueAirdrop(_airdropId, _account, _collectionAddress, _tokenId)];
    }

    function _leaf(address account, address collectionAddress, uint256 tokenId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account, collectionAddress, tokenId));
    }

    function _verify(bytes32 _root, bytes32 _leafNode, bytes32[] memory _proof) internal pure returns (bool) {
        return MerkleProof.verify(_proof, _root, _leafNode);
    }

    function _hashUniqueAirdrop(
        uint256 _airdropId,
        address _account,
        address _collectionAddress,
        uint256 _tokenId
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_airdropId, _account, _collectionAddress, _tokenId));
    }

    function numberNotClaimed(AirdropInfo[] memory infos) public view returns (uint128) {
        uint128 result = 0;

        for (uint256 i = 0; i < infos.length; i++) {
            if (!isClaimed(infos[i].airdropId, infos[i].account, infos[i].collectionAddress, infos[i].tokenId)) {
                result = result + 1;
            }
        }

        return result;
    }
}
