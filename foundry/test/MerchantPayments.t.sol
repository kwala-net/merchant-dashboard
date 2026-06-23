// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MerchantPayments.sol";
import "../src/MockERC20.sol";

/**
 * @title MerchantPaymentsTest
 * @notice Comprehensive Forge test suite for the MerchantPayments contract.
 *
 * Test strategy
 * ─────────────
 *  • Each test is independent — setUp() redeploys fresh contracts.
 *  • Helper _registerAndFundMerchant() handles boilerplate.
 *  • Events are checked with vm.expectEmit where the exact fields matter.
 *  • Revert paths are checked with vm.expectRevert.
 */
contract MerchantPaymentsTest is Test {
    // =========================================================================
    // State
    // =========================================================================

    MerchantPayments internal mp;
    MockERC20        internal usdc;

    address internal owner        = address(this);
    address internal merchant     = makeAddr("merchant");
    address internal payer        = makeAddr("payer");
    address internal operator     = makeAddr("operator");
    address internal classifier   = makeAddr("classifier");
    address internal randomUser   = makeAddr("randomUser");

    // Convenience constants (6-decimal USDC amounts).
    uint256 internal constant ONE_USDC        = 1e6;
    uint256 internal constant HUNDRED_USDC    = 100 * ONE_USDC;
    uint256 internal constant THOUSAND_USDC   = 1000 * ONE_USDC;
    uint256 internal constant HIGH_VALUE_THRESHOLD    = 500 * ONE_USDC;
    uint256 internal constant SUSPICIOUS_THRESHOLD    = 900 * ONE_USDC;

    // =========================================================================
    // Setup
    // =========================================================================

    function setUp() public {
        mp   = new MerchantPayments();
        usdc = new MockERC20();

        // Grant roles.
        mp.addOperator(operator);
        mp.addClassifier(classifier);
    }

    // =========================================================================
    // Internal Helpers
    // =========================================================================

    /**
     * @dev Register `merchant`, allowlist `usdc`, and mint tokens to `payer`.
     *      Returns so callers can chain.
     */
    function _registerAndFundMerchant() internal {
        vm.prank(operator);
        mp.registerMerchant(
            merchant,
            "Acme Store",
            MerchantPayments.MerchantTier.STARTER,
            HIGH_VALUE_THRESHOLD,
            SUSPICIOUS_THRESHOLD
        );

        // Allowlist the mock USDC token.
        vm.prank(operator);
        mp.setTokenAllowed(merchant, address(usdc), true);

        // Fund payer.
        usdc.mint(payer, 10_000 * ONE_USDC);
    }

    /**
     * @dev Submit a payment from `payer` to `merchant` and return its paymentId.
     */
    function _pay(uint256 amount) internal returns (bytes32 paymentId) {
        vm.prank(payer);
        paymentId = mp.receivePayment(
            merchant,
            address(usdc),
            amount,
            bytes3("USA"),
            bytes3("USD"),
            '{"orderId":"order-1"}'
        );
    }

    // =========================================================================
    // testRegisterMerchant
    // =========================================================================

    function testRegisterMerchant() public {
        vm.expectEmit(true, false, false, true);
        emit MerchantPayments.MerchantRegistered(
            merchant,
            "Acme Store",
            MerchantPayments.MerchantTier.STARTER
        );

        vm.prank(operator);
        mp.registerMerchant(
            merchant,
            "Acme Store",
            MerchantPayments.MerchantTier.STARTER,
            HIGH_VALUE_THRESHOLD,
            SUSPICIOUS_THRESHOLD
        );

        // Verify stored config.
        (
            address storedAddr,
            string memory storedName,
            MerchantPayments.MerchantTier storedTier,
            bool active,
            ,,,,,
        ) = mp.getMerchantConfig(merchant);

        assertEq(storedAddr,  merchant,      "address mismatch");
        assertEq(storedName,  "Acme Store",  "name mismatch");
        assertTrue(uint8(storedTier) == uint8(MerchantPayments.MerchantTier.STARTER), "tier mismatch");
        assertTrue(active, "should be active");
    }

    function testRegisterMerchant_RevertsForNonOperator() public {
        vm.prank(randomUser);
        vm.expectRevert("MerchantPayments: not operator");
        mp.registerMerchant(
            merchant,
            "Rogue",
            MerchantPayments.MerchantTier.FREE,
            0,
            0
        );
    }

    function testRegisterMerchant_RevertsForZeroAddress() public {
        vm.prank(operator);
        vm.expectRevert("MerchantPayments: zero address");
        mp.registerMerchant(
            address(0),
            "Zero",
            MerchantPayments.MerchantTier.FREE,
            0,
            0
        );
    }

    function testRegisterMerchant_RevertsForEmptyName() public {
        vm.prank(operator);
        vm.expectRevert("MerchantPayments: empty name");
        mp.registerMerchant(
            merchant,
            "",
            MerchantPayments.MerchantTier.FREE,
            0,
            0
        );
    }

    // =========================================================================
    // testReceivePayment
    // =========================================================================

    function testReceivePayment() public {
        _registerAndFundMerchant();

        uint256 amount = HUNDRED_USDC;

        // Submit the payment and capture the id returned.
        vm.prank(payer);
        bytes32 paymentId = mp.receivePayment(
            merchant,
            address(usdc),
            amount,
            bytes3("USA"),
            bytes3("USD"),
            '{"orderId":"order-1"}'
        );

        assertTrue(paymentId != bytes32(0), "payment id should be non-zero");

        MerchantPayments.Payment memory p = mp.getPayment(paymentId);
        assertEq(p.payer,          payer,         "payer mismatch");
        assertEq(p.merchant,       merchant,      "merchant mismatch");
        assertEq(p.amount,         amount,        "amount mismatch");
        assertEq(p.tokenAddress,   address(usdc), "token mismatch");
        assertTrue(
            uint8(p.status) == uint8(MerchantPayments.PaymentStatus.PENDING),
            "should be PENDING"
        );

        // Global stats incremented.
        (uint256 gVol, uint256 gPay) = mp.getGlobalStats();
        assertEq(gVol, amount, "global volume");
        assertEq(gPay, 1,      "global payment count");
    }

    function testReceivePayment_RevertsWhenPaused() public {
        _registerAndFundMerchant();
        mp.pause();

        vm.prank(payer);
        vm.expectRevert("MerchantPayments: contract is paused");
        mp.receivePayment(merchant, address(usdc), HUNDRED_USDC, bytes3("USA"), bytes3("USD"), "");
    }

    function testReceivePayment_RevertsForUnregisteredMerchant() public {
        vm.prank(payer);
        vm.expectRevert("MerchantPayments: merchant not registered");
        mp.receivePayment(merchant, address(usdc), HUNDRED_USDC, bytes3("USA"), bytes3("USD"), "");
    }

    function testReceivePayment_RevertsForDisallowedToken() public {
        vm.prank(operator);
        mp.registerMerchant(
            merchant,
            "Token Test",
            MerchantPayments.MerchantTier.STARTER,
            0,
            0
        );
        // Token NOT allowlisted.

        vm.prank(payer);
        vm.expectRevert("MerchantPayments: token not allowed for merchant");
        mp.receivePayment(merchant, address(usdc), HUNDRED_USDC, bytes3("USA"), bytes3("USD"), "");
    }

    function testReceivePayment_RevertsForZeroAmount() public {
        _registerAndFundMerchant();

        vm.prank(payer);
        vm.expectRevert("MerchantPayments: zero amount");
        mp.receivePayment(merchant, address(usdc), 0, bytes3("USA"), bytes3("USD"), "");
    }

    // =========================================================================
    // testClassifyPaymentHighValue
    // =========================================================================

    function testClassifyPaymentHighValue() public {
        _registerAndFundMerchant();

        // Submit an amount that is ABOVE the high-value threshold but below suspicious.
        uint256 amount = HIGH_VALUE_THRESHOLD + ONE_USDC;
        bytes32 paymentId = _pay(amount);

        // Auto-classified as HIGH_VALUE during receivePayment.
        MerchantPayments.Payment memory p = mp.getPayment(paymentId);
        assertTrue(
            uint8(p.classification) == uint8(MerchantPayments.PaymentClassification.HIGH_VALUE),
            "should be HIGH_VALUE"
        );

        // Classifier can override classification.
        vm.prank(classifier);
        mp.classifyPayment(paymentId, MerchantPayments.PaymentClassification.STANDARD);

        MerchantPayments.Payment memory p2 = mp.getPayment(paymentId);
        assertTrue(
            uint8(p2.classification) == uint8(MerchantPayments.PaymentClassification.STANDARD),
            "should be reclassified to STANDARD"
        );
        assertTrue(
            uint8(p2.status) == uint8(MerchantPayments.PaymentStatus.CLASSIFIED),
            "status should be CLASSIFIED"
        );
    }

    function testClassifyPayment_RevertsForNonClassifier() public {
        _registerAndFundMerchant();
        bytes32 paymentId = _pay(HUNDRED_USDC);

        vm.prank(randomUser);
        vm.expectRevert("MerchantPayments: not classifier");
        mp.classifyPayment(paymentId, MerchantPayments.PaymentClassification.BLOCKED);
    }

    // =========================================================================
    // testClassifyPaymentSuspicious
    // =========================================================================

    function testClassifyPaymentSuspicious() public {
        _registerAndFundMerchant();

        // Amount above the suspicious threshold → auto-classified as SUSPICIOUS.
        uint256 amount = SUSPICIOUS_THRESHOLD + ONE_USDC;
        bytes32 paymentId = _pay(amount);

        MerchantPayments.Payment memory p = mp.getPayment(paymentId);
        assertTrue(
            uint8(p.classification) == uint8(MerchantPayments.PaymentClassification.SUSPICIOUS),
            "should be auto-classified as SUSPICIOUS"
        );

        // Classifier promotes it to BLOCKED.
        vm.expectEmit(true, false, false, true);
        emit MerchantPayments.PaymentClassified(
            paymentId,
            MerchantPayments.PaymentClassification.BLOCKED,
            merchant,
            amount
        );

        vm.prank(classifier);
        mp.classifyPayment(paymentId, MerchantPayments.PaymentClassification.BLOCKED);

        MerchantPayments.Payment memory p2 = mp.getPayment(paymentId);
        assertTrue(
            uint8(p2.classification) == uint8(MerchantPayments.PaymentClassification.BLOCKED),
            "should be BLOCKED"
        );
    }

    // =========================================================================
    // testRecordWebhookAttempt
    // =========================================================================

    function testRecordWebhookAttempt() public {
        _registerAndFundMerchant();
        bytes32 paymentId = _pay(HUNDRED_USDC);

        vm.expectEmit(true, false, false, true);
        emit MerchantPayments.WebhookAttempted(
            paymentId,
            1,
            MerchantPayments.WebhookStatus.DELIVERED,
            200
        );

        vm.prank(operator);
        mp.recordWebhookAttempt(
            paymentId,
            1,
            MerchantPayments.WebhookStatus.DELIVERED,
            200,
            45
        );

        MerchantPayments.WebhookAttempt[] memory attempts = mp.getWebhookAttempts(paymentId);
        assertEq(attempts.length, 1, "should have one attempt");
        assertEq(attempts[0].attemptNumber, 1,   "attempt number");
        assertEq(attempts[0].responseCode,  200, "response code");
        assertEq(attempts[0].latencyMs,     45,  "latency");

        MerchantPayments.Payment memory p = mp.getPayment(paymentId);
        assertTrue(
            uint8(p.status) == uint8(MerchantPayments.PaymentStatus.WEBHOOK_DELIVERED),
            "status should be WEBHOOK_DELIVERED"
        );
    }

    function testRecordWebhookAttempt_ExhaustedSetsWebhookFailed() public {
        _registerAndFundMerchant();
        bytes32 paymentId = _pay(HUNDRED_USDC);

        vm.prank(operator);
        mp.recordWebhookAttempt(
            paymentId,
            3,
            MerchantPayments.WebhookStatus.EXHAUSTED,
            503,
            1200
        );

        MerchantPayments.Payment memory p = mp.getPayment(paymentId);
        assertTrue(
            uint8(p.status) == uint8(MerchantPayments.PaymentStatus.WEBHOOK_FAILED),
            "status should be WEBHOOK_FAILED"
        );
    }

    // =========================================================================
    // testRequestAndApproveRefund
    // =========================================================================

    function testRequestAndApproveRefund() public {
        _registerAndFundMerchant();
        bytes32 paymentId = _pay(HUNDRED_USDC);

        // Payer requests a partial refund.
        vm.prank(payer);
        bytes32 refundId = mp.requestRefund(paymentId, 50 * ONE_USDC, "item not received");

        assertTrue(refundId != bytes32(0), "refund id non-zero");

        MerchantPayments.Refund memory r = mp.getRefund(refundId);
        assertEq(r.paymentId, paymentId,         "paymentId mismatch");
        assertEq(r.amount,    50 * ONE_USDC,     "refund amount");
        assertEq(r.payer,     payer,             "payer mismatch");
        assertTrue(
            uint8(r.status) == uint8(MerchantPayments.RefundStatus.REQUESTED),
            "should be REQUESTED"
        );

        // Operator approves.
        vm.expectEmit(true, false, false, false);
        emit MerchantPayments.RefundProcessed(refundId, MerchantPayments.PaymentStatus.REFUNDED);

        vm.prank(operator);
        mp.approveRefund(refundId);

        MerchantPayments.Refund memory r2 = mp.getRefund(refundId);
        assertTrue(
            uint8(r2.status) == uint8(MerchantPayments.RefundStatus.APPROVED),
            "should be APPROVED"
        );
        assertEq(r2.approvedBy, operator, "approvedBy mismatch");

        MerchantPayments.Payment memory p = mp.getPayment(paymentId);
        assertTrue(p.refunded, "payment should be marked refunded");
        assertTrue(
            uint8(p.status) == uint8(MerchantPayments.PaymentStatus.REFUNDED),
            "payment should be REFUNDED"
        );
    }

    function testRejectRefund() public {
        _registerAndFundMerchant();
        bytes32 paymentId = _pay(HUNDRED_USDC);

        vm.prank(payer);
        bytes32 refundId = mp.requestRefund(paymentId, HUNDRED_USDC, "changed mind");

        vm.prank(operator);
        mp.rejectRefund(refundId);

        MerchantPayments.Refund memory r = mp.getRefund(refundId);
        assertTrue(
            uint8(r.status) == uint8(MerchantPayments.RefundStatus.REJECTED),
            "should be REJECTED"
        );

        // Payment should NOT be flagged as refunded.
        MerchantPayments.Payment memory p = mp.getPayment(paymentId);
        assertFalse(p.refunded, "payment should not be refunded");
    }

    function testRequestRefund_RevertsForNonPayer() public {
        _registerAndFundMerchant();
        bytes32 paymentId = _pay(HUNDRED_USDC);

        vm.prank(randomUser);
        vm.expectRevert("MerchantPayments: not authorised to refund");
        mp.requestRefund(paymentId, HUNDRED_USDC, "unauthorised");
    }

    function testRequestRefund_RevertsForExcessAmount() public {
        _registerAndFundMerchant();
        bytes32 paymentId = _pay(HUNDRED_USDC);

        vm.prank(payer);
        vm.expectRevert("MerchantPayments: invalid refund amount");
        mp.requestRefund(paymentId, HUNDRED_USDC + 1, "too much");
    }

    // =========================================================================
    // testVelocityCheck
    // =========================================================================

    function testVelocityCheck() public {
        _registerAndFundMerchant();

        // Set a tight velocity window: max 2 payments per window.
        vm.prank(operator);
        mp.updateMerchantConfig(
            merchant,
            type(uint256).max, // no daily limit
            30,                 // 0.30 % fee
            3600,               // 1-hour window
            2                   // max 2 payments per window
        );

        // First payment — should succeed.
        _pay(ONE_USDC);

        // Advance block/time to avoid paymentId collision.
        vm.roll(block.number + 1); vm.warp(block.timestamp + 1);

        // Second payment — should succeed (count = 2 = limit, but not exceeded yet
        // because we increment after checking).
        _pay(ONE_USDC);

        // Third payment — velocity exceeded (count already == 2 >= maxPaymentsPerWindow).
        vm.prank(payer);
        vm.expectRevert("MerchantPayments: velocity limit exceeded");
        mp.receivePayment(
            merchant,
            address(usdc),
            ONE_USDC,
            bytes3("USA"),
            bytes3("USD"),
            ""
        );

        // isVelocityExceeded should also return true now.
        assertTrue(mp.isVelocityExceeded(payer, merchant), "velocity should be exceeded");
    }

    function testVelocityCheck_ResetsAfterWindow() public {
        _registerAndFundMerchant();

        vm.prank(operator);
        mp.updateMerchantConfig(
            merchant,
            type(uint256).max,
            30,
            60,  // 60-second window
            1    // max 1 per window
        );

        _pay(ONE_USDC); // consumes the window slot

        // Advance time past the window.
        vm.warp(block.timestamp + 61);

        // Window should reset — payment goes through.
        _pay(ONE_USDC);
    }

    // =========================================================================
    // testDailyLimitExceeded
    // =========================================================================

    function testDailyLimitExceeded() public {
        _registerAndFundMerchant();

        uint256 limit = 150 * ONE_USDC;

        vm.prank(operator);
        mp.updateMerchantConfig(
            merchant,
            limit, // daily limit = 150 USDC
            30,
            3600,
            100
        );

        // First payment — 100 USDC.
        _pay(HUNDRED_USDC);

        // Second payment — 100 USDC — would push daily volume to 200 USDC > 150.
        vm.prank(payer);
        vm.expectRevert("MerchantPayments: daily limit exceeded");
        mp.receivePayment(
            merchant,
            address(usdc),
            HUNDRED_USDC,
            bytes3("USA"),
            bytes3("USD"),
            ""
        );
    }

    function testDailyLimit_ResetsAfterDay() public {
        _registerAndFundMerchant();

        uint256 limit = 150 * ONE_USDC;

        vm.prank(operator);
        mp.updateMerchantConfig(merchant, limit, 30, 3600, 100);

        _pay(HUNDRED_USDC);

        // Warp past 1 day.
        vm.warp(block.timestamp + 1 days + 1);

        // Daily volume resets; payment should succeed.
        _pay(HUNDRED_USDC);
    }

    // =========================================================================
    // testPauseUnpause
    // =========================================================================

    function testPauseUnpause() public {
        _registerAndFundMerchant();

        // Pause.
        mp.pause();
        assertTrue(mp.paused(), "should be paused");

        vm.prank(payer);
        vm.expectRevert("MerchantPayments: contract is paused");
        mp.receivePayment(merchant, address(usdc), HUNDRED_USDC, bytes3("USA"), bytes3("USD"), "");

        // Unpause.
        mp.unpause();
        assertFalse(mp.paused(), "should be unpaused");

        bytes32 pid = _pay(HUNDRED_USDC);
        assertTrue(pid != bytes32(0), "payment should succeed after unpause");
    }

    function testPause_RevertsForNonOwner() public {
        vm.prank(randomUser);
        vm.expectRevert("MerchantPayments: not owner");
        mp.pause();
    }

    // =========================================================================
    // testGetMerchantStats
    // =========================================================================

    function testGetMerchantStats() public {
        _registerAndFundMerchant();

        // Make 3 payments using distinct amounts + block advances to avoid paymentId collision.
        _pay(HUNDRED_USDC);
        vm.roll(block.number + 1); vm.warp(block.timestamp + 2);
        _pay(HUNDRED_USDC + ONE_USDC);
        vm.roll(block.number + 1); vm.warp(block.timestamp + 2);
        _pay(HUNDRED_USDC + 2 * ONE_USDC);

        (
            uint256 totalVolume,
            uint256 totalPayments,
            uint256 totalRefunds,
            uint256 successRate,
            uint256 currentDailyVol
        ) = mp.getMerchantStats(merchant);

        uint256 expectedVol = HUNDRED_USDC + (HUNDRED_USDC + ONE_USDC) + (HUNDRED_USDC + 2 * ONE_USDC);
        assertEq(totalVolume,    expectedVol, "total volume");
        assertEq(totalPayments,  3,           "total payments");
        assertEq(totalRefunds,   0,           "total refunds");
        assertEq(successRate,    10_000,      "success rate 100 % in bps");
        assertEq(currentDailyVol, expectedVol, "daily volume");

        // Approve a refund and check success rate drops.
        bytes32[] memory payerPids = mp.getPayerPayments(payer);
        vm.prank(payer);
        bytes32 refundId = mp.requestRefund(payerPids[0], HUNDRED_USDC, "test");
        vm.prank(operator);
        mp.approveRefund(refundId);

        (, , uint256 refundsAfter, uint256 rateAfter, ) = mp.getMerchantStats(merchant);
        assertEq(refundsAfter, 1,       "one refund");
        // rate = (3 - 1) / 3 * 10000 = 6666 bps
        assertEq(rateAfter, 6666,       "success rate should be 66.66 %");
    }

    // =========================================================================
    // testRecordSync
    // =========================================================================

    function testRecordSync() public {
        _registerAndFundMerchant();
        bytes32 paymentId = _pay(HUNDRED_USDC);

        vm.expectEmit(true, false, false, true);
        emit MerchantPayments.SyncRecorded(paymentId, 250, true, true);

        vm.prank(operator);
        mp.recordSync(paymentId, 250, true, true);

        MerchantPayments.SyncRecord memory sr = mp.getSyncRecord(paymentId);
        assertEq(sr.paymentId,     paymentId, "paymentId");
        assertEq(sr.syncLatencyMs, 250,       "sync latency");
        assertTrue(sr.dbSynced,              "db synced");
        assertTrue(sr.webhookDelivered,      "webhook delivered");
        assertTrue(sr.dashboardUpdated,      "dashboard updated");

        MerchantPayments.Payment memory p = mp.getPayment(paymentId);
        assertTrue(
            uint8(p.status) == uint8(MerchantPayments.PaymentStatus.SYNCED),
            "status should be SYNCED"
        );
    }

    // =========================================================================
    // testGetMerchantPayments — pagination
    // =========================================================================

    function testGetMerchantPayments_Pagination() public {
        _registerAndFundMerchant();

        // Create 5 payments.
        for (uint256 i = 0; i < 5; ++i) {
            // Each payment needs a unique block to avoid paymentId collision.
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 1);
            _pay(ONE_USDC * (i + 1));
        }

        bytes32[] memory page1 = mp.getMerchantPayments(merchant, 0, 3);
        assertEq(page1.length, 3, "page1 size");

        bytes32[] memory page2 = mp.getMerchantPayments(merchant, 3, 3);
        assertEq(page2.length, 2, "page2 size");

        bytes32[] memory empty = mp.getMerchantPayments(merchant, 10, 5);
        assertEq(empty.length, 0, "out-of-bounds should be empty");
    }

    // =========================================================================
    // testUpdateMerchantTier
    // =========================================================================

    function testUpdateMerchantTier() public {
        _registerAndFundMerchant();

        vm.prank(operator);
        mp.updateMerchantTier(merchant, MerchantPayments.MerchantTier.ENTERPRISE);

        (, , MerchantPayments.MerchantTier tier, , , , , , , ) =
            mp.getMerchantConfig(merchant);
        assertTrue(
            uint8(tier) == uint8(MerchantPayments.MerchantTier.ENTERPRISE),
            "tier should be ENTERPRISE"
        );
    }

    // =========================================================================
    // testAddRemoveOperator
    // =========================================================================

    function testAddRemoveOperator() public {
        address newOp = makeAddr("newOp");

        mp.addOperator(newOp);
        assertTrue(mp.operatorRole(newOp), "should be operator");

        mp.removeOperator(newOp);
        assertFalse(mp.operatorRole(newOp), "should not be operator");
    }

    // =========================================================================
    // testConfirmPayment
    // =========================================================================

    function testConfirmPayment() public {
        _registerAndFundMerchant();
        bytes32 paymentId = _pay(HUNDRED_USDC);

        bytes32 fakeTxHash = keccak256("tx");

        vm.prank(operator);
        mp.confirmPayment(paymentId, fakeTxHash, 1000);

        MerchantPayments.Payment memory p = mp.getPayment(paymentId);
        assertTrue(
            uint8(p.status) == uint8(MerchantPayments.PaymentStatus.CONFIRMED),
            "should be CONFIRMED"
        );
        assertEq(p.txHash,     fakeTxHash, "txHash");
        assertEq(p.networkFee, 1000,       "networkFee");
    }

    // =========================================================================
    // testIsTokenAllowed
    // =========================================================================

    function testIsTokenAllowed() public {
        _registerAndFundMerchant();

        assertTrue(
            mp.isTokenAllowed(merchant, address(usdc)),
            "usdc should be allowed"
        );
        assertFalse(
            mp.isTokenAllowed(merchant, address(0)),
            "zero address should not be allowed"
        );

        // Revoke.
        vm.prank(operator);
        mp.setTokenAllowed(merchant, address(usdc), false);
        assertFalse(
            mp.isTokenAllowed(merchant, address(usdc)),
            "usdc should be disallowed after revocation"
        );
    }
}
