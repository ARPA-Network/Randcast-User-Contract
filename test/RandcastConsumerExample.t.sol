// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.10;

import "forge-std/Test.sol";
import "../src/GetRandomNumberExample.sol";
import "../src/GetShuffledArrayExample.sol";
import "../src/RollDiceExample.sol";
import "../src/IController.sol";
import "./MockController.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract RandcastConsumerExampleTest is Test {
    GetRandomNumberExample getRandomNumberExample;
    GetShuffledArrayExample getShuffledArrayExample;
    RollDiceExample rollDiceExample;
    MockController mockController;
    IERC20 arpa;

    address public admin = address(0xABCD);
    address public user = address(0x11);
    address public node = address(0x22);

    function setUp() public {
        changePrank(admin);
        arpa = new ERC20("arpa token", "ARPA");
        mockController = new MockController();
        getRandomNumberExample = new GetRandomNumberExample(
            address(mockController),
            address(arpa)
        );
        rollDiceExample = new RollDiceExample(
            address(mockController),
            address(arpa)
        );
        getShuffledArrayExample = new GetShuffledArrayExample(
            address(mockController),
            address(arpa)
        );
    }

    function testControllerAddress() public {
        emit log_address(address(mockController));
        assertEq(getRandomNumberExample.controller(), address(mockController));
        assertEq(rollDiceExample.controller(), address(mockController));
        assertEq(getShuffledArrayExample.controller(), address(mockController));
    }

    function testGetRandomNumber() public {
        changePrank(admin);
        deal(user, 1 * 10**18);
        deal(address(arpa), address(getRandomNumberExample), 2000 * 10**18);
        changePrank(user);

        uint32 times = 10;
        for (uint256 i = 0; i < times; i++) {
            getRandomNumberExample.getRandomNumber(42);
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
        changePrank(admin);
        deal(user, 1 * 10**18);
        deal(address(arpa), address(rollDiceExample), 200 * 10**18);
        changePrank(user);

        uint32 bunch = 10;
        rollDiceExample.rollDice(42, bunch);

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
        changePrank(admin);
        deal(user, 1 * 10**18);
        deal(address(arpa), address(getShuffledArrayExample), 200 * 10**18);
        changePrank(user);

        uint32 upper = 10;
        getShuffledArrayExample.getShuffledArray(42, upper);

        for (
            uint256 i = 0;
            i < getShuffledArrayExample.lengthOfShuffleResults();
            i++
        ) {
            emit log_uint(getShuffledArrayExample.shuffleResults(i));
            assertTrue(
                getShuffledArrayExample.shuffleResults(i) >= 0 &&
                    getShuffledArrayExample.shuffleResults(i) < upper
            );
        }
        assertEq(getShuffledArrayExample.lengthOfShuffleResults(), upper);
    }

    // function testFailxxx() public {
    // }
}
