// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

abstract contract Utils {
    //@notice Generate a map based on the provided dimension
    //
    //@param randomness The randome number used to generate the map
    //@param width The width of the map
    //@param height The height of the map
    //@return map The generated map
    function generateMap(
        uint256 randomness,
        uint256 width, 
        uint256 height
    ) internal pure returns(uint256[][] memory map) {}


    //@notice Pick a winner between 2 players  
    //
    //@param randomness The randome number used to determine the winner
    //@return winner The value of -1 suggests that player 1 wins. 
    //               The value of 1 suggests that player 2 wins. 
    //               The value of 0 suggests a tie.
    function pickWinner(
        uint256 randomness
    ) internal pure returns(int8 winner) {}

    //@notice draw a lottery and determine the winning tickets 
    //
    //@param randomWords A list of random numbers used to determine the winners
    //@param tickets The total number of tickets for a lottery
    //@param numWinners The number of winning tickets for a lottery
    //@return winners The winning tickets for a lottery
    function draw(
        uint256[] memory randomWords,
        uint256 tickets,
        uint256 numWinners
    ) internal pure returns(uint256[] memory winners) {}

    //@notice pick attributes from a list of attribute values
    //
    //@param randomWords A list of random numbers used to determine the attributes
    //@param attributes A list of attributes with their corresponding values
    //@return values The determined values for the input attributes
    function pickAttributesFromValues(
        uint256[] memory randomWords,
        uint256[][] memory attributes
    ) internal pure returns(uint256[] memory values) {}

    //@notice pick attributes from a list of attribute numeric ranges
    //
    //@param randomWords A list of random numbers used to determine the attributes' values. 
    //@param attributes A list of attributes with their corresponding numeric ranges
    //       Each attribute defines a range with [lower, upper].
    //@return values The determined values for the input attributes
    function pickAttributesFromRanges(
        uint256[] memory randomWords,
        uint256[][2] memory attributes
    ) internal pure returns(uint256[] memory values) {}

    //@notice generate a batch of random numbers using a single random number as the seed  
    //
    //@param randomness The random number as the seed to genrate a batch of random numbers
    //@param number The quantity of the requested random numbers in the batch 
    //@return batch A list of random numbers generated using a single seed
    function batchRandomness(
        uint256 randomness,
        uint256 number
    ) internal pure returns(uint256[] memory batch) {}

    //@notice generate an randomly ordered list from 0 to the upper bound
    //
    //@param randomness The random number used to shuffle the list
    //@param upper The upper bound of the list
    //@return list The list of numbers that are randomly ordered
    function shuffle(
        uint256 randomness,
        uint256 upper
    ) internal pure returns(uint256[] memory list) {}

    //@notice shuffle a list of numbers
    //
    //@param randomness The random number used to shuffle the list
    //@param list The input list that needs to be shuffled
    //@return randomList The list of numbers that are randomly ordered
    function shuffle(
        uint256 randomness,
        uint256[] memory list
    ) internal pure returns(uint256[] memory randomList) {}

}
