// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MerchantPayments
 * @notice Comprehensive on-chain merchant payment processing contract for OnchainPay.
 *         Tracks payments, classifications, refunds, webhooks, and merchant configuration.
 *
 * Architecture overview
 * ─────────────────────
 *  • Every inbound payment is stored as a Payment struct keyed by a deterministic bytes32 id.
 *  • Merchants are independently registered with configurable thresholds and daily limits.
 *  • Velocity windows prevent rapid-fire payment spam from a single payer/merchant pair.
 *  • Off-chain services call recordSync / recordWebhookAttempt to keep on-chain audit trails.
 *  • Refunds follow a request→approve/reject lifecycle; approved refunds emit events consumed
 *    by the dashboard.
 *  • Role-based access: owner > operator > classifier, plus a global pause switch.
 */
contract MerchantPayments {
    // =========================================================================
    // Enums
    // =========================================================================

    /// @notice Lifecycle state of a single payment.
    enum PaymentStatus {
        PENDING,            // 0  Payment recorded; awaiting confirmation.
        CONFIRMED,          // 1  Confirmed on-chain.
        CLASSIFIED,         // 2  Classifier has assigned a classification.
        SYNCED,             // 3  Synced to off-chain database.
        WEBHOOK_DELIVERED,  // 4  Webhook delivered successfully.
        WEBHOOK_FAILED,     // 5  Webhook exhausted all retry attempts.
        REFUNDED,           // 6  Fully or partially refunded.
        DISPUTED            // 7  Under merchant / payer dispute.
    }

    /// @notice Risk / value classification for a payment.
    enum PaymentClassification {
        UNCLASSIFIED,   // 0  Default — not yet classified.
        STANDARD,       // 1  Normal payment.
        HIGH_VALUE,     // 2  Amount exceeds merchant highValueThreshold.
        SUSPICIOUS,     // 3  Triggered velocity or heuristic rules.
        BLOCKED         // 4  Hard-blocked by classifier.
    }

    /// @notice Commercial tier of a registered merchant.
    enum MerchantTier {
        FREE,           // 0
        STARTER,        // 1
        GROWTH,         // 2
        ENTERPRISE      // 3
    }

    /// @notice State machine for a refund request.
    enum RefundStatus {
        REQUESTED,  // 0  Created by payer or merchant.
        APPROVED,   // 1  Approved by an operator.
        PROCESSED,  // 2  Funds have been returned off-chain / on-chain.
        REJECTED    // 3  Operator rejected the request.
    }

    /// @notice State of a single webhook delivery attempt.
    enum WebhookStatus {
        PENDING,    // 0
        DELIVERED,  // 1
        FAILED,     // 2
        RETRYING,   // 3
        EXHAUSTED   // 4  Max retries consumed.
    }

    // =========================================================================
    // Structs
    // =========================================================================

    /**
     * @notice Complete on-chain record for a single payment.
     * @dev    Fields are packed loosely to aid readability; the compiler will
     *         reorder for optimal slot usage in memory layouts automatically.
     */
    struct Payment {
        bytes32              paymentId;
        address              payer;
        address              merchant;
        uint256              amount;
        address              tokenAddress;
        uint256              timestamp;
        uint256              blockNumber;
        PaymentStatus        status;
        PaymentClassification classification;
        bytes32              txHash;
        string               metadata;
        uint8                webhookRetryCount;
        uint256              lastWebhookAttempt;
        uint256              syncedAt;
        bool                 refunded;
        uint256              refundAmount;
        bytes3               countryCode;
        bytes3               currencyCode;
        uint256              processorFee;
        uint256              networkFee;
    }

    /**
     * @notice Per-merchant configuration and aggregate statistics.
     * @dev    `allowedTokens` must live in a separate mapping (structs cannot
     *         contain nested mappings in Solidity); see `_merchantAllowedTokens`.
     */
    struct MerchantConfig {
        address     merchantAddress;
        string      name;
        MerchantTier tier;
        string      webhookUrl;
        bool        active;
        uint256     totalVolume;
        uint256     totalPayments;
        uint256     totalRefunds;
        /// @dev Expressed in basis points (bps), e.g. 9900 = 99 %.
        uint256     successRate;
        uint256     registeredAt;
        uint256     lastActivityAt;
        uint256     maxDailyLimit;
        uint256     currentDailyVolume;
        uint256     dailyResetAt;
        uint256     feeRateBps;
        uint256     suspiciousThreshold;
        uint256     highValueThreshold;
        uint256     velocityWindowSeconds;
        uint256     maxPaymentsPerWindow;
    }

    /// @notice A refund request record.
    struct Refund {
        bytes32      refundId;
        bytes32      paymentId;
        address      merchant;
        address      payer;
        uint256      amount;
        RefundStatus status;
        uint256      requestedAt;
        uint256      processedAt;
        string       reason;
        address      approvedBy;
    }

    /**
     * @notice Sliding-window velocity tracker keyed by keccak256(payer, merchant).
     */
    struct VelocityWindow {
        address payer;
        address merchant;
        uint256 windowStart;
        uint256 paymentCount;
        uint256 totalAmount;
    }

    /// @notice Single webhook delivery attempt record.
    struct WebhookAttempt {
        bytes32       paymentId;
        uint8         attemptNumber;
        uint256       attemptedAt;
        WebhookStatus status;
        uint16        responseCode;
        uint32        latencyMs;
    }

    /// @notice Off-chain sync audit record for a payment.
    struct SyncRecord {
        bytes32 paymentId;
        uint256 onchainAt;
        uint256 offchainSyncedAt;
        uint256 syncLatencyMs;
        bool    dbSynced;
        bool    webhookDelivered;
        bool    dashboardUpdated;
    }

    // =========================================================================
    // Events
    // =========================================================================

    /// @notice Emitted when a new payment is recorded.
    event PaymentReceived(
        bytes32 indexed paymentId,
        address indexed payer,
        address indexed merchant,
        uint256 amount,
        address token,
        uint256 timestamp
    );

    /// @notice Emitted when a payment classification is assigned or updated.
    event PaymentClassified(
        bytes32 indexed paymentId,
        PaymentClassification classification,
        address indexed merchant,
        uint256 amount
    );

    /// @notice Emitted on any payment status transition.
    event PaymentStatusUpdated(
        bytes32 indexed paymentId,
        PaymentStatus oldStatus,
        PaymentStatus newStatus
    );

    /// @notice Emitted when a refund is requested.
    event RefundRequested(
        bytes32 indexed refundId,
        bytes32 indexed paymentId,
        address indexed payer,
        uint256 amount
    );

    /// @notice Emitted when a refund is approved or rejected.
    event RefundProcessed(bytes32 indexed refundId, PaymentStatus finalStatus);

    /// @notice Emitted for each webhook delivery attempt.
    event WebhookAttempted(
        bytes32 indexed paymentId,
        uint8 attemptNumber,
        WebhookStatus status,
        uint16 responseCode
    );

    /// @notice Emitted when a new merchant is registered.
    event MerchantRegistered(address indexed merchant, string name, MerchantTier tier);

    /// @notice Emitted when merchant configuration is updated.
    event MerchantConfigUpdated(address indexed merchant);

    /// @notice Emitted when a transaction would exceed the merchant's daily limit.
    event DailyLimitExceeded(address indexed merchant, uint256 attempted, uint256 limit);

    /// @notice Emitted when a suspicious-activity heuristic is triggered.
    event SuspiciousActivityDetected(
        address indexed payer,
        address indexed merchant,
        uint256 amount,
        string reason
    );

    /// @notice Emitted when off-chain sync details are recorded.
    event SyncRecorded(
        bytes32 indexed paymentId,
        uint256 syncLatencyMs,
        bool dbSynced,
        bool webhookDelivered
    );

    // =========================================================================
    // State Variables
    // =========================================================================

    /// @notice Contract owner — can perform all privileged operations.
    address public owner;

    /// @notice Global circuit-breaker. When true, payment intake is blocked.
    bool public paused;

    /// @notice Primary payment storage keyed by paymentId.
    mapping(bytes32 => Payment) public payments;

    /// @notice Merchant configuration and statistics keyed by merchant address.
    mapping(address => MerchantConfig) public merchantConfigs;

    /// @notice Refund records keyed by refundId.
    mapping(bytes32 => Refund) public refunds;

    /// @notice Off-chain sync audit records keyed by paymentId.
    mapping(bytes32 => SyncRecord) public syncRecords;

    /**
     * @notice Velocity sliding windows keyed by keccak256(abi.encodePacked(payer, merchant)).
     */
    mapping(bytes32 => VelocityWindow) public velocityWindows;

    /// @notice Ordered list of webhook attempts per payment.
    mapping(bytes32 => WebhookAttempt[]) public webhookAttempts;

    /// @notice Ordered payment IDs per merchant (used for paginated listing).
    mapping(address => bytes32[]) public merchantPaymentIds;

    /// @notice All payment IDs ever generated by a given payer.
    mapping(address => bytes32[]) public payerPaymentIds;

    /// @notice Total volume (in token-smallest-units) processed across all merchants.
    uint256 public totalGlobalVolume;

    /// @notice Total number of payments processed across all merchants.
    uint256 public totalGlobalPayments;

    /**
     * @notice Accounts that can perform operator-level actions (approve/reject
     *         refunds, update merchant config, record syncs and webhook attempts).
     */
    mapping(address => bool) public operatorRole;

    /**
     * @notice Accounts that can classify payments.
     */
    mapping(address => bool) public classifierRole;

    /**
     * @notice Per-merchant token allowlists. Stored separately because Solidity
     *         does not permit mappings inside structs that are themselves in mappings.
     *         Usage: _merchantAllowedTokens[merchant][token] = true/false.
     */
    mapping(address => mapping(address => bool)) private _merchantAllowedTokens;

    // =========================================================================
    // Modifiers
    // =========================================================================

    /// @dev Restricts the function to the contract owner.
    modifier onlyOwner() {
        require(msg.sender == owner, "MerchantPayments: not owner");
        _;
    }

    /// @dev Restricts the function to accounts holding the operator role (or owner).
    modifier onlyOperator() {
        require(
            msg.sender == owner || operatorRole[msg.sender],
            "MerchantPayments: not operator"
        );
        _;
    }

    /// @dev Restricts the function to accounts holding the classifier role (or owner).
    modifier onlyClassifier() {
        require(
            msg.sender == owner || classifierRole[msg.sender],
            "MerchantPayments: not classifier"
        );
        _;
    }

    /// @dev Reverts when the contract is paused.
    modifier whenNotPaused() {
        require(!paused, "MerchantPayments: contract is paused");
        _;
    }

    /// @dev Reverts when the given address is not a registered, active merchant.
    modifier onlyRegisteredMerchant(address merchant) {
        require(
            merchantConfigs[merchant].merchantAddress == merchant,
            "MerchantPayments: merchant not registered"
        );
        require(merchantConfigs[merchant].active, "MerchantPayments: merchant not active");
        _;
    }

    // =========================================================================
    // Constructor
    // =========================================================================

    /**
     * @notice Deploy the contract. The deployer becomes the owner and is
     *         automatically granted both operator and classifier roles.
     */
    constructor() {
        owner              = msg.sender;
        operatorRole[msg.sender]   = true;
        classifierRole[msg.sender] = true;
    }

    // =========================================================================
    // Merchant Management
    // =========================================================================

    /**
     * @notice Register a new merchant.
     * @dev    Can only be called by the owner or an operator.
     *         Re-registering an existing address updates the configuration.
     * @param merchant              The merchant's EOA or contract address.
     * @param merchantName          Human-readable merchant name.
     * @param tier                  Commercial tier.
     * @param highValueThreshold    Amount (in token-smallest-units) above which a
     *                              payment is classified as HIGH_VALUE.
     * @param suspiciousThreshold   Amount above which a payment is flagged SUSPICIOUS.
     */
    function registerMerchant(
        address      merchant,
        string calldata merchantName,
        MerchantTier tier,
        uint256      highValueThreshold,
        uint256      suspiciousThreshold
    ) external onlyOperator {
        require(merchant != address(0), "MerchantPayments: zero address");
        require(bytes(merchantName).length > 0, "MerchantPayments: empty name");

        MerchantConfig storage cfg = merchantConfigs[merchant];

        // Preserve existing statistics if re-registering.
        bool isNew = (cfg.merchantAddress == address(0));

        cfg.merchantAddress      = merchant;
        cfg.name                 = merchantName;
        cfg.tier                 = tier;
        cfg.active               = true;
        cfg.highValueThreshold   = highValueThreshold;
        cfg.suspiciousThreshold  = suspiciousThreshold;

        // Sensible defaults if this is a fresh registration.
        if (isNew) {
            cfg.registeredAt            = block.timestamp;
            cfg.successRate             = 10_000; // 100 % bps initially
            cfg.maxDailyLimit           = type(uint256).max;
            cfg.velocityWindowSeconds   = 3600;   // 1 hour
            cfg.maxPaymentsPerWindow    = 100;
            cfg.feeRateBps              = 30;     // 0.30 %
            cfg.dailyResetAt            = block.timestamp + 1 days;
        }

        emit MerchantRegistered(merchant, merchantName, tier);
    }

    /**
     * @notice Update runtime configuration parameters for a registered merchant.
     * @param merchant                  Merchant address.
     * @param maxDailyLimit             Maximum cumulative volume in a calendar day.
     * @param feeRateBps                Fee rate in basis points (e.g. 30 = 0.30 %).
     * @param velocityWindowSeconds     Length (seconds) of the rolling velocity window.
     * @param maxPaymentsPerWindow      Maximum payments allowed within the velocity window.
     */
    function updateMerchantConfig(
        address merchant,
        uint256 maxDailyLimit,
        uint256 feeRateBps,
        uint256 velocityWindowSeconds,
        uint256 maxPaymentsPerWindow
    ) external onlyOperator onlyRegisteredMerchant(merchant) {
        require(feeRateBps <= 10_000, "MerchantPayments: fee rate exceeds 100 %");
        require(velocityWindowSeconds > 0, "MerchantPayments: zero velocity window");
        require(maxPaymentsPerWindow > 0, "MerchantPayments: zero max payments");

        MerchantConfig storage cfg = merchantConfigs[merchant];
        cfg.maxDailyLimit           = maxDailyLimit;
        cfg.feeRateBps              = feeRateBps;
        cfg.velocityWindowSeconds   = velocityWindowSeconds;
        cfg.maxPaymentsPerWindow    = maxPaymentsPerWindow;

        emit MerchantConfigUpdated(merchant);
    }

    /**
     * @notice Set or revoke a token on a merchant's allowlist.
     * @param merchant  Merchant address.
     * @param token     ERC20 token address (address(0) represents native ETH).
     * @param allowed   True to allow, false to disallow.
     */
    function setTokenAllowed(
        address merchant,
        address token,
        bool    allowed
    ) external onlyOperator onlyRegisteredMerchant(merchant) {
        _merchantAllowedTokens[merchant][token] = allowed;
        emit MerchantConfigUpdated(merchant);
    }

    /**
     * @notice Upgrade or downgrade the commercial tier for a merchant.
     * @param merchant  Merchant address.
     * @param newTier   New MerchantTier value.
     */
    function updateMerchantTier(
        address      merchant,
        MerchantTier newTier
    ) external onlyOperator onlyRegisteredMerchant(merchant) {
        merchantConfigs[merchant].tier = newTier;
        emit MerchantConfigUpdated(merchant);
    }

    // =========================================================================
    // Payment Processing
    // =========================================================================

    /**
     * @notice Record a new inbound payment.
     * @dev    This function does NOT transfer tokens — token custody remains with
     *         the caller / bridge. The contract records the intent and metadata
     *         so that off-chain systems and on-chain audits stay consistent.
     * @param merchant      Registered merchant address.
     * @param token         ERC20 token address (use address(0) for native ETH).
     * @param amount        Payment amount in token-smallest-units.
     * @param countryCode   ISO 3166-1 alpha-3 country code (e.g. "USA").
     * @param currencyCode  ISO 4217 currency code (e.g. "USD").
     * @param metadata      Arbitrary JSON or string payload from the frontend.
     * @return paymentId    Deterministic bytes32 identifier for this payment.
     */
    function receivePayment(
        address         merchant,
        address         token,
        uint256         amount,
        bytes3          countryCode,
        bytes3          currencyCode,
        string calldata metadata
    )
        external
        whenNotPaused
        onlyRegisteredMerchant(merchant)
        returns (bytes32 paymentId)
    {
        require(amount > 0, "MerchantPayments: zero amount");
        require(
            _merchantAllowedTokens[merchant][token],
            "MerchantPayments: token not allowed for merchant"
        );

        // --- Daily limit check -----------------------------------------------
        _resetDailyIfNeeded(merchant);
        bool limitExceeded = _checkDailyLimit(merchant, amount);
        if (limitExceeded) {
            emit DailyLimitExceeded(
                merchant,
                merchantConfigs[merchant].currentDailyVolume + amount,
                merchantConfigs[merchant].maxDailyLimit
            );
            revert("MerchantPayments: daily limit exceeded");
        }

        // --- Velocity check ---------------------------------------------------
        bool velocityExceeded = _checkAndUpdateVelocity(msg.sender, merchant);
        if (velocityExceeded) {
            emit SuspiciousActivityDetected(
                msg.sender,
                merchant,
                amount,
                "velocity limit exceeded"
            );
            revert("MerchantPayments: velocity limit exceeded");
        }

        // --- Generate unique payment id --------------------------------------
        paymentId = _generatePaymentId(msg.sender, merchant, amount, block.timestamp);
        require(
            payments[paymentId].paymentId == bytes32(0),
            "MerchantPayments: payment id collision"
        );

        // --- Fee calculation -------------------------------------------------
        MerchantConfig storage cfg = merchantConfigs[merchant];
        uint256 processorFee = (amount * cfg.feeRateBps) / 10_000;

        // --- Store payment ---------------------------------------------------
        payments[paymentId] = Payment({
            paymentId:          paymentId,
            payer:              msg.sender,
            merchant:           merchant,
            amount:             amount,
            tokenAddress:       token,
            timestamp:          block.timestamp,
            blockNumber:        block.number,
            status:             PaymentStatus.PENDING,
            classification:     PaymentClassification.UNCLASSIFIED,
            txHash:             bytes32(0),           // filled by off-chain relay
            metadata:           metadata,
            webhookRetryCount:  0,
            lastWebhookAttempt: 0,
            syncedAt:           0,
            refunded:           false,
            refundAmount:       0,
            countryCode:        countryCode,
            currencyCode:       currencyCode,
            processorFee:       processorFee,
            networkFee:         0                     // filled by off-chain relay
        });

        // --- Index -----------------------------------------------------------
        merchantPaymentIds[merchant].push(paymentId);
        payerPaymentIds[msg.sender].push(paymentId);

        // --- Update merchant stats -------------------------------------------
        cfg.totalVolume        += amount;
        cfg.totalPayments      += 1;
        cfg.currentDailyVolume += amount;
        cfg.lastActivityAt      = block.timestamp;

        // --- Global stats ----------------------------------------------------
        totalGlobalVolume   += amount;
        totalGlobalPayments += 1;

        // --- Auto-classify based on thresholds --------------------------------
        if (cfg.suspiciousThreshold > 0 && amount >= cfg.suspiciousThreshold) {
            payments[paymentId].classification = PaymentClassification.SUSPICIOUS;
            emit SuspiciousActivityDetected(
                msg.sender,
                merchant,
                amount,
                "amount exceeds suspicious threshold"
            );
        } else if (cfg.highValueThreshold > 0 && amount >= cfg.highValueThreshold) {
            payments[paymentId].classification = PaymentClassification.HIGH_VALUE;
        }

        emit PaymentReceived(paymentId, msg.sender, merchant, amount, token, block.timestamp);
        return paymentId;
    }

    /**
     * @notice Transition a payment to CONFIRMED status.
     * @dev    Called by an operator once the underlying blockchain transaction
     *         has received sufficient confirmations.
     * @param paymentId  The payment to confirm.
     * @param txHash     The on-chain transaction hash for audit purposes.
     * @param networkFee Gas / network fee paid, in token-smallest-units.
     */
    function confirmPayment(
        bytes32 paymentId,
        bytes32 txHash,
        uint256 networkFee
    ) external onlyOperator {
        Payment storage p = payments[paymentId];
        require(p.paymentId == paymentId, "MerchantPayments: payment not found");
        require(p.status == PaymentStatus.PENDING, "MerchantPayments: not pending");

        PaymentStatus old = p.status;
        p.status    = PaymentStatus.CONFIRMED;
        p.txHash    = txHash;
        p.networkFee = networkFee;

        emit PaymentStatusUpdated(paymentId, old, PaymentStatus.CONFIRMED);
    }

    // =========================================================================
    // Classification
    // =========================================================================

    /**
     * @notice Assign or override the risk classification for a payment.
     * @param paymentId       Payment to classify.
     * @param classification  The new PaymentClassification value.
     */
    function classifyPayment(
        bytes32               paymentId,
        PaymentClassification classification
    ) external onlyClassifier {
        Payment storage p = payments[paymentId];
        require(p.paymentId == paymentId, "MerchantPayments: payment not found");
        require(
            p.status != PaymentStatus.REFUNDED,
            "MerchantPayments: cannot classify refunded payment"
        );

        p.classification = classification;

        PaymentStatus old = p.status;
        if (p.status == PaymentStatus.CONFIRMED || p.status == PaymentStatus.PENDING) {
            p.status = PaymentStatus.CLASSIFIED;
            emit PaymentStatusUpdated(paymentId, old, PaymentStatus.CLASSIFIED);
        }

        emit PaymentClassified(paymentId, classification, p.merchant, p.amount);

        if (classification == PaymentClassification.SUSPICIOUS) {
            emit SuspiciousActivityDetected(
                p.payer,
                p.merchant,
                p.amount,
                "classifier flagged suspicious"
            );
        }
    }

    // =========================================================================
    // Webhook Tracking
    // =========================================================================

    /**
     * @notice Record the outcome of a single webhook delivery attempt.
     * @param paymentId     The payment the webhook targets.
     * @param attemptNumber Sequential attempt counter (1-indexed).
     * @param status        Outcome of this attempt.
     * @param responseCode  HTTP response code returned by the merchant endpoint.
     * @param latencyMs     Round-trip latency in milliseconds.
     */
    function recordWebhookAttempt(
        bytes32       paymentId,
        uint8         attemptNumber,
        WebhookStatus status,
        uint16        responseCode,
        uint32        latencyMs
    ) external onlyOperator {
        Payment storage p = payments[paymentId];
        require(p.paymentId == paymentId, "MerchantPayments: payment not found");

        webhookAttempts[paymentId].push(WebhookAttempt({
            paymentId:     paymentId,
            attemptNumber: attemptNumber,
            attemptedAt:   block.timestamp,
            status:        status,
            responseCode:  responseCode,
            latencyMs:     latencyMs
        }));

        p.webhookRetryCount    = attemptNumber;
        p.lastWebhookAttempt   = block.timestamp;

        // Update payment status based on webhook outcome.
        PaymentStatus old = p.status;
        if (status == WebhookStatus.DELIVERED) {
            p.status = PaymentStatus.WEBHOOK_DELIVERED;
        } else if (status == WebhookStatus.EXHAUSTED) {
            p.status = PaymentStatus.WEBHOOK_FAILED;
        }

        if (p.status != old) {
            emit PaymentStatusUpdated(paymentId, old, p.status);
        }

        emit WebhookAttempted(paymentId, attemptNumber, status, responseCode);
    }

    // =========================================================================
    // Sync Recording
    // =========================================================================

    /**
     * @notice Record that an off-chain system has synced this payment.
     * @param paymentId         The payment that was synced.
     * @param syncLatencyMs     Milliseconds between on-chain timestamp and sync.
     * @param dbSynced          True if the database row has been written.
     * @param webhookDelivered  True if the webhook has been delivered.
     */
    function recordSync(
        bytes32 paymentId,
        uint256 syncLatencyMs,
        bool    dbSynced,
        bool    webhookDelivered
    ) external onlyOperator {
        Payment storage p = payments[paymentId];
        require(p.paymentId == paymentId, "MerchantPayments: payment not found");

        SyncRecord storage sr = syncRecords[paymentId];
        sr.paymentId          = paymentId;
        sr.onchainAt          = p.timestamp;
        sr.offchainSyncedAt   = block.timestamp;
        sr.syncLatencyMs      = syncLatencyMs;
        sr.dbSynced           = dbSynced;
        sr.webhookDelivered   = webhookDelivered;
        sr.dashboardUpdated   = true;

        if (p.syncedAt == 0) {
            p.syncedAt = block.timestamp;
        }

        PaymentStatus old = p.status;
        if (
            p.status == PaymentStatus.CLASSIFIED ||
            p.status == PaymentStatus.CONFIRMED  ||
            p.status == PaymentStatus.PENDING
        ) {
            p.status = PaymentStatus.SYNCED;
            emit PaymentStatusUpdated(paymentId, old, PaymentStatus.SYNCED);
        }

        emit SyncRecorded(paymentId, syncLatencyMs, dbSynced, webhookDelivered);
    }

    // =========================================================================
    // Refunds
    // =========================================================================

    /**
     * @notice Open a refund request for an existing payment.
     * @dev    Can be called by the payer of the payment or by an operator.
     * @param paymentId  Payment to refund.
     * @param amount     Amount to refund (must be <= payment.amount).
     * @param reason     Human-readable reason for the refund request.
     * @return refundId  Identifier for the newly created Refund record.
     */
    function requestRefund(
        bytes32         paymentId,
        uint256         amount,
        string calldata reason
    ) external whenNotPaused returns (bytes32 refundId) {
        Payment storage p = payments[paymentId];
        require(p.paymentId == paymentId, "MerchantPayments: payment not found");
        require(
            msg.sender == p.payer || operatorRole[msg.sender] || msg.sender == owner,
            "MerchantPayments: not authorised to refund"
        );
        require(amount > 0 && amount <= p.amount, "MerchantPayments: invalid refund amount");
        require(!p.refunded, "MerchantPayments: already refunded");
        require(
            p.status != PaymentStatus.DISPUTED,
            "MerchantPayments: payment under dispute"
        );

        refundId = _generateRefundId(paymentId, block.timestamp);
        require(
            refunds[refundId].refundId == bytes32(0),
            "MerchantPayments: refund id collision"
        );

        refunds[refundId] = Refund({
            refundId:    refundId,
            paymentId:   paymentId,
            merchant:    p.merchant,
            payer:       p.payer,
            amount:      amount,
            status:      RefundStatus.REQUESTED,
            requestedAt: block.timestamp,
            processedAt: 0,
            reason:      reason,
            approvedBy:  address(0)
        });

        emit RefundRequested(refundId, paymentId, p.payer, amount);
        return refundId;
    }

    /**
     * @notice Approve a pending refund request.
     * @dev    Marks the payment as REFUNDED and updates merchant statistics.
     * @param refundId  The refund to approve.
     */
    function approveRefund(bytes32 refundId) external onlyOperator {
        Refund storage r = refunds[refundId];
        require(r.refundId == refundId, "MerchantPayments: refund not found");
        require(r.status == RefundStatus.REQUESTED, "MerchantPayments: refund not pending");

        r.status      = RefundStatus.APPROVED;
        r.approvedBy  = msg.sender;
        r.processedAt = block.timestamp;

        // Update payment record.
        Payment storage p = payments[r.paymentId];
        p.refunded     = true;
        p.refundAmount = r.amount;

        PaymentStatus old = p.status;
        p.status = PaymentStatus.REFUNDED;

        // Update merchant stats.
        MerchantConfig storage cfg = merchantConfigs[p.merchant];
        cfg.totalRefunds += 1;
        // Recompute success rate in bps: (confirmed - refunded) / confirmed * 10000.
        if (cfg.totalPayments > 0) {
            uint256 successful = cfg.totalPayments > cfg.totalRefunds
                ? cfg.totalPayments - cfg.totalRefunds
                : 0;
            cfg.successRate = (successful * 10_000) / cfg.totalPayments;
        }

        emit PaymentStatusUpdated(r.paymentId, old, PaymentStatus.REFUNDED);
        emit RefundProcessed(refundId, PaymentStatus.REFUNDED);
    }

    /**
     * @notice Reject a pending refund request.
     * @param refundId  The refund to reject.
     */
    function rejectRefund(bytes32 refundId) external onlyOperator {
        Refund storage r = refunds[refundId];
        require(r.refundId == refundId, "MerchantPayments: refund not found");
        require(r.status == RefundStatus.REQUESTED, "MerchantPayments: refund not pending");

        r.status      = RefundStatus.REJECTED;
        r.approvedBy  = msg.sender;
        r.processedAt = block.timestamp;

        // Payment status remains unchanged.
        emit RefundProcessed(refundId, payments[r.paymentId].status);
    }

    // =========================================================================
    // Access Control
    // =========================================================================

    /// @notice Pause inbound payment processing.
    function pause() external onlyOwner {
        paused = true;
    }

    /// @notice Resume inbound payment processing.
    function unpause() external onlyOwner {
        paused = false;
    }

    /**
     * @notice Grant the operator role to `op`.
     * @param op  Address to promote.
     */
    function addOperator(address op) external onlyOwner {
        require(op != address(0), "MerchantPayments: zero address");
        operatorRole[op] = true;
    }

    /**
     * @notice Revoke the operator role from `op`.
     * @param op  Address to demote.
     */
    function removeOperator(address op) external onlyOwner {
        operatorRole[op] = false;
    }

    /**
     * @notice Grant the classifier role to `clf`.
     * @param clf  Address to promote.
     */
    function addClassifier(address clf) external onlyOwner {
        require(clf != address(0), "MerchantPayments: zero address");
        classifierRole[clf] = true;
    }

    /**
     * @notice Revoke the classifier role from `clf`.
     * @param clf  Address to demote.
     */
    function removeClassifier(address clf) external onlyOwner {
        classifierRole[clf] = false;
    }

    // =========================================================================
    // View Functions
    // =========================================================================

    /**
     * @notice Retrieve the full Payment struct for `paymentId`.
     * @param paymentId  Payment identifier.
     * @return           The Payment struct (memory copy).
     */
    function getPayment(bytes32 paymentId) external view returns (Payment memory) {
        require(
            payments[paymentId].paymentId == paymentId,
            "MerchantPayments: payment not found"
        );
        return payments[paymentId];
    }

    /**
     * @notice Paginated list of payment IDs for a merchant.
     * @param merchant  Merchant address.
     * @param offset    Start index (0-indexed).
     * @param limit     Maximum number of IDs to return.
     * @return          Slice of the merchant's payment ID array.
     */
    function getMerchantPayments(
        address merchant,
        uint256 offset,
        uint256 limit
    ) external view returns (bytes32[] memory) {
        bytes32[] storage ids = merchantPaymentIds[merchant];
        uint256 total = ids.length;

        if (offset >= total || limit == 0) {
            return new bytes32[](0);
        }

        uint256 end  = offset + limit;
        if (end > total) end = total;
        uint256 size = end - offset;

        bytes32[] memory result = new bytes32[](size);
        for (uint256 i = 0; i < size; ++i) {
            result[i] = ids[offset + i];
        }
        return result;
    }

    /**
     * @notice Return all payment IDs associated with a payer.
     * @param payer  Payer address.
     * @return       Array of payment IDs.
     */
    function getPayerPayments(address payer) external view returns (bytes32[] memory) {
        return payerPaymentIds[payer];
    }

    /**
     * @notice Aggregate statistics for a registered merchant.
     * @param merchant          Merchant address.
     * @return totalVolume      Cumulative payment volume.
     * @return totalPayments    Total number of payments received.
     * @return totalRefunds     Total number of refunds processed.
     * @return successRate      Success rate in basis points.
     * @return currentDailyVol  Volume processed today (resets at midnight UTC-ish).
     */
    function getMerchantStats(address merchant)
        external
        view
        returns (
            uint256 totalVolume,
            uint256 totalPayments,
            uint256 totalRefunds,
            uint256 successRate,
            uint256 currentDailyVol
        )
    {
        MerchantConfig storage cfg = merchantConfigs[merchant];
        return (
            cfg.totalVolume,
            cfg.totalPayments,
            cfg.totalRefunds,
            cfg.successRate,
            cfg.currentDailyVolume
        );
    }

    /**
     * @notice Return all webhook attempt records for a payment.
     * @param paymentId  Payment identifier.
     * @return           Array of WebhookAttempt structs.
     */
    function getWebhookAttempts(bytes32 paymentId)
        external
        view
        returns (WebhookAttempt[] memory)
    {
        return webhookAttempts[paymentId];
    }

    /**
     * @notice Retrieve the sync record for a payment.
     * @param paymentId  Payment identifier.
     * @return           The SyncRecord struct.
     */
    function getSyncRecord(bytes32 paymentId) external view returns (SyncRecord memory) {
        return syncRecords[paymentId];
    }

    /**
     * @notice Retrieve the full Refund struct for `refundId`.
     * @param refundId  Refund identifier.
     * @return          The Refund struct.
     */
    function getRefund(bytes32 refundId) external view returns (Refund memory) {
        require(
            refunds[refundId].refundId == refundId,
            "MerchantPayments: refund not found"
        );
        return refunds[refundId];
    }

    /**
     * @notice Check whether the payer/merchant velocity window is currently exceeded.
     * @param payer     Payer address.
     * @param merchant  Merchant address.
     * @return exceeded True if the payer has exceeded the allowed payment count
     *                  within the merchant's velocity window.
     */
    function isVelocityExceeded(address payer, address merchant)
        external
        view
        returns (bool exceeded)
    {
        bytes32 key = keccak256(abi.encodePacked(payer, merchant));
        VelocityWindow storage vw = velocityWindows[key];
        MerchantConfig storage cfg = merchantConfigs[merchant];

        if (vw.windowStart == 0) return false;

        bool windowActive = (block.timestamp - vw.windowStart) < cfg.velocityWindowSeconds;
        if (!windowActive) return false;

        return vw.paymentCount >= cfg.maxPaymentsPerWindow;
    }

    /**
     * @notice Protocol-wide aggregate statistics.
     * @return gTotalVolume    Sum of all payment amounts ever recorded.
     * @return gTotalPayments  Total count of payments ever recorded.
     */
    function getGlobalStats()
        external
        view
        returns (uint256 gTotalVolume, uint256 gTotalPayments)
    {
        return (totalGlobalVolume, totalGlobalPayments);
    }

    /**
     * @notice Return the configuration for a registered merchant.
     * @param merchant              Merchant address.
     * @return merchantAddress      Stored address (sanity check).
     * @return merchantName         Registered name.
     * @return tier                 Commercial tier.
     * @return active               Whether the merchant is active.
     * @return maxDailyLimit        Daily volume cap.
     * @return feeRateBps           Processor fee in bps.
     * @return velocityWindowSecs   Length of the velocity window in seconds.
     * @return maxPaymentsPerWin    Max payments allowed per velocity window.
     * @return highValueThreshold   Amount above which payments are HIGH_VALUE.
     * @return suspiciousThreshold  Amount above which payments are SUSPICIOUS.
     */
    function getMerchantConfig(address merchant)
        external
        view
        returns (
            address      merchantAddress,
            string memory merchantName,
            MerchantTier  tier,
            bool          active,
            uint256       maxDailyLimit,
            uint256       feeRateBps,
            uint256       velocityWindowSecs,
            uint256       maxPaymentsPerWin,
            uint256       highValueThreshold,
            uint256       suspiciousThreshold
        )
    {
        MerchantConfig storage cfg = merchantConfigs[merchant];
        return (
            cfg.merchantAddress,
            cfg.name,
            cfg.tier,
            cfg.active,
            cfg.maxDailyLimit,
            cfg.feeRateBps,
            cfg.velocityWindowSeconds,
            cfg.maxPaymentsPerWindow,
            cfg.highValueThreshold,
            cfg.suspiciousThreshold
        );
    }

    /**
     * @notice Return whether a token is on a merchant's allowlist.
     * @param merchant  Merchant address.
     * @param token     Token address (address(0) = native ETH).
     * @return          True if the token is allowed.
     */
    function isTokenAllowed(address merchant, address token)
        external
        view
        returns (bool)
    {
        return _merchantAllowedTokens[merchant][token];
    }

    // =========================================================================
    // Internal Helpers
    // =========================================================================

    /**
     * @notice Derive a deterministic payment ID from contextual data.
     * @param payer      Payer address.
     * @param merchant   Merchant address.
     * @param amount     Payment amount.
     * @param timestamp  Block timestamp at submission.
     * @return           keccak256 hash used as the payment ID.
     */
    function _generatePaymentId(
        address payer,
        address merchant,
        uint256 amount,
        uint256 timestamp
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(payer, merchant, amount, timestamp, block.number, block.prevrandao)
        );
    }

    /**
     * @notice Derive a deterministic refund ID.
     * @param paymentId  The payment being refunded.
     * @param timestamp  Block timestamp at refund request.
     * @return           keccak256 hash used as the refund ID.
     */
    function _generateRefundId(bytes32 paymentId, uint256 timestamp)
        internal
        view
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(paymentId, timestamp, block.number));
    }

    /**
     * @notice Evaluate and update the payer/merchant velocity window.
     * @dev    Resets the window if it has expired, then increments the counter.
     *         Returns true only if the window limit was already reached BEFORE
     *         this call (i.e., the payment should be blocked).
     * @param payer     Payer address.
     * @param merchant  Merchant address.
     * @return exceeded True if the payment would exceed the velocity limit.
     */
    function _checkAndUpdateVelocity(address payer, address merchant)
        internal
        returns (bool exceeded)
    {
        bytes32 key = keccak256(abi.encodePacked(payer, merchant));
        VelocityWindow storage vw = velocityWindows[key];
        MerchantConfig storage cfg = merchantConfigs[merchant];

        // Initialise or reset an expired window.
        bool windowExpired = (block.timestamp - vw.windowStart) >= cfg.velocityWindowSeconds;
        if (vw.windowStart == 0 || windowExpired) {
            vw.payer        = payer;
            vw.merchant     = merchant;
            vw.windowStart  = block.timestamp;
            vw.paymentCount = 0;
            vw.totalAmount  = 0;
        }

        // Check limit before incrementing.
        if (vw.paymentCount >= cfg.maxPaymentsPerWindow) {
            return true;
        }

        // Increment window counters.
        vw.paymentCount += 1;
        return false;
    }

    /**
     * @notice Check whether adding `amount` to today's volume would breach the
     *         merchant's daily limit.
     * @param merchant  Merchant address.
     * @param amount    Amount to add.
     * @return exceeded True if the limit would be breached.
     */
    function _checkDailyLimit(address merchant, uint256 amount)
        internal
        view
        returns (bool exceeded)
    {
        MerchantConfig storage cfg = merchantConfigs[merchant];
        if (cfg.maxDailyLimit == type(uint256).max) return false;
        return (cfg.currentDailyVolume + amount) > cfg.maxDailyLimit;
    }

    /**
     * @notice Reset the merchant's daily volume counter when a new calendar day
     *         has started relative to `dailyResetAt`.
     * @param merchant  Merchant address.
     */
    function _resetDailyIfNeeded(address merchant) internal {
        MerchantConfig storage cfg = merchantConfigs[merchant];
        if (block.timestamp >= cfg.dailyResetAt) {
            cfg.currentDailyVolume = 0;
            // Advance the reset timestamp by however many 24-hour periods have passed.
            uint256 elapsed = block.timestamp - cfg.dailyResetAt;
            uint256 periods = elapsed / 1 days + 1;
            cfg.dailyResetAt += periods * 1 days;
        }
    }
}
