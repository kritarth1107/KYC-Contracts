// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Interface to the external KYC contract
interface IKYC {
    function isWalletKYCed(address wallet) external view returns (bool);
}

contract KYCChecker {
    IKYC public kycContract;

    constructor(address _kycContractAddress) {
        kycContract = IKYC(_kycContractAddress);
    }

    // Read-only function to check KYC status
    function checkKYCStatus(address wallet) external view returns (bool) {
        return kycContract.isWalletKYCed(wallet);
    }
}
