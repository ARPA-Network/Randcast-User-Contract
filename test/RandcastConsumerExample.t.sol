// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import "../src/examples/GetRandomNumberExample.sol";
import "../src/examples/GetShuffledArrayExample.sol";
import "../src/examples/RollDiceExample.sol";
import "../src/examples/AdvancedGetShuffledArrayExample.sol";
import "./RandcastTestHelper.sol";

contract RandcastConsumerExampleTest is RandcastTestHelper {
    GetRandomNumberExample getRandomNumberExample;
    GetShuffledArrayExample getShuffledArrayExample;
    RollDiceExample rollDiceExample;
    AdvancedGetShuffledArrayExample advancedGetShuffledArrayExample;

    function setUp() public {
        skip(1000);
        changePrank(admin);
        arpa = new ERC20("arpa token", "ARPA");
        oracle = new MockOracle();
        mockController = new MockController(address(arpa), address(oracle));
        getRandomNumberExample = new GetRandomNumberExample(
            address(mockController)
        );
        rollDiceExample = new RollDiceExample(address(mockController));
        getShuffledArrayExample = new GetShuffledArrayExample(
            address(mockController)
        );
        advancedGetShuffledArrayExample = new AdvancedGetShuffledArrayExample(
            address(mockController)
        );

        uint16 minimumRequestConfirmations = 3;
        uint32 maxGasLimit = 2000000;
        uint32 stalenessSeconds = 30;
        uint32 gasAfterPaymentCalculation = 30000;
        uint32 gasExceptCallback = 200000;
        int256 fallbackWeiPerUnitArpa = 1e12;
        mockController.setConfig(
            minimumRequestConfirmations,
            maxGasLimit,
            stalenessSeconds,
            gasAfterPaymentCalculation,
            gasExceptCallback,
            fallbackWeiPerUnitArpa,
            MockController.FeeConfig(
                250000,
                250000,
                250000,
                250000,
                250000,
                0,
                0,
                0,
                0
            )
        );

        uint96 plentyOfArpaBalance = 1e6 * 1e18;
        deal(address(arpa), address(admin), 3 * plentyOfArpaBalance);
        arpa.approve(address(mockController), 3 * plentyOfArpaBalance);
        prepareSubscription(
            address(getRandomNumberExample),
            plentyOfArpaBalance
        );
        prepareSubscription(address(rollDiceExample), plentyOfArpaBalance);
        prepareSubscription(
            address(getShuffledArrayExample),
            plentyOfArpaBalance
        );
    }

    function testControllerAddress() public {
        emit log_address(address(mockController));
        assertEq(getRandomNumberExample.controller(), address(mockController));
        assertEq(rollDiceExample.controller(), address(mockController));
        assertEq(getShuffledArrayExample.controller(), address(mockController));
    }

    function testGetRandomNumber() public {
        deal(user, 1 * 1e18);
        changePrank(user);

        uint32 times = 10;
        for (uint256 i = 0; i < times; i++) {
            bytes32 requestId = getRandomNumberExample.getRandomNumber();

            deal(node, 1 * 1e18);
            changePrank(node);
            fulfillRequest(requestId);

            changePrank(user);
            vm.roll(block.number + 1);
        }

        for (
            uint256 i = 0;
            i < getRandomNumberExample.lengthOfRandomnessResults();
            i++
        ) {
            emit log_uint(getRandomNumberExample.randomnessResults(i));
        }
        assertEq(getRandomNumberExample.lengthOfRandomnessResults(), times);
    }

    function testRollDice() public {
        deal(user, 1 * 1e18);
        changePrank(user);

        uint32 bunch = 10;
        bytes32 requestId = rollDiceExample.rollDice(bunch);

        deal(node, 1 * 1e18);
        changePrank(node);
        fulfillRequest(requestId);

        changePrank(user);

        for (uint256 i = 0; i < rollDiceExample.lengthOfDiceResults(); i++) {
            emit log_uint(rollDiceExample.diceResults(i));
            assertTrue(
                rollDiceExample.diceResults(i) > 0 &&
                    rollDiceExample.diceResults(i) <= 6
            );
        }
        assertEq(rollDiceExample.lengthOfDiceResults(), bunch);
    }

    function testGetShuffledArray() public {
        deal(user, 1 * 1e18);
        changePrank(user);

        uint32 upper = 10;
        bytes32 requestId = getShuffledArrayExample.getShuffledArray(upper);

        deal(node, 1 * 1e18);
        changePrank(node);
        fulfillRequest(requestId);

        changePrank(user);

        for (uint256 i = 0; i < upper; i++) {
            emit log_uint(getShuffledArrayExample.shuffleResults(i));
            assertTrue(
                getShuffledArrayExample.shuffleResults(i) >= 0 &&
                    getShuffledArrayExample.shuffleResults(i) < upper
            );
        }
        assertEq(getShuffledArrayExample.lengthOfShuffleResults(), upper);
    }

    function testAdvancedGetShuffledArray() public {
        changePrank(admin);
        uint96 plentyOfArpaBalance = 1e6 * 1e18;
        deal(address(arpa), address(admin), plentyOfArpaBalance);
        arpa.approve(address(mockController), plentyOfArpaBalance);
        uint64 subId = prepareSubscription(
            address(advancedGetShuffledArrayExample),
            plentyOfArpaBalance
        );

        deal(user, 1 * 1e18);
        changePrank(user);

        uint32 upper = 10;
        uint256 seed = 42;
        uint16 requestConfirmations = 0;
        uint256 callbackGasLimit = 260000;
        uint256 callbackMaxGasPrice = 1 * 1e9;

        bytes32 requestId = advancedGetShuffledArrayExample
            .getRandomNumberThenGenerateShuffledArray(
                upper,
                subId,
                seed,
                requestConfirmations,
                callbackGasLimit,
                callbackMaxGasPrice
            );

        deal(node, 1 * 1e18);
        changePrank(node);
        fulfillRequest(requestId);

        changePrank(user);

        assertEq(advancedGetShuffledArrayExample.lengthOfShuffleResults(), 1);

        for (
            uint256 k = 0;
            k < advancedGetShuffledArrayExample.lengthOfShuffleResults();
            k++
        ) {
            for (uint256 i = 0; i < upper; i++) {
                emit log_uint(
                    advancedGetShuffledArrayExample.shuffleResults(k, i)
                );
                assertTrue(
                    advancedGetShuffledArrayExample.shuffleResults(k, i) >= 0 &&
                        advancedGetShuffledArrayExample.shuffleResults(k, i) <
                        upper
                );
            }
        }
    }
}
