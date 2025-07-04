// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract KYCStorage {
    struct KYCRecord {
        bytes32 userId;           // Off-chain user ID, hashed
        bytes encryptedData;      // Encrypted KYC blob (off-chain processed)
        uint256 validUntil;       // Expiry timestamp
        bool exists;              // Internal check
    }

    address public owner;
    mapping(address => bytes32) public walletToUserId;
    mapping(bytes32 => KYCRecord) private kycRecords;
    mapping(bytes32 => address[]) private userWallets;

    event KYCAdded(bytes32 indexed userId, address indexed wallet, uint256 validUntil);
    event WalletLinked(bytes32 indexed userId, address indexed wallet);
    event KYCUpdated(bytes32 indexed userId, uint256 newExpiry);
    event KYCDeleted(bytes32 indexed userId);
    event WalletRemoved(bytes32 indexed userId, address indexed wallet);
    event WalletReplaced(bytes32 indexed userId, address indexed wallet, address indexed newWallet);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function addKYC(
        bytes32 userId,
        address wallet,
        bytes calldata encryptedData,
        uint256 validUntil
    ) external onlyOwner {
        require(!kycRecords[userId].exists, "User already exists");
        require(walletToUserId[wallet] == bytes32(0), "Wallet already linked");

        kycRecords[userId] = KYCRecord({
            userId: userId,
            encryptedData: encryptedData,
            validUntil: validUntil,
            exists: true
        });

        walletToUserId[wallet] = userId;
        userWallets[userId].push(wallet);

        emit KYCAdded(userId, wallet, validUntil);
    }

    function linkWallet(bytes32 userId, address newWallet) external onlyOwner {
        require(kycRecords[userId].exists, "User does not exist");
        require(walletToUserId[newWallet] == bytes32(0), "Wallet already linked");

        walletToUserId[newWallet] = userId;
        userWallets[userId].push(newWallet);

        emit WalletLinked(userId, newWallet);
    }

    function removeKYC(bytes32 userId) external onlyOwner {
    require(kycRecords[userId].exists, "User does not exist");

    // Unlink all wallets
    address[] memory wallets = userWallets[userId];
    for (uint256 i = 0; i < wallets.length; i++) {
        delete walletToUserId[wallets[i]];
    }

    delete userWallets[userId];
    delete kycRecords[userId];

    emit KYCDeleted(userId);
}

function removeLinkedWalletAddress(bytes32 userId, address wallet) external onlyOwner {
    require(kycRecords[userId].exists, "User does not exist");
    require(walletToUserId[wallet] == userId, "Wallet not linked to user");

    address[] storage wallets = userWallets[userId];
    require(wallets.length > 1, "Cannot remove last wallet");

    // Remove wallet from userWallets
    for (uint256 i = 0; i < wallets.length; i++) {
        if (wallets[i] == wallet) {
            wallets[i] = wallets[wallets.length - 1];
            wallets.pop();
            break;
        }
    }
    delete walletToUserId[wallet];
    emit WalletRemoved(userId, wallet);
}

function replaceWallet(bytes32 userId, address oldWallet, address newWallet) external onlyOwner {
    require(kycRecords[userId].exists, "User does not exist");
    require(walletToUserId[oldWallet] == userId, "Old wallet not linked");
    require(walletToUserId[newWallet] == bytes32(0), "New wallet already linked");

    address[] storage wallets = userWallets[userId];
    for (uint256 i = 0; i < wallets.length; i++) {
        if (wallets[i] == oldWallet) {
            wallets[i] = newWallet;
            break;
        }
    }

    delete walletToUserId[oldWallet];
    walletToUserId[newWallet] = userId;
    emit WalletReplaced(userId, oldWallet, newWallet);
}

    function updateKYC(
        bytes32 userId,
        bytes calldata newEncryptedData,
        uint256 newValidUntil
    ) external onlyOwner {
        require(kycRecords[userId].exists, "User does not exist");

        kycRecords[userId].encryptedData = newEncryptedData;
        kycRecords[userId].validUntil = newValidUntil;

        emit KYCUpdated(userId, newValidUntil);
    }

    function isWalletKYCed(address wallet) public view returns (bool) {
        bytes32 userId = walletToUserId[wallet];
        if (userId == bytes32(0)) return false;

        KYCRecord memory record = kycRecords[userId];
        return block.timestamp <= record.validUntil;
    }

    function getKYCStatus(address wallet) external view returns (
    bytes32 userId,
    uint256 currentTime,
    uint256 validUntil,
    bool isValid
) {
    userId = walletToUserId[wallet];
    if (userId == bytes32(0)) {
        return (bytes32(0), block.timestamp, 0, false);
    }

    KYCRecord memory record = kycRecords[userId];
    return (userId, block.timestamp, record.validUntil, block.timestamp <= record.validUntil);
}

    function getEncryptedData(bytes32 userId) external view onlyOwner returns (bytes memory) {
        require(kycRecords[userId].exists, "No KYC");
        return kycRecords[userId].encryptedData;
    }

    function getUserWallets(bytes32 userId) external view returns (address[] memory) {
        return userWallets[userId];
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }
}
