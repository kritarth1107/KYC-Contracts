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

    // tokenId => custom URI
    mapping(uint256 => string) private _tokenURIs;

    // tokenId => approvals
    struct Approval {
        uint256 allowedAmount;
        uint256 expiry;
    }
    mapping(address => mapping(uint256 => Approval)) public approvals;

    constructor(address _kycContract) ERC1155("") Ownable(msg.sender) {
        require(_kycContract != address(0), "Invalid KYC contract");
        kycContract = IKYC(_kycContract);
    }

    // ===== Minting =====

    function mint(
        uint256 tokenId,
        string memory tokenURI_,
        uint256 fractions
    ) external onlyOwner {
        require(fractions > 0, "Must mint at least 1 fraction");
        require(bytes(_tokenURIs[tokenId]).length == 0, "Token already minted");

        _mint(msg.sender, tokenId, fractions, "");
        _tokenURIs[tokenId] = tokenURI_;
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
        emit URI(newURI, tokenId);
    }

    // ===== SBT-Style Transfer Restriction =====

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
        _safeTransferFrom(from, to, tokenId, amount, "");
    }

    // ===== Transfer Override for Owner-Only with KYC =====

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
        } else {
            revert("Batch transfers not allowed. Only owner can transfer.");
        }
    }

    // ===== Marketplace Compatibility =====

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
