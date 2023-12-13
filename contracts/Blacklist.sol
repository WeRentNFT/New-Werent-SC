// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "./interfaces/IBlacklist.sol";
import "./interfaces/IWeRent.sol";

contract Blacklist is IBlacklist, Initializable, PausableUpgradeable, OwnableUpgradeable {
    mapping(address => bool) public list;

    function initialize() public initializer {
        __Pausable_init();
        __Ownable_init(address(msg.sender));
    }

    function setBlacklist(address _account) external override onlyOwner whenNotPaused {
        require(_account != address(0), "Blacklist: not allow address zero");
        require(_account != owner(), "Blacklist: cannot blacklist owner of contract");
        require(!list[_account], "Blacklist: this user already blacklisted");
        list[_account] = true;
        emit Blacklisted(_account);
    }

    function removeBlacklist(address _account) external override onlyOwner whenNotPaused {
        require(_account != address(0), "Blacklist: not allow address zero");
        list[_account] = false;
        emit RemoveBlacklist(_account);
    }

    function isBlacklisted(address _account) public view override returns (bool) {
        return list[_account];
    }

    function isContract(address _addr) public view override returns (bool) {
        return _addr.code.length > 0;
    }
}
