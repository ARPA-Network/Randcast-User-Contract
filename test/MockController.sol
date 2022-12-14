// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import "forge-std/Test.sol";
import "../src/interfaces/IController.sol";
import "../src/BasicRandcastConsumerBase.sol";
import "../src/RequestIdBase.sol";
import "../src/utils/RandomnessHandler.sol";
import "../src/interfaces/IAggregatorV3.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockController is
    IController,
    RequestIdBase,
    RandomnessHandler,
    Ownable,
    Test
{
    using SafeERC20 for IERC20;
    using Address for address;

    IERC20 public immutable ARPA;
    AggregatorV3Interface public immutable ARPA_ETH_FEED;
    // We need to maintain a list of consuming addresses.
    // This bound ensures we are able to loop over them as needed.
    // Should a user require more consumers, they can use multiple subscriptions.
    uint16 public constant MAX_CONSUMERS = 100;
    // TODO Set this maximum to 200 to give us a 56 block window to fulfill
    // the request before requiring the block hash feeder.
    uint16 public constant MAX_REQUEST_CONFIRMATIONS = 200;
    // 5k is plenty for an EXTCODESIZE call (2600) + warm CALL (100)
    // and some arithmetic operations.
    uint256 private constant GAS_FOR_CALL_EXACT_CHECK = 5_000;

    struct Config {
        uint16 minimumRequestConfirmations;
        uint32 maxGasLimit;
        // Reentrancy protection.
        bool reentrancyLock;
        // stalenessSeconds is how long before we consider the feed price to be stale
        // and fallback to fallbackWeiPerUnitArpa.
        uint32 stalenessSeconds;
        // Gas to cover group payment after we calculate the payment.
        // We make it configurable in case those operations are repriced.
        uint32 gasAfterPaymentCalculation;
        // Gas except callback during fulfillment of randomness. Only used for estimating inflight cost.
        uint32 gasExceptCallback;
    }
    int256 private s_fallbackWeiPerUnitArpa;
    Config private s_config;
    FeeConfig private s_feeConfig;
    struct FeeConfig {
        // Flat fee charged per fulfillment in millionths of arpa
        // So fee range is [0, 2^32/10^6].
        uint32 fulfillmentFlatFeeArpaPPMTier1;
        uint32 fulfillmentFlatFeeArpaPPMTier2;
        uint32 fulfillmentFlatFeeArpaPPMTier3;
        uint32 fulfillmentFlatFeeArpaPPMTier4;
        uint32 fulfillmentFlatFeeArpaPPMTier5;
        uint24 reqsForTier2;
        uint24 reqsForTier3;
        uint24 reqsForTier4;
        uint24 reqsForTier5;
    }
    event ConfigSet(
        uint16 minimumRequestConfirmations,
        uint32 maxGasLimit,
        uint32 stalenessSeconds,
        uint32 gasAfterPaymentCalculation,
        uint32 gasExceptCallback,
        int256 fallbackWeiPerUnitArpa,
        FeeConfig feeConfig
    );

    // TODO only record the hash of the callback params to save storage gas
    struct Callback {
        address callbackContract;
        RequestType requestType;
        bytes params;
        uint64 subId;
        uint256 seed;
        uint256 blockNum;
        uint16 requestConfirmations;
        uint256 callbackGasLimit;
        uint256 callbackMaxGasPrice;
    }

    mapping(bytes32 => Callback) public s_callbacks;

    struct Consumer {
        mapping(uint64 => uint64) nonces; /* subId */ /* nonce */
        uint64 lastSubscription;
    }

    struct Subscription {
        address owner; // Owner can fund/withdraw/cancel the sub.
        address requestedOwner; // For safely transferring sub ownership.
        address[] consumers;
        uint96 balance; // Arpa balance used for all consumer requests.
        uint96 inflightCost; // Arpa upper cost for pending requests.
        mapping(bytes32 => uint96) inflightPayments;
        uint64 reqCount; // For fee tiers
    }
    // Note a nonce of 0 indicates an the consumer is not assigned to that subscription.
    mapping(address => Consumer) /* consumerAddress */ /* consumer */
        private s_consumers;
    mapping(uint64 => Subscription) /* subId */ /* subscription */
        private s_subscriptions;
    uint64 private s_currentSubId;
    mapping(uint256 => uint96) /* group */ /* ARPA balance */
        private s_withdrawableTokens;

    event SubscriptionCreated(uint64 indexed subId, address owner);
    event SubscriptionFunded(
        uint64 indexed subId,
        uint256 oldBalance,
        uint256 newBalance
    );
    event SubscriptionConsumerAdded(uint64 indexed subId, address consumer);

    error Reentrant();
    error InvalidRequestConfirmations(uint16 have, uint16 min, uint16 max);
    error TooManyConsumers();
    error InsufficientBalanceWhenRequest();
    error InsufficientBalanceWhenFulfill();
    error InvalidConsumer(uint64 subId, address consumer);
    error InvalidSubscription();
    error MustBeSubOwner(address owner);
    error PaymentTooLarge();
    error InvalidArpaWeiPrice(int256 arpaWei);

    constructor(address arpa, address arpaEthFeed) {
        ARPA = IERC20(arpa);
        ARPA_ETH_FEED = AggregatorV3Interface(arpaEthFeed);
    }

    function createSubscription() external nonReentrant returns (uint64) {
        s_currentSubId++;

        s_subscriptions[s_currentSubId].owner = msg.sender;

        emit SubscriptionCreated(s_currentSubId, msg.sender);
        return s_currentSubId;
    }

    function addConsumer(uint64 subId, address consumer)
        external
        onlySubOwner(subId)
        nonReentrant
    {
        // Already maxed, cannot add any more consumers.
        if (s_subscriptions[subId].consumers.length == MAX_CONSUMERS) {
            revert TooManyConsumers();
        }
        if (s_consumers[consumer].nonces[subId] != 0) {
            // Idempotence - do nothing if already added.
            // Ensures uniqueness in subscriptions[subId].consumers.
            return;
        }
        // Initialize the nonce to 1, indicating the consumer is allocated.
        s_consumers[consumer].nonces[subId] = 1;
        s_consumers[consumer].lastSubscription = subId;
        s_subscriptions[subId].consumers.push(consumer);

        emit SubscriptionConsumerAdded(subId, consumer);
    }

    function fundSubscription(uint64 subId, uint256 amount)
        external
        nonReentrant
    {
        if (s_subscriptions[subId].owner == address(0)) {
            revert InvalidSubscription();
        }
        ARPA.safeTransferFrom(msg.sender, address(this), amount);
        // We do not check that the msg.sender is the subscription owner,
        // anyone can fund a subscription.
        uint256 oldBalance = s_subscriptions[subId].balance;
        s_subscriptions[subId].balance += uint96(amount);
        emit SubscriptionFunded(subId, oldBalance, oldBalance + amount);
    }

    function requestRandomness(
        RequestType requestType,
        bytes memory params,
        uint64 subId,
        uint256 seed,
        uint16 requestConfirmations,
        uint256 callbackGasLimit,
        uint256 callbackMaxGasPrice
    ) external override returns (bytes32) {
        // Input validation using the subscription storage.
        if (s_subscriptions[subId].owner == address(0)) {
            revert InvalidSubscription();
        }
        // Its important to ensure that the consumer is in fact who they say they
        // are, otherwise they could use someone else's subscription balance.
        // A nonce of 0 indicates consumer is not allocated to the sub.
        uint64 currentNonce = s_consumers[msg.sender].nonces[subId];
        if (currentNonce == 0) {
            revert InvalidConsumer(subId, msg.sender);
        }

        uint64 nonce = s_consumers[msg.sender].nonces[subId];
        uint256 rawSeed = makeRandcastInputSeed(seed, msg.sender, nonce);
        s_consumers[msg.sender].nonces[subId] += 1;
        bytes32 requestId = makeRequestId(rawSeed);

        // Estimate upper cost of this fulfillment.
        uint64 reqCount = s_subscriptions[subId].reqCount;
        uint96 payment = estimatePaymentAmount(
            callbackGasLimit,
            s_config.gasExceptCallback,
            getFeeTier(reqCount + 1),
            callbackMaxGasPrice
        );
        // Check balance with inflight cost and the payment.
        emit log_string("Estimate payment when request...");
        emit log_named_uint("tx.gasprice", tx.gasprice);
        emit log_named_uint(
            "balance minus inflight cost",
            s_subscriptions[subId].balance - s_subscriptions[subId].inflightCost
        );
        emit log_named_uint("estimated payment", payment);

        if (
            s_subscriptions[subId].balance -
                s_subscriptions[subId].inflightCost <
            payment
        ) {
            revert InsufficientBalanceWhenRequest();
        }
        s_subscriptions[subId].inflightCost += payment;
        s_subscriptions[subId].inflightPayments[requestId] = payment;

        // Record callback struct
        assert(s_callbacks[requestId].callbackContract == address(0));
        s_callbacks[requestId].callbackContract = msg.sender;
        s_callbacks[requestId].requestType = requestType;
        s_callbacks[requestId].params = params;
        s_callbacks[requestId].subId = subId;
        s_callbacks[requestId].seed = rawSeed;
        s_callbacks[requestId].blockNum = block.number;
        s_callbacks[requestId].requestConfirmations = requestConfirmations;
        s_callbacks[requestId].callbackGasLimit = callbackGasLimit;
        s_callbacks[requestId].callbackMaxGasPrice = callbackMaxGasPrice;

        // mock strategy of task assignment(group_index)
        emit RandomnessRequest(
            /*mock*/
            0,
            requestId,
            msg.sender,
            subId,
            seed,
            requestConfirmations,
            callbackGasLimit,
            callbackMaxGasPrice
        );

        return requestId;
    }

    function fulfillRandomness(
        uint256 groupIndex,
        bytes32 requestId,
        uint256 signature,
        PartialSignature[] memory partialSignatures
    ) public override {
        uint256 startGas = gasleft();

        // mock signature verification
        (groupIndex, partialSignatures);

        uint256 randomness = uint256(keccak256(abi.encode(signature)));

        Callback memory callback = s_callbacks[requestId];

        require(
            block.number >= callback.blockNum + callback.requestConfirmations,
            "Too early to fulfill"
        );

        BasicRandcastConsumerBase b;
        bytes memory resp;
        if (callback.requestType == RequestType.Randomness) {
            resp = abi.encodeWithSelector(
                b.rawFulfillRandomness.selector,
                requestId,
                randomness
            );
        } else if (callback.requestType == RequestType.RandomWords) {
            uint32 numWords = abi.decode(callback.params, (uint32));
            uint256[] memory randomWords = new uint256[](numWords);
            for (uint256 i = 0; i < numWords; i++) {
                randomWords[i] = uint256(keccak256(abi.encode(randomness, i)));
            }
            resp = abi.encodeWithSelector(
                b.rawFulfillRandomWords.selector,
                requestId,
                randomWords
            );
        } else if (callback.requestType == RequestType.Shuffling) {
            uint32 upper = abi.decode(callback.params, (uint32));
            uint256[] memory shuffledArray = shuffle(upper, randomness);
            resp = abi.encodeWithSelector(
                b.rawFulfillShuffledArray.selector,
                requestId,
                shuffledArray
            );
        }

        delete s_callbacks[requestId];

        // Call with explicitly the amount of callback gas requested
        // Important to not let them exhaust the gas budget and avoid oracle payment.
        // Do not allow any non-view/non-pure coordinator functions to be called
        // during the consumers callback code via reentrancyLock.
        // Note that callWithExactGas will revert if we do not have sufficient gas
        // to give the callee their requested amount.
        s_config.reentrancyLock = true;
        bool success = callWithExactGas(
            callback.callbackGasLimit,
            callback.callbackContract,
            resp
        );
        s_config.reentrancyLock = false;

        // Increment the req count for fee tier selection.
        uint64 reqCount = s_subscriptions[callback.subId].reqCount;
        s_subscriptions[callback.subId].reqCount += 1;

        // We want to charge users exactly for how much gas they use in their callback.
        // The gasAfterPaymentCalculation is meant to cover these additional operations where we
        // decrement the subscription balance and increment the groups withdrawable balance.
        // We also add the flat arpa fee to the payment amount.
        // Its specified in millionths of arpa, if s_config.fulfillmentFlatFeeArpaPPM = 1
        // 1 arpa / 1e6 = 1e18 arpa wei / 1e6 = 1e12 arpa wei.
        uint96 payment = calculatePaymentAmount(
            startGas,
            s_config.gasAfterPaymentCalculation,
            getFeeTier(reqCount),
            tx.gasprice
        );

        emit log_string("Calculate payment when fulfill...");
        emit log_named_uint("tx.gasprice", tx.gasprice);
        emit log_named_uint("balance", s_subscriptions[callback.subId].balance);
        emit log_named_uint("actual payment", payment);

        if (s_subscriptions[callback.subId].balance < payment) {
            revert InsufficientBalanceWhenFulfill();
        }
        s_subscriptions[callback.subId].inflightCost -= s_subscriptions[
            callback.subId
        ].inflightPayments[requestId];
        delete s_subscriptions[callback.subId].inflightPayments[requestId];
        s_subscriptions[callback.subId].balance -= payment;
        // TODO mock distribute payment to working group
        s_withdrawableTokens[groupIndex] += payment;

        // Include payment in the event for tracking costs.
        emit RandomnessRequestFulfilled(
            requestId,
            randomness,
            payment,
            success
        );
    }

    /**
     * @dev calls target address with exactly gasAmount gas and data as calldata
     * or reverts if at least gasAmount gas is not available.
     */
    function callWithExactGas(
        uint256 gasAmount,
        address target,
        bytes memory data
    ) private returns (bool success) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let g := gas()
            // Compute g -= GAS_FOR_CALL_EXACT_CHECK and check for underflow
            // The gas actually passed to the callee is min(gasAmount, 63//64*gas available).
            // We want to ensure that we revert if gasAmount >  63//64*gas available
            // as we do not want to provide them with less, however that check itself costs
            // gas.  GAS_FOR_CALL_EXACT_CHECK ensures we have at least enough gas to be able
            // to revert if gasAmount >  63//64*gas available.
            if lt(g, GAS_FOR_CALL_EXACT_CHECK) {
                revert(0, 0)
            }
            g := sub(g, GAS_FOR_CALL_EXACT_CHECK)
            // if g - g//64 <= gasAmount, revert
            // (we subtract g//64 because of EIP-150)
            if iszero(gt(sub(g, div(g, 64)), gasAmount)) {
                revert(0, 0)
            }
            // solidity calls check that a contract actually exists at the destination, so we do the same
            if iszero(extcodesize(target)) {
                revert(0, 0)
            }
            // call and return whether we succeeded. ignore return data
            // call(gas,addr,value,argsOffset,argsLength,retOffset,retLength)
            success := call(
                gasAmount,
                target,
                0,
                add(data, 0x20),
                mload(data),
                0,
                0
            )
        }
        return success;
    }

    /**
     * @notice Sets the configuration of the vrfv2 coordinator
     * @param minimumRequestConfirmations global min for request confirmations
     * @param maxGasLimit global max for request gas limit
     * @param stalenessSeconds if the eth/arpa feed is more stale then this, use the fallback price
     * @param gasAfterPaymentCalculation gas used in doing accounting after completing the gas measurement
     * @param fallbackWeiPerUnitArpa fallback eth/arpa price in the case of a stale feed
     * @param feeConfig fee tier configuration
     */
    function setConfig(
        uint16 minimumRequestConfirmations,
        uint32 maxGasLimit,
        uint32 stalenessSeconds,
        uint32 gasAfterPaymentCalculation,
        uint32 gasExceptCallback,
        int256 fallbackWeiPerUnitArpa,
        FeeConfig memory feeConfig
    ) external onlyOwner {
        if (minimumRequestConfirmations > MAX_REQUEST_CONFIRMATIONS) {
            revert InvalidRequestConfirmations(
                minimumRequestConfirmations,
                minimumRequestConfirmations,
                MAX_REQUEST_CONFIRMATIONS
            );
        }
        if (fallbackWeiPerUnitArpa <= 0) {
            revert InvalidArpaWeiPrice(fallbackWeiPerUnitArpa);
        }
        s_config = Config({
            minimumRequestConfirmations: minimumRequestConfirmations,
            maxGasLimit: maxGasLimit,
            stalenessSeconds: stalenessSeconds,
            gasAfterPaymentCalculation: gasAfterPaymentCalculation,
            gasExceptCallback: gasExceptCallback,
            reentrancyLock: false
        });
        s_feeConfig = feeConfig;
        s_fallbackWeiPerUnitArpa = fallbackWeiPerUnitArpa;
        emit ConfigSet(
            minimumRequestConfirmations,
            maxGasLimit,
            stalenessSeconds,
            gasAfterPaymentCalculation,
            gasExceptCallback,
            fallbackWeiPerUnitArpa,
            s_feeConfig
        );
    }

    /*
     * @notice Compute fee based on the request count
     * @param reqCount number of requests
     * @return feePPM fee in ARPA PPM
     */
    function getFeeTier(uint64 reqCount) public view returns (uint32) {
        FeeConfig memory fc = s_feeConfig;
        if (0 <= reqCount && reqCount <= fc.reqsForTier2) {
            return fc.fulfillmentFlatFeeArpaPPMTier1;
        }
        if (fc.reqsForTier2 < reqCount && reqCount <= fc.reqsForTier3) {
            return fc.fulfillmentFlatFeeArpaPPMTier2;
        }
        if (fc.reqsForTier3 < reqCount && reqCount <= fc.reqsForTier4) {
            return fc.fulfillmentFlatFeeArpaPPMTier3;
        }
        if (fc.reqsForTier4 < reqCount && reqCount <= fc.reqsForTier5) {
            return fc.fulfillmentFlatFeeArpaPPMTier4;
        }
        return fc.fulfillmentFlatFeeArpaPPMTier5;
    }

    // Estimate the amount of gas used for fulfillment
    function estimatePaymentAmount(
        uint256 callbackGasLimit,
        uint256 gasExceptCallback,
        uint32 fulfillmentFlatFeeArpaPPM,
        uint256 weiPerUnitGas
    ) internal view returns (uint96) {
        int256 weiPerUnitArpa;
        weiPerUnitArpa = getFeedData();
        if (weiPerUnitArpa <= 0) {
            revert InvalidArpaWeiPrice(weiPerUnitArpa);
        }
        // (1e18 arpa wei/arpa) (wei/gas * gas) / (wei/arpa) = arpa wei
        uint256 paymentNoFee = (1e18 *
            weiPerUnitGas *
            (gasExceptCallback + callbackGasLimit)) / uint256(weiPerUnitArpa);
        uint256 fee = 1e12 * uint256(fulfillmentFlatFeeArpaPPM);
        return uint96(paymentNoFee + fee);
    }

    // Get the amount of gas used for fulfillment
    function calculatePaymentAmount(
        uint256 startGas,
        uint256 gasAfterPaymentCalculation,
        uint32 fulfillmentFlatFeeArpaPPM,
        uint256 weiPerUnitGas
    ) internal view returns (uint96) {
        int256 weiPerUnitArpa;
        weiPerUnitArpa = getFeedData();
        if (weiPerUnitArpa <= 0) {
            revert InvalidArpaWeiPrice(weiPerUnitArpa);
        }
        // (1e18 arpa wei/arpa) (wei/gas * gas) / (wei/arpa) = arpa wei
        uint256 paymentNoFee = (1e18 *
            weiPerUnitGas *
            (gasAfterPaymentCalculation + startGas - gasleft())) /
            uint256(weiPerUnitArpa);
        uint256 fee = 1e12 * uint256(fulfillmentFlatFeeArpaPPM);
        if (paymentNoFee > (1e27 - fee)) {
            revert PaymentTooLarge(); // Payment + fee cannot be more than all of the arpa in existence.
        }
        return uint96(paymentNoFee + fee);
    }

    function getFeedData() private view returns (int256) {
        uint32 stalenessSeconds = s_config.stalenessSeconds;
        bool staleFallback = stalenessSeconds > 0;
        uint256 timestamp;
        int256 weiPerUnitArpa;
        (, weiPerUnitArpa, , timestamp, ) = ARPA_ETH_FEED.latestRoundData();
        // solhint-disable-next-line not-rely-on-time
        if (staleFallback && stalenessSeconds < block.timestamp - timestamp) {
            weiPerUnitArpa = s_fallbackWeiPerUnitArpa;
        }
        return weiPerUnitArpa;
    }

    function getLastSubscription(address consumer)
        public
        view
        override
        returns (uint64)
    {
        return s_consumers[consumer].lastSubscription;
    }

    function getSubscription(uint64 subId)
        public
        view
        override
        returns (
            uint96 balance,
            uint96 inflightCost,
            uint64 reqCount,
            address owner,
            address[] memory consumers
        )
    {
        if (s_subscriptions[subId].owner == address(0)) {
            revert InvalidSubscription();
        }
        return (
            s_subscriptions[subId].balance,
            s_subscriptions[subId].inflightCost,
            s_subscriptions[subId].reqCount,
            s_subscriptions[subId].owner,
            s_subscriptions[subId].consumers
        );
    }

    function getPendingRequest(bytes32 requestId)
        public
        view
        returns (Callback memory)
    {
        return s_callbacks[requestId];
    }

    modifier onlySubOwner(uint64 subId) {
        address owner = s_subscriptions[subId].owner;
        if (owner == address(0)) {
            revert InvalidSubscription();
        }
        if (msg.sender != owner) {
            revert MustBeSubOwner(owner);
        }
        _;
    }

    modifier nonReentrant() {
        if (s_config.reentrancyLock) {
            revert Reentrant();
        }
        _;
    }
}
