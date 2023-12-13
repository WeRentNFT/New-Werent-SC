// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/IWeRent.sol";
import "./interfaces/IBlacklist.sol";

import "./extensions/WerentSignature.sol";

contract WeRent is WerentSignature, IWeRent, ERC721Holder, ERC1155Holder, Initializable {
    using SafeERC20Upgradeable for ERC20Upgradeable;
    address payable public admin;
    address payable private beneficiary;
    ERC20Upgradeable private extraTokenAddress;
    IBlacklist private blacklistContract;
    uint256 private lendingId;
    bool public paused;

    // in bps. so 100 => 1%
    uint256 public rentFee;

    uint256 public constant SECONDS_IN_DAY = 86400;
    uint256 private constant DECIMAL = 18;

    // single storage slot: address - 160 bits, 168, 200, 232, 240, 248
    struct Lending {
        address payable lenderAddress;
        uint8 maxRentDuration;
        bytes4 dailyRentPrice;
        bytes4 nftPrice;
        uint8 lentAmount;
        bool useNativeToken;
        bytes32 category;
    }

    // single storage slot: 160 bits, 168, 200
    struct Renting {
        address payable renterAddress;
        uint8 rentDuration;
        uint32 rentedAt;
    }

    struct LendingRenting {
        Lending lending;
        Renting renting;
    }

    mapping(bytes32 => LendingRenting) private lendingRenting;

    struct CallData {
        uint256 left;
        uint256 right;
        address[] nfts;
        uint256[] tokenIds;
        uint256[] lentAmounts;
        uint8[] maxRentDurations;
        bytes4[] dailyRentPrices;
        bytes4[] nftPrices;
        uint256[] lendingIds;
        uint8[] rentDurations;
        bool[] useNativeTokens;
        bytes32[] category;
        DiscountSignature[] discountSignatures;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "not admin");
        _;
    }

    modifier notPaused() {
        require(!paused, "paused");
        _;
    }

    modifier notBlacklisted() {
        require(blacklistContract.isBlacklisted(msg.sender) == false, "System: account is blacklisted");
        require(!isContract(msg.sender), "unable to call by contract");
        _;
    }

    function initialize(
        address payable _beneficiary,
        address payable _admin,
        address _extraTokenAddress,
        address _blacklistContract
    ) public initializer {
        ensureIsNotZeroAddr(_beneficiary);
        ensureIsNotZeroAddr(_admin);
        ensureIsNotZeroAddr(_extraTokenAddress);
        beneficiary = _beneficiary;
        admin = _admin;
        extraTokenAddress = ERC20Upgradeable(_extraTokenAddress);
        blacklistContract = IBlacklist(_blacklistContract);

        lendingId = 1;
        paused = false;
        rentFee = 500; // default 5%
    }

    function bundleCall(function(CallData memory) _handler, CallData memory _cd) private {
        require(_cd.nfts.length > 0, "no nfts");
        while (_cd.right != _cd.nfts.length) {
            if ((_cd.nfts[_cd.left] == _cd.nfts[_cd.right]) && (is1155(_cd.nfts[_cd.right]))) {
                _cd.right++;
            } else {
                _handler(_cd);
                _cd.left = _cd.right;
                _cd.right++;
            }
        }
        _handler(_cd);
    }

    // lend, rent, return, stop, claim

    function lend(
        address[] memory _nfts,
        uint256[] memory _tokenIds,
        uint256[] memory _lendAmounts,
        uint8[] memory _maxRentDurations,
        bytes4[] memory _dailyRentPrices,
        bytes4[] memory _nftPrices,
        bool[] memory _useNativeTokens,
        bytes32[] memory  _category
    ) external override notPaused notBlacklisted {
        bundleCall(
            handleLend,
            createLendCallData(
                _nfts,
                _tokenIds,
                _lendAmounts,
                _maxRentDurations,
                _dailyRentPrices,
                _nftPrices,
                _useNativeTokens,
                _category
            )
        );
    }

    function rent(
        address[] memory _nfts,
        uint256[] memory _tokenIds,
        uint256[] memory _lendingIds,
        uint8[] memory _rentDurations
    ) external payable override notPaused notBlacklisted {
        bundleCall(handleRent, createRentCallData(_nfts, _tokenIds, _lendingIds, _rentDurations));
    }

    function returnIt(
        address[] memory _nfts,
        uint256[] memory _tokenIds,
        uint256[] memory _lendingIds,
        DiscountSignature[] memory _discountSignature
    ) external override notPaused {
        bundleCall(handleReturn, createActionCallDataWithSignature(_nfts, _tokenIds, _lendingIds, _discountSignature));
    }

    function stopLending(
        address[] memory _nfts,
        uint256[] memory _tokenIds,
        uint256[] memory _lendingIds
    ) external override notPaused {
        bundleCall(handleStopLending, createActionCallData(_nfts, _tokenIds, _lendingIds));
    }

    function claimCollateral(
        address[] memory _nfts,
        uint256[] memory _tokenIds,
        uint256[] memory _lendingIds,
        DiscountSignature[] memory _discountSignature
    ) external override notPaused {
        bundleCall(
            handleClaimCollateral,
            createActionCallDataWithSignature(_nfts, _tokenIds, _lendingIds, _discountSignature)
        );
    }

    //      .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.
    // `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'

    function takeFee(
        address lenderRenter,
        uint256 _rent,
        bool _useNativeToken,
        DiscountSignature memory _discountSignature
    ) private returns (uint256 fee) {
        fee = _rent * rentFee;
        fee /= 10000;
        require(
            verify(
                admin,
                _discountSignature.discount,
                _discountSignature.deadline,
                _discountSignature.lender,
                _discountSignature.signature
            ),
            "Invalid verify"
        );
        require(block.timestamp < _discountSignature.deadline, "Signature is expired");
        require(lenderRenter == _discountSignature.lender, "Not user recieve discount");
        fee = fee - (_discountSignature.discount * fee) / 10000;
        if (_useNativeToken) {
            (bool success, ) = beneficiary.call{ value: fee }("");
            require(success, "Failed to send Ether");
        } else {
            extraTokenAddress.transfer(beneficiary, fee);
        }
    }

    function estimatedFeeAmount(address _nft, uint256 _tokenId, uint256 _lendingId) external view returns (uint256) {
        LendingRenting storage item = lendingRenting[keccak256(abi.encodePacked(_nft, _tokenId, _lendingId))];

        ensureIsNotNull(item.lending);

        uint256 _secondsSinceRentStart = block.timestamp - item.renting.rentedAt;
        uint256 decimals = getTokenDecimal(item.lending.useNativeToken);
        uint256 scale = 10 ** decimals;

        uint256 rentPrice = unpackPrice(item.lending.dailyRentPrice, scale);
        uint256 sendLenderAmt = (_secondsSinceRentStart * rentPrice) / SECONDS_IN_DAY;
        require(sendLenderAmt > 0, "lender payment is zero");

        return sendLenderAmt;
    }

    function distributePayments(
        LendingRenting storage _lendingRenting,
        uint256 _secondsSinceRentStart,
        DiscountSignature memory _discountSignature
    ) private returns (uint256) {
        bool useNativeToken = _lendingRenting.lending.useNativeToken;
        uint256 scale = 10 ** getTokenDecimal(useNativeToken);
        uint256 nftPrice = _lendingRenting.lending.lentAmount * unpackPrice(_lendingRenting.lending.nftPrice, scale);
        uint256 rentPrice = unpackPrice(_lendingRenting.lending.dailyRentPrice, scale);
        uint256 totalRenterPmtWoCollateral = rentPrice * _lendingRenting.renting.rentDuration;
        uint256 sendLenderAmt = (_secondsSinceRentStart * rentPrice) / SECONDS_IN_DAY;
        require(totalRenterPmtWoCollateral > 0, "total payment wo collateral is zero");
        require(sendLenderAmt > 0, "lender payment is zero");
        uint256 sendRenterAmt = totalRenterPmtWoCollateral - sendLenderAmt;

        uint256 takenFee = takeFee(
            _lendingRenting.lending.lenderAddress,
            sendLenderAmt,
            useNativeToken,
            _discountSignature
        );

        sendLenderAmt -= takenFee;
        sendRenterAmt += nftPrice;

        address payable lenderAddress = _lendingRenting.lending.lenderAddress;
        address payable renterAddress = _lendingRenting.renting.renterAddress;

        if (useNativeToken) {
            (bool successLender, ) = lenderAddress.call{ value: sendLenderAmt }("");
            require(successLender, "Failed to send Ether");
            (bool successRenter, ) = renterAddress.call{ value: sendRenterAmt }("");
            require(successRenter, "Failed to send Ether");
        } else {
            extraTokenAddress.transfer(lenderAddress, sendLenderAmt);
            extraTokenAddress.transfer(renterAddress, sendRenterAmt);
        }

        return sendLenderAmt += takenFee;
    }

    function distributeClaimPayment(
        LendingRenting memory _lendingRenting,
        DiscountSignature memory _discountSignature
    ) private returns (uint256) {
        bool useNativeToken = _lendingRenting.lending.useNativeToken;

        uint256 decimals = getTokenDecimal(useNativeToken);
        uint256 scale = 10 ** decimals;
        uint256 nftPrice = _lendingRenting.lending.lentAmount * unpackPrice(_lendingRenting.lending.nftPrice, scale);
        uint256 rentPrice = unpackPrice(_lendingRenting.lending.dailyRentPrice, scale);
        uint256 maxRentPayment = rentPrice * _lendingRenting.renting.rentDuration;
        uint256 takenFee = takeFee(
            _lendingRenting.lending.lenderAddress,
            maxRentPayment,
            useNativeToken,
            _discountSignature
        );

        uint256 finalAmt = maxRentPayment + nftPrice;

        require(maxRentPayment > 0, "collateral plus rent is zero");
        if (useNativeToken) {
            address payable lenderAddress = _lendingRenting.lending.lenderAddress;
            (bool successRenter, ) = lenderAddress.call{ value: finalAmt - takenFee }("");
            require(successRenter, "Failed to send Ether");
        } else {
            extraTokenAddress.transfer(_lendingRenting.lending.lenderAddress, finalAmt - takenFee);
        }

        return (maxRentPayment - takenFee);
    }

    function safeTransfer(
        CallData memory _cd,
        address _from,
        address _to,
        uint256[] memory _tokenIds,
        uint256[] memory _lentAmounts
    ) private {
        if (is721(_cd.nfts[_cd.left])) {
            IERC721(_cd.nfts[_cd.left]).transferFrom(_from, _to, _cd.tokenIds[_cd.left]);
        } else if (is1155(_cd.nfts[_cd.left])) {
            IERC1155(_cd.nfts[_cd.left]).safeBatchTransferFrom(_from, _to, _tokenIds, _lentAmounts, "");
        } else {
            revert("unsupported token type");
        }
    }

    function getLendRentInfo(
        address _nft,
        uint256 _tokenId,
        uint256 _lendingId
    ) public view returns (LendingRenting memory item) {
        item = lendingRenting[keccak256(abi.encodePacked(_nft, _tokenId, _lendingId))];
    }

    //      .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.
    // `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'

    function handleLend(CallData memory _cd) private {
        for (uint256 i = _cd.left; i < _cd.right; i++) {
            ensureIsLendable(_cd, i);

            LendingRenting storage item = lendingRenting[
                keccak256(abi.encodePacked(_cd.nfts[_cd.left], _cd.tokenIds[i], lendingId))
            ];

            ensureIsNull(item.lending);
            ensureIsNull(item.renting);

            bool nftIs721 = is721(_cd.nfts[i]);
            item.lending = Lending({
                lenderAddress: payable(msg.sender),
                lentAmount: nftIs721 ? 1 : uint8(_cd.lentAmounts[i]),
                maxRentDuration: _cd.maxRentDurations[i],
                dailyRentPrice: _cd.dailyRentPrices[i],
                nftPrice: _cd.nftPrices[i],
                useNativeToken: _cd.useNativeTokens[i],
                category: _cd.category[i]
            });

            emit Lent(
                _cd.nfts[_cd.left],
                _cd.tokenIds[i],
                nftIs721 ? 1 : uint8(_cd.lentAmounts[i]),
                lendingId,
                msg.sender,
                _cd.maxRentDurations[i],
                _cd.dailyRentPrices[i],
                _cd.nftPrices[i],
                nftIs721,
                _cd.useNativeTokens[i],
                _cd.category[i]
            );

            lendingId++;
        }

        safeTransfer(
            _cd,
            msg.sender,
            address(this),
            sliceArr(_cd.tokenIds, _cd.left, _cd.right, 0),
            sliceArr(_cd.lentAmounts, _cd.left, _cd.right, 0)
        );
    }

    function handleRent(CallData memory _cd) private {
        uint256[] memory lentAmounts = new uint256[](_cd.right - _cd.left);

        for (uint256 i = _cd.left; i < _cd.right; i++) {
            LendingRenting storage item = lendingRenting[
                keccak256(abi.encodePacked(_cd.nfts[_cd.left], _cd.tokenIds[i], _cd.lendingIds[i]))
            ];

            ensureIsNotContract(msg.sender);
            ensureIsNotNull(item.lending);
            ensureIsNull(item.renting);
            ensureIsRentable(item.lending, _cd, i, msg.sender);
            bool useNativeToken = item.lending.useNativeToken;

            uint256 decimals = getTokenDecimal(useNativeToken);

            {
                uint256 scale = 10 ** decimals;
                uint256 rentPrice = _cd.rentDurations[i] * unpackPrice(item.lending.dailyRentPrice, scale);
                uint256 nftPrice = item.lending.lentAmount * unpackPrice(item.lending.nftPrice, scale);

                require(rentPrice > 0, "rent price is zero");
                require(nftPrice > 0, "nft price is zero");

                if (useNativeToken) {
                    require(msg.value == rentPrice + nftPrice, "Value to pay not enough");
                } else {
                    extraTokenAddress.transferFrom(msg.sender, address(this), rentPrice + nftPrice);
                }
            }

            lentAmounts[i - _cd.left] = item.lending.lentAmount;

            item.renting.renterAddress = payable(msg.sender);
            item.renting.rentDuration = _cd.rentDurations[i];
            item.renting.rentedAt = uint32(block.timestamp);

            emit Rented(_cd.lendingIds[i], msg.sender, _cd.rentDurations[i], item.renting.rentedAt);
        }

        safeTransfer(
            _cd,
            address(this),
            msg.sender,
            sliceArr(_cd.tokenIds, _cd.left, _cd.right, 0),
            sliceArr(lentAmounts, _cd.left, _cd.right, _cd.left)
        );
    }

    function handleReturn(CallData memory _cd) private {
        uint256[] memory lentAmounts = new uint256[](_cd.right - _cd.left);

        for (uint256 i = _cd.left; i < _cd.right; i++) {
            LendingRenting storage item = lendingRenting[
                keccak256(abi.encodePacked(_cd.nfts[_cd.left], _cd.tokenIds[i], _cd.lendingIds[i]))
            ];

            ensureIsNotContract(msg.sender);
            ensureIsNotNull(item.lending);
            ensureIsReturnable(item.renting, tx.origin, block.timestamp);

            uint256 secondsSinceRentStart = block.timestamp - item.renting.rentedAt;
            uint256 renterFee = distributePayments(item, secondsSinceRentStart, _cd.discountSignatures[i]);

            lentAmounts[i - _cd.left] = item.lending.lentAmount;

            emit Returned(_cd.lendingIds[i], uint32(block.timestamp), renterFee);

            delete item.renting;
        }

        safeTransfer(
            _cd,
            tx.origin,
            address(this),
            sliceArr(_cd.tokenIds, _cd.left, _cd.right, 0),
            sliceArr(lentAmounts, _cd.left, _cd.right, _cd.left)
        );
    }

    function handleStopLending(CallData memory _cd) private {
        uint256[] memory lentAmounts = new uint256[](_cd.right - _cd.left);

        for (uint256 i = _cd.left; i < _cd.right; i++) {
            LendingRenting storage item = lendingRenting[
                keccak256(abi.encodePacked(_cd.nfts[_cd.left], _cd.tokenIds[i], _cd.lendingIds[i]))
            ];

            ensureIsNotNull(item.lending);
            ensureIsNull(item.renting);
            ensureIsStoppable(item.lending, msg.sender);

            lentAmounts[i - _cd.left] = item.lending.lentAmount;

            emit LendingStopped(_cd.lendingIds[i], uint32(block.timestamp));

            delete item.lending;
        }

        safeTransfer(
            _cd,
            address(this),
            msg.sender,
            sliceArr(_cd.tokenIds, _cd.left, _cd.right, 0),
            sliceArr(lentAmounts, _cd.left, _cd.right, _cd.left)
        );
    }

    function handleClaimCollateral(CallData memory _cd) private {
        for (uint256 i = _cd.left; i < _cd.right; i++) {
            LendingRenting storage item = lendingRenting[
                keccak256(abi.encodePacked(_cd.nfts[_cd.left], _cd.tokenIds[i], _cd.lendingIds[i]))
            ];

            ensureIsNotNull(item.lending);
            ensureIsNotNull(item.renting);
            ensureIsClaimable(item.renting, block.timestamp);

            uint256 rentalFee = distributeClaimPayment(item, _cd.discountSignatures[i]);

            emit CollateralClaimed(_cd.lendingIds[i], uint32(block.timestamp), rentalFee);

            delete item.lending;
            delete item.renting;
        }
    }

    //      .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.
    // `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'

    function is721(address _nft) private view returns (bool) {
        return IERC165(_nft).supportsInterface(type(IERC721).interfaceId);
    }

    function is1155(address _nft) private view returns (bool) {
        return IERC165(_nft).supportsInterface(type(IERC1155).interfaceId);
    }

    //      .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.
    // `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'

    function createLendCallData(
        address[] memory _nfts,
        uint256[] memory _tokenIds,
        uint256[] memory _lendAmounts,
        uint8[] memory _maxRentDurations,
        bytes4[] memory _dailyRentPrices,
        bytes4[] memory _nftPrices,
        bool[] memory _useNativeTokens,
        bytes32[] memory _category
    ) private pure returns (CallData memory cd) {
        cd = CallData({
            left: 0,
            right: 1,
            nfts: _nfts,
            tokenIds: _tokenIds,
            lentAmounts: _lendAmounts,
            lendingIds: new uint256[](0),
            rentDurations: new uint8[](0),
            maxRentDurations: _maxRentDurations,
            dailyRentPrices: _dailyRentPrices,
            nftPrices: _nftPrices,
            useNativeTokens: _useNativeTokens,
            discountSignatures: new DiscountSignature[](0),
            category: _category
        });
    }

    function createRentCallData(
        address[] memory _nfts,
        uint256[] memory _tokenIds,
        uint256[] memory _lendingIds,
        uint8[] memory _rentDurations
    ) private pure returns (CallData memory cd) {
        cd = CallData({
            left: 0,
            right: 1,
            nfts: _nfts,
            tokenIds: _tokenIds,
            lentAmounts: new uint256[](0),
            lendingIds: _lendingIds,
            rentDurations: _rentDurations,
            maxRentDurations: new uint8[](0),
            dailyRentPrices: new bytes4[](0),
            nftPrices: new bytes4[](0),
            useNativeTokens: new bool[](0),
            discountSignatures: new DiscountSignature[](0),
            category: new  bytes32[](0)
        });
    }

    function createActionCallData(
        address[] memory _nfts,
        uint256[] memory _tokenIds,
        uint256[] memory _lendingIds
    ) private pure returns (CallData memory cd) {
        cd = CallData({
            left: 0,
            right: 1,
            nfts: _nfts,
            tokenIds: _tokenIds,
            lentAmounts: new uint256[](0),
            lendingIds: _lendingIds,
            rentDurations: new uint8[](0),
            maxRentDurations: new uint8[](0),
            dailyRentPrices: new bytes4[](0),
            nftPrices: new bytes4[](0),
            useNativeTokens: new bool[](0),
            discountSignatures: new DiscountSignature[](0),
            category: new  bytes32[](0)
        });
    }

    function createActionCallDataWithSignature(
        address[] memory _nfts,
        uint256[] memory _tokenIds,
        uint256[] memory _lendingIds,
        DiscountSignature[] memory _discountSignature
    ) private pure returns (CallData memory cd) {
        cd = CallData({
            left: 0,
            right: 1,
            nfts: _nfts,
            tokenIds: _tokenIds,
            lentAmounts: new uint256[](0),
            lendingIds: _lendingIds,
            rentDurations: new uint8[](0),
            maxRentDurations: new uint8[](0),
            dailyRentPrices: new bytes4[](0),
            nftPrices: new bytes4[](0),
            useNativeTokens: new bool[](0),
            discountSignatures: _discountSignature,
            category: new  bytes32[](0)
        });
    }

    function unpackPrice(bytes4 _price, uint256 _scale) private pure returns (uint256) {
        ensureIsUnpackablePrice(_price, _scale);

        uint16 whole = uint16(bytes2(_price));
        uint16 decimal = uint16(bytes2(_price << 16));
        uint256 decimalScale = _scale / 10000;

        if (whole > 9999) {
            whole = 9999;
        }
        if (decimal > 9999) {
            decimal = 9999;
        }

        uint256 w = whole * _scale;
        uint256 d = decimal * decimalScale;
        uint256 price = w + d;

        return price;
    }

    function getTokenDecimal(bool useNativeToken) private view returns (uint256) {
        if (useNativeToken) return DECIMAL;
        return extraTokenAddress.decimals();
    }

    function sliceArr(
        uint256[] memory _arr,
        uint256 _fromIx,
        uint256 _toIx,
        uint256 _arrOffset
    ) private pure returns (uint256[] memory r) {
        r = new uint256[](_toIx - _fromIx);
        for (uint256 i = _fromIx; i < _toIx; i++) {
            r[i - _fromIx] = _arr[i - _arrOffset];
        }
    }

    //      .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.
    // `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'

    function isContract(address _addr) private view returns (bool) {
        return _addr.code.length > 0;
    }

    function ensureIsNotContract(address _msgSender) private view {
        require(!isContract(_msgSender), "unable to call by contract");
    }

    function ensureIsNotZeroAddr(address _addr) private pure {
        require(_addr != address(0), "zero address");
    }

    function ensureIsZeroAddr(address _addr) private pure {
        require(_addr == address(0), "not a zero address");
    }

    function ensureIsNull(Lending memory _lending) private pure {
        ensureIsZeroAddr(_lending.lenderAddress);
        require(_lending.maxRentDuration == 0, "duration not zero");
        require(_lending.dailyRentPrice == 0, "rent price not zero");
        require(_lending.nftPrice == 0, "nft price not zero");
    }

    function ensureIsNotNull(Lending memory _lending) private pure {
        ensureIsNotZeroAddr(_lending.lenderAddress);
        require(_lending.maxRentDuration != 0, "duration zero");
        require(_lending.dailyRentPrice != 0, "rent price is zero");
        require(_lending.nftPrice != 0, "nft price is zero");
    }

    function ensureIsNull(Renting memory _renting) private pure {
        ensureIsZeroAddr(_renting.renterAddress);
        require(_renting.rentDuration == 0, "duration not zero");
        require(_renting.rentedAt == 0, "rented at not zero");
    }

    function ensureIsNotNull(Renting memory _renting) private pure {
        ensureIsNotZeroAddr(_renting.renterAddress);
        require(_renting.rentDuration != 0, "duration is zero");
        require(_renting.rentedAt != 0, "rented at is zero");
    }

    function ensureIsLendable(CallData memory _cd, uint256 _i) private pure {
        require(_cd.lentAmounts[_i] > 0, "lend amount is zero");
        require(_cd.lentAmounts[_i] <= type(uint8).max, "not uint8");
        require(_cd.maxRentDurations[_i] > 0, "duration is zero");
        require(_cd.maxRentDurations[_i] <= type(uint8).max, "not uint8");
        require(uint32(_cd.dailyRentPrices[_i]) > 0, "rent price is zero");
        require(uint32(_cd.nftPrices[_i]) > 0, "nft price is zero");
    }

    function ensureIsRentable(
        Lending memory _lending,
        CallData memory _cd,
        uint256 _i,
        address _msgSender
    ) private pure {
        require(_msgSender != _lending.lenderAddress, "cant rent own nft");
        require(_cd.rentDurations[_i] <= type(uint8).max, "not uint8");
        require(_cd.rentDurations[_i] > 0, "duration is zero");
        require(_cd.rentDurations[_i] <= _lending.maxRentDuration, "rent duration exceeds allowed max");
    }

    function ensureIsReturnable(Renting memory _renting, address _msgSender, uint256 _blockTimestamp) private pure {
        require(_renting.renterAddress == _msgSender, "not renter");
        require(!isPastReturnDate(_renting, _blockTimestamp), "past return date");
    }

    function ensureIsStoppable(Lending memory _lending, address _msgSender) private pure {
        require(_lending.lenderAddress == _msgSender, "not lender");
    }

    function ensureIsClaimable(Renting memory _renting, uint256 _blockTimestamp) private pure {
        require(isPastReturnDate(_renting, _blockTimestamp), "return date not passed");
    }

    function ensureIsUnpackablePrice(bytes4 _price, uint256 _scale) private pure {
        require(uint32(_price) > 0, "invalid price");
        require(_scale >= 10000, "invalid scale");
    }

    function ensureTokenNotSentinel(uint8 _paymentIx) private pure {
        require(_paymentIx > 0, "token is sentinel");
    }

    function isPastReturnDate(Renting memory _renting, uint256 _now) private pure returns (bool) {
        require(_now > _renting.rentedAt, "now before rented");
        return _now - _renting.rentedAt > _renting.rentDuration * SECONDS_IN_DAY;
    }

    //      .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.
    // `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'

    function setRentFee(uint256 _rentFee) external onlyAdmin {
        require(_rentFee < 10000, "fee exceeds 100pct");
        rentFee = _rentFee;

        emit RentFee(_rentFee);
    }

    function setBeneficiary(address payable _newBeneficiary) external onlyAdmin {
        beneficiary = _newBeneficiary;

        emit Beneficiary(_newBeneficiary);
    }

    function setPaused(bool _paused) external onlyAdmin {
        paused = _paused;

        emit Paused(_paused);
    }

    function setExtraToken(address _extraTokenAddress) external onlyAdmin {
        require(_extraTokenAddress != address(0), "Invalid address");
        extraTokenAddress = ERC20Upgradeable(_extraTokenAddress);
        emit ExtraToken(_extraTokenAddress);
    }

    function setBlacklistContract(address _address) external onlyAdmin {
        require(_address != address(0), "WeRent: not allow zero address");
        blacklistContract = IBlacklist(_address);
        emit SetBlacklistContract(_address);
    }

    function emergencyWithdrawNFT(
        address[] memory _nfts,
        uint256[] memory _tokenIds,
        address _beneficiary
    ) external onlyAdmin {
        require(_beneficiary != address(0), "WeRent: invalid address");
        for (uint i = 0; i < _nfts.length; i++) {
            IERC721(_nfts[i]).transferFrom(address(this), _beneficiary, _tokenIds[i]);
        }
    }

    function emergencyWithdrawToken(address _beneficiary, bool isNativeToken) external onlyAdmin {
        uint256 withdrawBalance;
        if (isNativeToken) {
            withdrawBalance = address(this).balance;
            (bool success, ) = _beneficiary.call{ value: withdrawBalance }("");
            require(success, "Failed to send Ether");
        } else {
            withdrawBalance = extraTokenAddress.balanceOf(address(this));
            extraTokenAddress.transfer(_beneficiary, withdrawBalance);
        }
    }

    function setNewAdmin(address payable _newAdminAddress) external onlyAdmin {
        require(_newAdminAddress != address(0), "WeRent: invalid address");
        admin = _newAdminAddress;
        emit SetNewAdmin(_newAdminAddress);
    }
}
