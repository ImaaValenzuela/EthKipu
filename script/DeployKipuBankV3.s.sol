// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/KipuBankV3.sol";

contract DeployKipuBankV3 is Script {
    // Sepolia addresses
    address constant UNISWAP_ROUTER = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;
    address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    
    uint256 constant BANK_CAP = 100_000_000000; // 100k USDC
    uint256 constant WITHDRAWAL_LIMIT = 10_000_000000; // 10k USDC

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        KipuBankV3 bank = new KipuBankV3(
            UNISWAP_ROUTER,
            USDC,
            BANK_CAP,
            WITHDRAWAL_LIMIT
        );
        
        console.log("KipuBankV3 deployed:", address(bank));
        console.log("Bank Cap:", BANK_CAP / 1e6, "USDC");
        console.log("Withdrawal Limit:", WITHDRAWAL_LIMIT / 1e6, "USDC");
        
        vm.stopBroadcast();
    }
}