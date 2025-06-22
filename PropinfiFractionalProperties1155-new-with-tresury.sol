// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IKYC {
    function isWalletKYCed(address wallet) external view returns (bool);
}

contract PropinfiFractionalProperties is ERC1155, Ownable {
    using Strings for uint256;

    IKYC public kycContract;
    address public treasuryWallet;

    // tokenId => custom URI
    mapping(uint256 => string) private _tokenURIs;

    // tokenId => approvals
    struct Approval {
        uint256 allowedAmount;
        uint256 expiry;
    }
    mapping(address => mapping(uint256 => Approval)) public approvals;

    // Events
    event Minted(address indexed to, uint256 indexed tokenId, uint256 fractions, string tokenURI);
    event TokenURIUpdated(uint256 indexed tokenId, string newURI);
    event ApprovalForTransferSet(address indexed owner, uint256 indexed tokenId, uint256 allowedAmount, uint256 expiry);
    event SafeTransfer(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 amount);
    event TreasuryWalletUpdated(address indexed oldWallet, address indexed newWallet);

    constructor(address _kycContract, address _treasuryWallet) ERC1155("") Ownable(msg.sender) {
        require(_kycContract != address(0), "Invalid KYC contract");
        require(_treasuryWallet != address(0), "Invalid treasury wallet");
        kycContract = IKYC(_kycContract);
        treasuryWallet = _treasuryWallet;
    }

    // ===== Minting =====
    function mint(
        uint256 tokenId,
        string memory tokenURI_,
        uint256 fractions
    ) external onlyOwner {
        require(fractions > 0, "Must mint at least 1 fraction");
        require(bytes(_tokenURIs[tokenId]).length == 0, "Token already minted");

        _mint(treasuryWallet, tokenId, fractions, "");
        _tokenURIs[tokenId] = tokenURI_;

        emit Minted(treasuryWallet, tokenId, fractions, tokenURI_);
    }

    // ===== URI Handling =====
    function uri(uint256 tokenId) public view override returns (string memory) {
        require(bytes(_tokenURIs[tokenId]).length > 0, "URI not set for token");
        return _tokenURIs[tokenId];
    }

    function updateTokenURI(uint256 tokenId, string memory newURI) external onlyOwner {
        string memory currentURI = _tokenURIs[tokenId];
        require(bytes(currentURI).length > 0, "Token does not exist");
        require(
            keccak256(bytes(currentURI)) != keccak256(bytes(newURI)),
            "New URI must be different"
        );
        _tokenURIs[tokenId] = newURI;
        emit TokenURIUpdated(tokenId, newURI);
    }

    // ===== Approval for Transfer (SBT-style) =====
    function setApprovalForTransfer(
        uint256 tokenId,
        uint256 allowedAmount,
        uint256 expiryTimestamp
    ) external {
        require(balanceOf(msg.sender, tokenId) >= allowedAmount, "Insufficient balance");
        approvals[msg.sender][tokenId] = Approval({
            allowedAmount: allowedAmount,
            expiry: expiryTimestamp
        });
        emit ApprovalForTransferSet(msg.sender, tokenId, allowedAmount, expiryTimestamp);
    }

    function transferApprovedToken(
        address from,
        address to,
        uint256 tokenId,
        uint256 amount
    ) external onlyOwner {
        require(kycContract.isWalletKYCed(to), "Recipient KYC not verified");

        Approval memory approval = approvals[from][tokenId];
        require(block.timestamp <= approval.expiry, "Approval expired");
        require(approval.allowedAmount >= amount, "Not enough approved tokens");

        approvals[from][tokenId].allowedAmount -= amount;
        if (approvals[from][tokenId].allowedAmount == 0) {
            delete approvals[from][tokenId];
        }

        _safeTransferFrom(from, to, tokenId, amount, "");
    }

    // ===== Transfer Overrides with KYC =====
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override {
        if (msg.sender == owner()) {
            require(kycContract.isWalletKYCed(to), "Recipient KYC not verified");
            super.safeTransferFrom(from, to, id, amount, data);
            emit SafeTransfer(msg.sender, from, to, id, amount);
        } else {
            revert("Transfers not allowed. Only owner can transfer.");
        }
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public override {
        if (msg.sender == owner()) {
            require(kycContract.isWalletKYCed(to), "Recipient KYC not verified");
            super.safeBatchTransferFrom(from, to, ids, amounts, data);
            // Note: You can emit multiple SafeTransfer events here if needed
        } else {
            revert("Batch transfers not allowed. Only owner can transfer.");
        }
    }

    // ===== Update Treasury Wallet =====
    function updateTreasuryWallet(address newTreasuryWallet) external onlyOwner {
        require(newTreasuryWallet != address(0), "Invalid treasury wallet address");
        emit TreasuryWalletUpdated(treasuryWallet, newTreasuryWallet);
        treasuryWallet = newTreasuryWallet;
    }

    // ===== Interface support =====
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
