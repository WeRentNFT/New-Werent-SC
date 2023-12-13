// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

interface IBlacklist {
    // Events
    event Blacklisted(address account);

    event RemoveBlacklist(address account);

    event SetWeRentContract(address weRentContractAddress);

    // Functions
    function isBlacklisted(address _account) external view returns (bool);

    function isContract(address _addr) external view returns (bool);

    function setBlacklist(address _account) external;

    function removeBlacklist(address _account) external;
}
