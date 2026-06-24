// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/MerchantPayments.sol";
import "../src/MockERC20.sol";

/**
 * @title Seed
 * @notice Generates varied on-chain payment data for local / testnet demos.
 *         Kwala listens to the emitted events and propagates them through to the
 *         Next.js API routes and dashboard.
 *
 * Usage (local Anvil — deploy + seed in one shot):
 *   anvil &
 *   forge script script/Seed.s.sol:Seed \
 *     --rpc-url http://127.0.0.1:8545 \
 *     --broadcast \
 *     -vvvv
 *
 * Usage (use an existing deployment):
 *   MERCHANT_PAYMENTS_ADDRESS=0x... MOCK_ERC20_ADDRESS=0x... \
 *   forge script script/Seed.s.sol:Seed \
 *     --rpc-url http://127.0.0.1:8545 \
 *     --broadcast \
 *     -vvvv
 *
 * Payment mix produced (thresholds: highValue=10k, suspicious=50k, maxPerWindow=3):
 *   Payer A: 5 payments → pay 1-3 STANDARD, pay 4-5 SUSPICIOUS (velocity breach)
 *   Payer B: 3 payments → 1 STANDARD, 2 HIGH_VALUE
 *   Payer C: 3 payments → 1 STANDARD, 1 HIGH_VALUE, 1 SUSPICIOUS (amount threshold)
 *   After seeding: requestRefund() on first payment from Payer A
 */
contract Seed is Script {

    // -------------------------------------------------------------------------
    // Anvil well-known private keys (accounts 0-3)
    // -------------------------------------------------------------------------
    uint256 constant DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant PAYER_A_KEY  = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant PAYER_B_KEY  = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 constant PAYER_C_KEY  = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

    // -------------------------------------------------------------------------
    // Seed merchant — separate from the demo merchant in Deploy.s.sol
    // -------------------------------------------------------------------------
    address constant SEED_MERCHANT = address(0xdeADbeEf00000000000000000000000000000002);

    // Low max-per-window so velocity breaches happen quickly
    uint256 constant HIGH_VALUE_THRESHOLD    = 10_000 * 1e6;  // 10k USDC
    uint256 constant SUSPICIOUS_THRESHOLD    = 50_000 * 1e6;  // 50k USDC
    uint256 constant DAILY_LIMIT            = 10_000_000 * 1e6;
    uint256 constant FEE_RATE_BPS           = 30;
    uint256 constant VELOCITY_WINDOW_SECS   = 3600;
    uint256 constant MAX_PAYMENTS_PER_WINDOW = 3; // 4th payment triggers velocity breach

    uint256 constant MINT_PER_PAYER = 5_000_000 * 1e6; // 5M mUSDC each

    // -------------------------------------------------------------------------
    // run()
    // -------------------------------------------------------------------------
    function run() external {
        address deployer = vm.addr(DEPLOYER_KEY);
        address payerA   = vm.addr(PAYER_A_KEY);
        address payerB   = vm.addr(PAYER_B_KEY);
        address payerC   = vm.addr(PAYER_C_KEY);

        // ------------------------------------------------------------------
        // 1. Deploy or load MerchantPayments + MockERC20
        // ------------------------------------------------------------------
        MerchantPayments mp;
        MockERC20        usdc;

        address mpAddr   = vm.envOr("MERCHANT_PAYMENTS_ADDRESS", address(0));
        address usdcAddr = vm.envOr("MOCK_ERC20_ADDRESS",        address(0));

        vm.startBroadcast(DEPLOYER_KEY);

        if (mpAddr == address(0)) {
            mp   = new MerchantPayments();
            usdc = new MockERC20();
            console.log("Deployed MerchantPayments:", address(mp));
            console.log("Deployed MockERC20:       ", address(usdc));
        } else {
            mp   = MerchantPayments(mpAddr);
            usdc = MockERC20(usdcAddr);
            console.log("Using existing MerchantPayments:", address(mp));
            console.log("Using existing MockERC20:       ", address(usdc));
        }

        // ------------------------------------------------------------------
        // 2. Register seed merchant (skip if already registered)
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
            mp.setTokenAllowed(SEED_MERCHANT, address(usdc), true);
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
        // 3. Mint tokens to each payer
        // ------------------------------------------------------------------
        usdc.mint(payerA, MINT_PER_PAYER);
        usdc.mint(payerB, MINT_PER_PAYER);
        usdc.mint(payerC, MINT_PER_PAYER);
        console.log("Minted tokens to payers.");

        vm.stopBroadcast();

        // ==================================================================
        // PAYER A — 5 payments; velocity window = 3, so #4 and #5 = SUSPICIOUS
        // ==================================================================
        vm.startBroadcast(PAYER_A_KEY);

        bytes32 payA1 = mp.receivePayment(SEED_MERCHANT, address(usdc), 500  * 1e6, "USD", "USD", "order:A001"); // STANDARD
        console.log("Payer A pay #1 (STANDARD):");
        console.logBytes32(payA1);

        bytes32 payA2 = mp.receivePayment(SEED_MERCHANT, address(usdc), 1_200 * 1e6, "USD", "USD", "order:A002"); // STANDARD
        console.log("Payer A pay #2 (STANDARD):");
        console.logBytes32(payA2);

        bytes32 payA3 = mp.receivePayment(SEED_MERCHANT, address(usdc), 800  * 1e6, "USD", "USD", "order:A003"); // STANDARD (fills window)
        console.log("Payer A pay #3 (STANDARD, fills velocity window):");
        console.logBytes32(payA3);

        bytes32 payA4 = mp.receivePayment(SEED_MERCHANT, address(usdc), 300  * 1e6, "USD", "USD", "order:A004"); // SUSPICIOUS — velocity breach
        console.log("Payer A pay #4 (SUSPICIOUS - velocity breach):");
        console.logBytes32(payA4);

        bytes32 payA5 = mp.receivePayment(SEED_MERCHANT, address(usdc), 450  * 1e6, "USD", "USD", "order:A005"); // SUSPICIOUS — velocity breach
        console.log("Payer A pay #5 (SUSPICIOUS - velocity breach):");
        console.logBytes32(payA5);

        vm.stopBroadcast();

        // ==================================================================
        // PAYER B — 1 STANDARD + 2 HIGH_VALUE
        // ==================================================================
        vm.startBroadcast(PAYER_B_KEY);

        bytes32 payB1 = mp.receivePayment(SEED_MERCHANT, address(usdc), 2_500  * 1e6, "GBP", "GBP", "order:B001"); // STANDARD
        console.log("Payer B pay #1 (STANDARD):");
        console.logBytes32(payB1);

        bytes32 payB2 = mp.receivePayment(SEED_MERCHANT, address(usdc), 15_000 * 1e6, "GBP", "GBP", "order:B002"); // HIGH_VALUE
        console.log("Payer B pay #2 (HIGH_VALUE):");
        console.logBytes32(payB2);

        bytes32 payB3 = mp.receivePayment(SEED_MERCHANT, address(usdc), 22_000 * 1e6, "GBP", "GBP", "order:B003"); // HIGH_VALUE
        console.log("Payer B pay #3 (HIGH_VALUE):");
        console.logBytes32(payB3);

        vm.stopBroadcast();

        // ==================================================================
        // PAYER C — 1 STANDARD + 1 HIGH_VALUE + 1 SUSPICIOUS (amount threshold)
        // ==================================================================
        vm.startBroadcast(PAYER_C_KEY);

        bytes32 payC1 = mp.receivePayment(SEED_MERCHANT, address(usdc), 4_000  * 1e6, "EUR", "EUR", "order:C001"); // STANDARD
        console.log("Payer C pay #1 (STANDARD):");
        console.logBytes32(payC1);

        bytes32 payC2 = mp.receivePayment(SEED_MERCHANT, address(usdc), 12_500 * 1e6, "EUR", "EUR", "order:C002"); // HIGH_VALUE
        console.log("Payer C pay #2 (HIGH_VALUE):");
        console.logBytes32(payC2);

        bytes32 payC3 = mp.receivePayment(SEED_MERCHANT, address(usdc), 55_000 * 1e6, "EUR", "EUR", "order:C003"); // SUSPICIOUS — above 50k threshold
        console.log("Payer C pay #3 (SUSPICIOUS - amount threshold):");
        console.logBytes32(payC3);

        vm.stopBroadcast();

        // ==================================================================
        // Refund request — payer A requests refund on their first payment
        // ==================================================================
        vm.startBroadcast(PAYER_A_KEY);
        mp.requestRefund(payA1, 500 * 1e6, "duplicate charge");
        console.log("Refund requested on payA1.");
        vm.stopBroadcast();

        // ------------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------------
        console.log("");
        console.log("=================================================");
        console.log("Seed summary");
        console.log("=================================================");
        console.log("MerchantPayments:", address(mp));
        console.log("MockERC20:       ", address(usdc));
        console.log("Seed merchant:   ", SEED_MERCHANT);
        console.log("Deployer:        ", deployer);
        console.log("Payer A:         ", payerA);
        console.log("Payer B:         ", payerB);
        console.log("Payer C:         ", payerC);
        console.log("Payments created: 11");
        console.log("  STANDARD:   5  (A1, A2, A3, B1, C1)");
        console.log("  HIGH_VALUE: 3  (B2, B3, C2)");
        console.log("  SUSPICIOUS: 3  (A4, A5, C3)");
        console.log("Refund requested: payA1");
        console.log("=================================================");
    }
}
