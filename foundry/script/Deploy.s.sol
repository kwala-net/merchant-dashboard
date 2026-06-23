// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/MerchantPayments.sol";
import "../src/MockERC20.sol";

/**
 * @title Deploy
 * @notice Forge deployment script for the OnchainPay merchant payment system.
 *
 * Usage (Sepolia testnet):
 *   forge script script/Deploy.s.sol:Deploy \
 *     --rpc-url sepolia \
 *     --broadcast \
 *     --verify \
 *     -vvvv
 *
 * Usage (local Anvil):
 *   forge script script/Deploy.s.sol:Deploy \
 *     --rpc-url http://127.0.0.1:8545 \
 *     --broadcast \
 *     -vvvv
 *
 * The script:
 *   1. Deploys MerchantPayments.
 *   2. Deploys MockERC20 (Mock USDC, 6 decimals).
 *   3. Registers a sample merchant ("OnchainPay Demo Merchant") as GROWTH tier.
 *   4. Allowlists MockERC20 for the sample merchant.
 *   5. Mints 1,000,000 mUSDC to the deployer for testing.
 *   6. Logs all deployed addresses via the Forge console.
 */
contract Deploy is Script {
    // -----------------------------------------------------------------------
    // Sample merchant parameters
    // -----------------------------------------------------------------------

    /// @dev Change this to the merchant wallet you want to use in tests / demos.
    address internal constant SAMPLE_MERCHANT = address(0xdEADbeEF00000000000000000000000000000001);

    string  internal constant MERCHANT_NAME       = "OnchainPay Demo Merchant";
    uint256 internal constant HIGH_VALUE_THRESHOLD    = 500 * 1e6;   // 500 USDC
    uint256 internal constant SUSPICIOUS_THRESHOLD    = 900 * 1e6;   // 900 USDC
    uint256 internal constant DAILY_LIMIT             = 100_000 * 1e6; // 100k USDC / day
    uint256 internal constant FEE_RATE_BPS            = 30;           // 0.30 %
    uint256 internal constant VELOCITY_WINDOW_SECS    = 3600;         // 1 hour
    uint256 internal constant MAX_PAYMENTS_PER_WINDOW = 200;

    uint256 internal constant MINT_AMOUNT = 1_000_000 * 1e6; // 1M mUSDC

    // -----------------------------------------------------------------------
    // run()
    // -----------------------------------------------------------------------

    function run() external {
        // Load the private key from the environment (PRIVATE_KEY=0x...).
        uint256 deployerKey  = vm.envUint("PRIVATE_KEY");
        address deployer     = vm.addr(deployerKey);

        console.log("=================================================");
        console.log("OnchainPay Deployment Script");
        console.log("=================================================");
        console.log("Deployer:         ", deployer);
        console.log("Chain ID:         ", block.chainid);
        console.log("Block number:     ", block.number);
        console.log("");

        vm.startBroadcast(deployerKey);

        // ------------------------------------------------------------------
        // 1. Deploy MerchantPayments
        // ------------------------------------------------------------------
        MerchantPayments mp = new MerchantPayments();
        console.log("MerchantPayments deployed at:", address(mp));

        // ------------------------------------------------------------------
        // 2. Deploy MockERC20 (Mock USDC)
        // ------------------------------------------------------------------
        MockERC20 usdc = new MockERC20();
        console.log("MockERC20 (mUSDC) deployed at:", address(usdc));

        // ------------------------------------------------------------------
        // 3. Register the sample merchant
        //    (deployer is automatically an operator after construction)
        // ------------------------------------------------------------------
        mp.registerMerchant(
            SAMPLE_MERCHANT,
            MERCHANT_NAME,
            MerchantPayments.MerchantTier.GROWTH,
            HIGH_VALUE_THRESHOLD,
            SUSPICIOUS_THRESHOLD
        );
        console.log("Sample merchant registered:   ", SAMPLE_MERCHANT);

        // ------------------------------------------------------------------
        // 4. Allowlist MockERC20 for the sample merchant
        // ------------------------------------------------------------------
        mp.setTokenAllowed(SAMPLE_MERCHANT, address(usdc), true);
        console.log("MockERC20 allowlisted for merchant.");

        // ------------------------------------------------------------------
        // 5. Configure the sample merchant's runtime parameters
        // ------------------------------------------------------------------
        mp.updateMerchantConfig(
            SAMPLE_MERCHANT,
            DAILY_LIMIT,
            FEE_RATE_BPS,
            VELOCITY_WINDOW_SECS,
            MAX_PAYMENTS_PER_WINDOW
        );
        console.log("Merchant config updated.");

        // ------------------------------------------------------------------
        // 6. Mint test tokens to the deployer
        // ------------------------------------------------------------------
        usdc.mint(deployer, MINT_AMOUNT);
        console.log("Minted", MINT_AMOUNT / 1e6, "mUSDC to deployer.");

        vm.stopBroadcast();

        // ------------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------------
        console.log("");
        console.log("=================================================");
        console.log("Deployment summary");
        console.log("=================================================");
        console.log("MerchantPayments : ", address(mp));
        console.log("MockERC20 (mUSDC): ", address(usdc));
        console.log("Sample merchant  : ", SAMPLE_MERCHANT);
        console.log("Deployer balance : ", usdc.balanceOf(deployer) / 1e6, "mUSDC");
        console.log("=================================================");
    }
}
