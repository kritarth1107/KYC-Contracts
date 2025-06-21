// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IKYC {
    function isWalletKYCed(address wallet) external view returns (bool);
}

interface IPropinfi1155 {
    function transferApprovedToken(address from, address to, uint256 tokenId, uint256 amount) external;
}

contract PropinfiMarketplace is Ownable, ReentrancyGuard {
    struct Listing {
        uint256 pricePerFraction;
        uint256 amount;
        uint256 expiry;
    }

    IERC20 public prnfToken;
    IKYC public kycContract;

    uint256 public platformFeePercent; // 250 = 2.5%
    address public feeWallet;

    mapping(address => mapping(uint256 => mapping(address => Listing))) public listings; // nft => tokenId => seller => Listing
    mapping(address => mapping(uint256 => mapping(address => uint256))) public deposits; // buyer => tokenId => seller => amount

    event PropertyListed(address indexed seller, uint256 indexed tokenId, uint256 amount, uint256 price, uint256 expiry);
    event PropertyDelisted(address indexed seller, uint256 indexed tokenId);
    event PropertyBought(address indexed buyer, address indexed seller, uint256 indexed tokenId, uint256 amount);
    event DepositMade(address indexed buyer, address indexed seller, uint256 indexed tokenId, uint256 amount, uint256 totalCost);
    event DepositCancelled(address indexed buyer, uint256 indexed tokenId, address indexed seller, uint256 amount);
    event PlatformFeeUpdated(uint256 newFee);
    event FeeWalletUpdated(address newWallet);

    modifier onlyKYCed() {
        require(kycContract.isWalletKYCed(msg.sender), "Wallet not KYCed");
        _;
    }

    constructor(address _kycContract, address _prnfToken, uint256 _platformFeePercent, address _feeWallet) Ownable(msg.sender) {
        require(_kycContract != address(0), "Invalid KYC contract");
        require(_prnfToken != address(0), "Invalid PRNF token");
        require(_feeWallet != address(0), "Invalid fee wallet");
        require(_platformFeePercent <= 1000, "Fee too high");

        kycContract = IKYC(_kycContract);
        prnfToken = IERC20(_prnfToken);
        platformFeePercent = _platformFeePercent;
        feeWallet = _feeWallet;
    }

    function listProperty(address nft, uint256 tokenId, uint256 amount, uint256 pricePerFraction, uint256 expiry) external {
        require(amount > 0, "Amount must be > 0");
        require(pricePerFraction > 0, "Price must be > 0");
        require(block.timestamp < expiry, "Invalid expiry");

        listings[nft][tokenId][msg.sender] = Listing({
            pricePerFraction: pricePerFraction,
            amount: amount,
            expiry: expiry
        });

        emit PropertyListed(msg.sender, tokenId, amount, pricePerFraction, expiry);
    }

    function cancelListing(address nft, uint256 tokenId) external {
        Listing storage listing = listings[nft][tokenId][msg.sender];
        require(listing.amount > 0, "No active listing");
        delete listings[nft][tokenId][msg.sender];
        emit PropertyDelisted(msg.sender, tokenId);
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

    function finalizePurchase(address nft, uint256 tokenId, address seller, uint256 amount) external onlyKYCed nonReentrant {
        Listing storage listing = listings[nft][tokenId][seller];
        require(block.timestamp < listing.expiry, "Listing expired");
        require(listing.amount >= amount, "Not enough listed");

        uint256 totalCost = listing.pricePerFraction * amount;
        require(deposits[msg.sender][tokenId][seller] >= totalCost, "Insufficient deposit");

        uint256 fee = (totalCost * platformFeePercent) / 10000;
        uint256 sellerAmount = totalCost - fee;

        require(prnfToken.transfer(feeWallet, fee), "Fee transfer failed");
        require(prnfToken.transfer(seller, sellerAmount), "Seller payment failed");

        IPropinfi1155(nft).transferApprovedToken(seller, msg.sender, tokenId, amount);

        delete listings[nft][tokenId][seller];
        deposits[msg.sender][tokenId][seller] = 0;

        emit PropertyBought(msg.sender, seller, tokenId, amount);
    }

    function cancelDeposit(uint256 tokenId, address seller) external {
        uint256 amount = deposits[msg.sender][tokenId][seller];
        require(amount > 0, "No deposit found");
        deposits[msg.sender][tokenId][seller] = 0;
        require(prnfToken.transfer(msg.sender, amount), "Refund failed");
        emit DepositCancelled(msg.sender, tokenId, seller, amount);
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
}
