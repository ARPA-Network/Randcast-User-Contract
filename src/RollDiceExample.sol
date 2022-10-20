// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import "./RandcastConsumerBase.sol";

contract RollDiceExample is RandcastConsumerBase {
    /* requestId -> randomness */
    mapping(bytes32 => uint256[]) public randomResults;
    uint256[] public diceResults;

    constructor(address controller, address arpa)
        RandcastConsumerBase(controller, arpa)
    {}

    /**
     * Requests randomness
     */
    function rollDice(uint256 seed, uint32 bunch)
        public
        returns (bytes32 requestId)
    {
        require(
            arpa.balanceOf(address(this)) >= requestFee,
            "Not enough ARPA - fill contract with faucet"
        );
        bytes memory params = abi.encode(bunch);
        return requestRandomness(RequestType.RandomWords, params, seed);
    }

    /**
     * Callback function used by Randcast Controller
     */
    function fulfillRandomWords(bytes32 requestId, uint256[] memory randomWords)
        internal
        override
    {
        randomResults[requestId] = randomWords;
        diceResults = new uint256[](randomWords.length);
        for (uint32 i = 0; i < randomWords.length; i++) {
            diceResults[i] = (randomWords[i] % 6) + 1;
        }
    }

    function lengthOfDiceResults() public view returns (uint256) {
        return diceResults.length;
    }
}
