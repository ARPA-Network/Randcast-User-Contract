// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import "./RandcastConsumerBase.sol";

contract GetRandomNumberExample is RandcastConsumerBase {
    /* requestId -> randomness */
    mapping(bytes32 => uint256) public randomResults;
    uint256[] public randomnessResults;

    constructor(address controller, address arpa)
        RandcastConsumerBase(controller, arpa)
    {}

    /**
     * Requests randomness
     */
    function getRandomNumber(uint256 seed) public returns (bytes32 requestId) {
        require(
            arpa.balanceOf(address(this)) >= requestFee,
            "Not enough ARPA - fill contract with faucet"
        );
        bytes memory params;
        return requestRandomness(RequestType.Randomness, params, seed);
    }

    /**
     * Callback function used by Randcast Controller
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        randomResults[requestId] = randomness;
        randomnessResults.push(randomness);
    }

    function lengthOfRandomnessResults() public view returns (uint256) {
        return randomnessResults.length;
    }
}
