# KYC-Contracts
This repository contains two Solidity contracts:

1. `KYCStorage.sol` – the main contract that stores and manages KYC data on-chain.
2. `KYCChecker.sol` – a sample external contract that integrates with the KYC system to check wallet verification status.

---
## 🧩 Overview

The goal is to maintain off-chain verified KYC identities and link them to one or more wallet addresses on-chain. Other contracts (e.g., property marketplaces, token contracts) can verify if a wallet is KYC-verified by calling a single view function.

---

## 📂 Contracts

### `KYCStorage.sol`

Main contract for managing KYC data:
- Stores encrypted KYC data
- Links multiple wallet addresses to a single off-chain user ID
- Supports expiry and re-verification of KYC
- Restricts mutation functions to the contract `owner`

#### Key Functions

| Function | Description |
|---------|-------------|
| `addKYC(userId, wallet, encryptedData, validUntil)` | Adds a new KYC record |
| `linkWallet(userId, newWallet)` | Links another wallet to the user |
| `updateKYC(userId, encryptedData, newValidUntil)` | Updates encrypted data and expiry |
| `isWalletKYCed(wallet)` | Returns `true` if wallet is KYCed and not expired |
| `getEncryptedData(userId)` | View-only encrypted KYC blob (owner-only) |

---
### `KYCChecker.sol`

This is a lightweight external contract that consumes the `KYCStorage` contract and reads verification status via `isWalletKYCed()`.

```solidity
interface IKYC {
    function isWalletKYCed(address wallet) external view returns (bool);
}

contract KYCChecker {
    IKYC public kycContract;

    constructor(address _kycContractAddress) {
        kycContract = IKYC(_kycContractAddress);
    }

    function checkKYCStatus(address wallet) external view returns (bool) {
        return kycContract.isWalletKYCed(wallet);
    }
}
```

## 🚀 Deployment Steps (Sepolia via Remix)

### 1. Deploy `KYCStorage.sol`

1. Open [Remix IDE](https://remix.ethereum.org)
2. Paste the contents of `KYCStorage.sol` into a new file and compile it.
3. Go to the **"Deploy & Run Transactions"** panel.
4. Set environment to **"Injected Provider - MetaMask"** (make sure you are connected to Sepolia).
5. Select the `KYCStorage` contract and click **Deploy**.
6. Confirm the transaction in MetaMask.
7. After deployment, copy the deployed contract address.  
   Example: `0xAF9d2703F04b9e43fca923ca3FaD658E5C30959e`

---

### 2. Add a New KYC Record

1. In the deployed contract panel in Remix, expand the `addKYC` function.
2. Fill in the inputs:

- `userId`:  
  Use the hashed form of a user string:  
  `0x6e8f5079d9337a5dbf3c45b09b7789e9a0bfae3bca28c556df4c7b125da7e5d8`  
  (This is `keccak256("user1234")`)
  
- `wallet`:  
  Any Sepolia test wallet, e.g.  
  `0x1234567890123456789012345678901234567890`

- `encryptedData`:  
  Example:  
  `0x746869735f69735f656e637279707465645f6b79635f64617461`  
  (`"this_is_encrypted_kyc_data"` in hex)

- `validUntil`:  
  A future UNIX timestamp, e.g.  
  `1752500000` (roughly July 2025)

3. Click **Transact**, and approve in MetaMask.

---

### 3. Link Additional Wallets

1. Call `linkWallet(userId, newWallet)`
2. The new wallet will be added to the user’s whitelist.

---

### 4. Update or Renew KYC (if expired)

1. Call `updateKYC(userId, newEncryptedData, newValidUntil)`
2. Example:
- `userId`: same as above
- `newEncryptedData`: `0x01`
- `newValidUntil`: `1755000000` (future timestamp)

---

### 5. Check KYC Status

- Call `isWalletKYCed(wallet)`  
- Returns `true` if KYC is valid and not expired

---