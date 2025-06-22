// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface IKYC {
    function isWalletKYCed(address wallet) external view returns (bool);
}

interface IPropinfi1155 is IERC1155 {
    function transferApprovedToken(address from, address to, uint256 id, uint256 amount) external;
}

contract PropinfiMarketplace is ReentrancyGuard, Ownable {
    struct Listing {
        uint256 pricePerFraction;
        uint256 amount;
        uint256 expiry;
    }

    struct ListingInfo {
        address seller;
        uint256 pricePerFraction;
        uint256 amount;
        uint256 expiry;
    }

    struct DepositInfo {
        uint256 tokenId;
        uint256 deposit;
        address seller;
    }

    IERC20 public prnfToken;
    IKYC public kycContract;
    address public feeWallet;
    uint256 public platformFeePercent; // in basis points (10000 = 100%)

    // nft => tokenId => seller => Listing
    mapping(address => mapping(uint256 => mapping(address => Listing))) public listings;

    // nft => tokenId => sellers list
    mapping(address => mapping(uint256 => address[])) private sellersByToken;

    // buyer => tokenId => seller => deposit amount
    mapping(address => mapping(uint256 => mapping(address => uint256))) public deposits;

    // buyer => tokenId => seller => is locked
    mapping(address => mapping(uint256 => mapping(address => bool))) public isDepositLocked;

    event ListingCreated(address indexed seller, uint256 indexed tokenId, uint256 price, uint256 amount, uint256 expiry);
    event DepositMade(address indexed buyer, address indexed seller, uint256 indexed tokenId, uint256 amount, uint256 totalCost);
    event DepositLocked(address indexed buyer, address indexed seller, uint256 indexed tokenId);
    event DepositCancelled(address indexed buyer, uint256 indexed tokenId, address indexed seller, uint256 amount);
    event PropertyBought(address indexed buyer, address indexed seller, uint256 indexed tokenId, uint256 amount);
    event PlatformFeeUpdated(uint256 newFee);
    event FeeWalletUpdated(address newWallet);

    modifier onlyKYCed() {
        require(kycContract.isWalletKYCed(msg.sender), "KYC not approved");
        _;
    }

    constructor(
        address _kycContract,
        address _prnfToken,
        uint256 _platformFeePercent,
        address _feeWallet
    ) Ownable(msg.sender) {
        require(_kycContract != address(0), "Invalid KYC contract");
        require(_prnfToken != address(0), "Invalid PRNF token");
        require(_feeWallet != address(0), "Invalid fee wallet");
        require(_platformFeePercent <= 1000, "Fee too high");

        kycContract = IKYC(_kycContract);
        prnfToken = IERC20(_prnfToken);
        platformFeePercent = _platformFeePercent;
        feeWallet = _feeWallet;
    }

    function setPlatformFeePercent(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "Fee too high");
        platformFeePercent = newFee;
        emit PlatformFeeUpdated(newFee);
    }

    function setFeeWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "Invalid address");
        feeWallet = newWallet;
        emit FeeWalletUpdated(newWallet);
    }

    function createListing(address nft, uint256 tokenId, uint256 pricePerFraction, uint256 amount, uint256 expiry) external {
        require(pricePerFraction > 0 && amount > 0, "Invalid params");
        require(expiry > block.timestamp, "Expiry must be in future");

        if (listings[nft][tokenId][msg.sender].amount == 0) {
            sellersByToken[nft][tokenId].push(msg.sender);
        }

        listings[nft][tokenId][msg.sender] = Listing({
            pricePerFraction: pricePerFraction,
            amount: amount,
            expiry: expiry
        });

        emit ListingCreated(msg.sender, tokenId, pricePerFraction, amount, expiry);
    }

    function depositPRNF(address nft, uint256 tokenId, address seller, uint256 amount) external onlyKYCed {
        Listing memory listing = listings[nft][tokenId][seller];
        require(block.timestamp < listing.expiry, "Listing expired");
        require(listing.amount >= amount, "Not enough listed");

        uint256 totalCost = listing.pricePerFraction * amount;
        require(prnfToken.transferFrom(msg.sender, address(this), totalCost), "PRNF transfer failed");

        deposits[msg.sender][tokenId][seller] += totalCost;

        emit DepositMade(msg.sender, seller, tokenId, amount, totalCost);
    }

    function lockDeposit(address buyer, uint256 tokenId, address seller) external onlyOwner {
        require(deposits[buyer][tokenId][seller] > 0, "No deposit found");
        isDepositLocked[buyer][tokenId][seller] = true;

        emit DepositLocked(buyer, seller, tokenId);
    }

    function cancelDeposit(uint256 tokenId, address seller) external {
        require(!isDepositLocked[msg.sender][tokenId][seller], "Deposit locked by admin");

        uint256 amount = deposits[msg.sender][tokenId][seller];
        require(amount > 0, "No deposit found");

        deposits[msg.sender][tokenId][seller] = 0;
        require(prnfToken.transfer(msg.sender, amount), "Refund failed");

        emit DepositCancelled(msg.sender, tokenId, seller, amount);
    }

    function finalizePurchase(address nft, address buyer, uint256 tokenId, address seller, uint256 amount) external onlyOwner nonReentrant {
        Listing storage listing = listings[nft][tokenId][seller];
        require(block.timestamp < listing.expiry, "Listing expired");
        require(listing.amount >= amount, "Not enough listed");

        uint256 totalCost = listing.pricePerFraction * amount;
        require(deposits[buyer][tokenId][seller] >= totalCost, "Insufficient deposit");

        uint256 fee = (totalCost * platformFeePercent) / 10000;
        uint256 sellerAmount = totalCost - fee;

        require(prnfToken.transfer(feeWallet, fee), "Fee transfer failed");
        require(prnfToken.transfer(seller, sellerAmount), "Seller payment failed");

        IPropinfi1155(nft).transferApprovedToken(seller, buyer, tokenId, amount);

        delete listings[nft][tokenId][seller];
        deposits[buyer][tokenId][seller] = 0;
        isDepositLocked[buyer][tokenId][seller] = false;

        emit PropertyBought(buyer, seller, tokenId, amount);
    }

    function getListings(address nft, uint256 tokenId) external view returns (ListingInfo[] memory) {
        address[] memory sellers = sellersByToken[nft][tokenId];
        uint256 count = sellers.length;
        ListingInfo[] memory results = new ListingInfo[](count);

        for (uint256 i = 0; i < count; i++) {
            address seller = sellers[i];
            Listing memory listing = listings[nft][tokenId][seller];
            if (listing.amount > 0) {
                results[i] = ListingInfo({
                    seller: seller,
                    pricePerFraction: listing.pricePerFraction,
                    amount: listing.amount,
                    expiry: listing.expiry
                });
            }
        }

        return results;
    }

    function getBuyerDeposits(address buyer, address nft) external view returns (DepositInfo[] memory) {
        // Count total deposits
        uint256 totalCount = 0;
        for (uint256 tokenId = 0; tokenId < 10000; tokenId++) { // assuming tokenId range is reasonable
            address[] memory sellers = sellersByToken[nft][tokenId];
            for (uint256 j = 0; j < sellers.length; j++) {
                if (deposits[buyer][tokenId][sellers[j]] > 0) {
                    totalCount++;
                }
            }
        }

        DepositInfo[] memory results = new DepositInfo[](totalCount);
        uint256 index = 0;

        for (uint256 tokenId = 0; tokenId < 10000; tokenId++) {
            address[] memory sellers = sellersByToken[nft][tokenId];
            for (uint256 j = 0; j < sellers.length; j++) {
                uint256 amount = deposits[buyer][tokenId][sellers[j]];
                if (amount > 0) {
                    results[index++] = DepositInfo({
                        tokenId: tokenId,
                        deposit: amount,
                        seller: sellers[j]
                    });
                }
            }
        }

        return results;
    }
}
