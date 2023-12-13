// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IWeRent is IERC721Receiver, IERC1155Receiver {
    event Lent(
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint8 lentAmount,
        uint256 lendingId,
        address indexed lenderAddress,
        uint8 maxRentDuration,
        bytes4 dailyRentPrice,
        bytes4 nftPrice,
        bool isERC721,
        bool useNativeToken,
        bytes32 categories
    );

    event Rented(uint256 lendingId, address indexed renterAddress, uint8 rentDuration, uint32 rentedAt);

    event Returned(uint256 indexed lendingId, uint32 returnedAt, uint256 fee);

    event CollateralClaimed(uint256 indexed lendingId, uint32 claimedAt, uint256 rentalFee);

    event LendingStopped(uint256 indexed lendingId, uint32 stoppedAt);

    event RentFee(uint256);
    event Beneficiary(address);
    event Staking(address);
    event Paused(bool);
    event ExtraToken(address);
    event Delegator(address);

    event SetBlacklistContract(address blacklistContractAddress);

    event SetNewAdmin(address newAdminAddress);

    /**
     * @dev sends your NFT to ReNFT contract, which acts as an escrow
     * between the lender and the renter
     */
    struct DiscountSignature {
        uint256 discount;
        uint256 deadline;
        address lender;
        bytes signature;
    }

    function lend(
        address[] memory _nft,
        uint256[] memory _tokenId,
        uint256[] memory _lendAmounts,
        uint8[] memory _maxRentDuration,
        bytes4[] memory _dailyRentPrice,
        bytes4[] memory _nftPrice,
        bool[] memory _useNativeToken,
        bytes32[] memory _categories
    ) external;

    /**
     * @dev renter sends rentDuration * dailyRentPrice
     * to cover for the potentially full cost of renting. They also
     * must send the collateral (nft price set by the lender in lend)
     */
    function rent(
        address[] memory _nft,
        uint256[] memory _tokenId,
        uint256[] memory _lendingIds,
        uint8[] memory _rentDurations
    ) external payable;

    /**
     * @dev renters call this to return the rented NFT before the
     * deadline. If they fail to do so, they will lose the posted
     * collateral
     */
    function returnIt(
        address[] memory _nft,
        uint256[] memory _tokenId,
        uint256[] memory _lendingIds,
        DiscountSignature[] memory _discountSignature
    ) external;

    /**
     * @dev claim collateral on rentals that are past their due date
     */
    function claimCollateral(
        address[] memory _nfts,
        uint256[] memory _tokenIds,
        uint256[] memory _lendingIds,
        DiscountSignature[] memory _discountSignature
    ) external;

    /**
     * @dev stop lending releases the NFT from escrow and sends it back
     * to the lender
     */
    function stopLending(address[] memory _nft, uint256[] memory _tokenId, uint256[] memory _lendingIds) external;
}
