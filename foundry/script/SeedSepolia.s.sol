// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/MerchantPayments.sol";
import "../src/MockERC20.sol";

/**
 * @title SeedSepolia
 * @notice Sepolia-compatible seeding script — uses only PRIVATE_KEY (single signer).
 *         The deployer acts as the payer for all payments, which means velocity kicks
 *         in after MAX_PAYMENTS_PER_WINDOW = 3, giving a natural mix of classifications.
 *
 * Prerequisites:
 *   1. Deploy: forge script script/Deploy.s.sol:Deploy --rpc-url sepolia --broadcast --verify -vvvv
 *   2. Set MERCHANT_PAYMENTS_ADDRESS and MOCK_ERC20_ADDRESS in your .env
 *
 * Usage:
 *   forge script script/SeedSepolia.s.sol:SeedSepolia \
 *     --rpc-url sepolia \
 *     --broadcast \
 *     -vvvv
 *
 * Payment mix produced (thresholds: highValue=10k, suspicious=50k, maxPerWindow=3):
 *   pay1:  500 USDC   → UNCLASSIFIED  (below HIGH_VALUE threshold, no velocity breach yet)
 *   pay2:  1,200 USDC → UNCLASSIFIED  (same)
 *   pay3:  15,000 USDC → HIGH_VALUE   (fills velocity window)
 *   pay4:  300 USDC   → SUSPICIOUS   (velocity breach)
 *   pay5:  450 USDC   → SUSPICIOUS   (velocity breach)
 *
 * classifyPayment and requestRefund are intentionally NOT called here.
 * Mixing payment creation and ID-dependent calls in one script fails because
 * block.timestamp differs between local dry-run and on-chain simulation,
 * producing different payment IDs. Run classify/refund in a separate script
 * after payments are confirmed on-chain.
 */
contract SeedSepolia is Script {

    address constant SEED_MERCHANT = address(0xdeADbeEf00000000000000000000000000000002);

    uint256 constant HIGH_VALUE_THRESHOLD    = 10_000 * 1e6;
    uint256 constant SUSPICIOUS_THRESHOLD    = 50_000 * 1e6;
    uint256 constant DAILY_LIMIT            = 10_000_000 * 1e6;
    uint256 constant FEE_RATE_BPS           = 30;
    uint256 constant VELOCITY_WINDOW_SECS   = 3600;
    uint256 constant MAX_PAYMENTS_PER_WINDOW = 3;

    function run() external {
        uint256 deployerKey  = vm.envUint("PRIVATE_KEY");
        address mpAddr       = vm.envAddress("MERCHANT_PAYMENTS_ADDRESS");
        address usdcAddr     = vm.envAddress("MOCK_ERC20_ADDRESS");

        MerchantPayments mp   = MerchantPayments(mpAddr);
        MockERC20        usdc = MockERC20(usdcAddr);

        console.log("=================================================");
        console.log("SeedSepolia");
        console.log("=================================================");
        console.log("MerchantPayments:", mpAddr);
        console.log("MockERC20:       ", usdcAddr);

        vm.startBroadcast(deployerKey);

        // ------------------------------------------------------------------
        // 1. Register seed merchant (skip if already registered)
        // ------------------------------------------------------------------
        (address registeredAddr,,,,,,,,,) = mp.getMerchantConfig(SEED_MERCHANT);
        if (registeredAddr == address(0)) {
            mp.registerMerchant(
                SEED_MERCHANT,
                "Seed Merchant",
                MerchantPayments.MerchantTier.ENTERPRISE,
                HIGH_VALUE_THRESHOLD,
                SUSPICIOUS_THRESHOLD
            );
            mp.setTokenAllowed(SEED_MERCHANT, usdcAddr, true);
            mp.updateMerchantConfig(
                SEED_MERCHANT,
                DAILY_LIMIT,
                FEE_RATE_BPS,
                VELOCITY_WINDOW_SECS,
                MAX_PAYMENTS_PER_WINDOW
            );
            console.log("Seed merchant registered:", SEED_MERCHANT);
        } else {
            console.log("Seed merchant already registered, skipping.");
        }

        // ------------------------------------------------------------------
        // 2. Mint tokens to deployer (so usdc balance reflects in logs)
        // ------------------------------------------------------------------
        usdc.mint(vm.addr(deployerKey), 5_000_000 * 1e6);

        // ------------------------------------------------------------------
        // 3. Payments — deployer is payer for all
        // ------------------------------------------------------------------

        // pay1: 500 USDC — below HIGH_VALUE threshold → UNCLASSIFIED
        mp.receivePayment(SEED_MERCHANT, usdcAddr, 500 * 1e6, "USD", "USD", "order:SEP001");
        console.log("pay1 sent (UNCLASSIFIED)");

        // pay2: 1,200 USDC — below HIGH_VALUE threshold → UNCLASSIFIED
        mp.receivePayment(SEED_MERCHANT, usdcAddr, 1_200 * 1e6, "GBP", "GBP", "order:SEP002");
        console.log("pay2 sent (UNCLASSIFIED)");

        // pay3: 15,000 USDC — above HIGH_VALUE threshold, fills velocity window → HIGH_VALUE
        mp.receivePayment(SEED_MERCHANT, usdcAddr, 15_000 * 1e6, "EUR", "EUR", "order:SEP003");
        console.log("pay3 sent (HIGH_VALUE)");

        // pay4: 300 USDC — velocity breach (4th payment) → SUSPICIOUS
        mp.receivePayment(SEED_MERCHANT, usdcAddr, 300 * 1e6, "USD", "USD", "order:SEP004");
        console.log("pay4 sent (SUSPICIOUS - velocity)");

        // pay5: 450 USDC — velocity breach (5th payment) → SUSPICIOUS
        mp.receivePayment(SEED_MERCHANT, usdcAddr, 450 * 1e6, "USD", "USD", "order:SEP005");
        console.log("pay5 sent (SUSPICIOUS - velocity)");

        vm.stopBroadcast();

        console.log("");
        console.log("=================================================");
        console.log("Seed summary");
        console.log("=================================================");
        console.log("UNCLASSIFIED: 2  (pay1, pay2) - awaiting Kwala classifyPayment");
        console.log("HIGH_VALUE:   1  (pay3)       - 15k USDC > 10k threshold");
        console.log("SUSPICIOUS:   2  (pay4, pay5) - velocity breach after 3rd payment");
        console.log("");
        console.log("Next step: npm run seed:redis");
        console.log("=================================================");
    }
}
