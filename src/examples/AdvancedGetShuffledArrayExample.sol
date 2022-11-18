// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import "../BasicRandcastConsumerBase.sol";
import "../utils/RandomnessHandler.sol";
import "../RequestIdBase.sol";

contract AdvancedGetShuffledArrayExample is
    RequestIdBase,
    BasicRandcastConsumerBase,
    RandomnessHandler
{
    mapping(bytes32 => uint256) public shuffledArrayUppers;
    uint256[][] public shuffleResults;

    constructor(address controller, address arpa)
        BasicRandcastConsumerBase(controller, arpa)
    {}

    /**
     * Requests randomness
     */
    function getRandomNumberThenGenerateShuffledArray(
        uint256 shuffledArrayUpper,
        uint256 seed,
        uint16 requestConfirmations,
        uint256 callbackGasLimit
    ) external {
        require(
            arpa.balanceOf(address(this)) >= requestFee,
            "Not enough ARPA - fill contract with faucet"
        );
        bytes memory params;

        uint256 rawSeed = makeRandcastInputSeed(seed, address(this), nonce);
        // This should be identical to controller generated requestId.
        bytes32 requestId = makeRequestId(rawSeed);

        shuffledArrayUppers[requestId] = shuffledArrayUpper;

        rawRequestRandomness(
            RequestType.Randomness,
            params,
            seed,
            requestConfirmations,
            callbackGasLimit
        );

        // These equals to following code(recommended):
        // bytes32 requestId = rawRequestRandomness(
        //     RequestType.Randomness,
        //     params,
        //     seed,
        //     requestConfirmations,
        //     callbackGasLimit
        // );

        // shuffledArrayUppers[requestId] = shuffledArrayUpper;
    }

    /**
     * Callback function used by Randcast Controller
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        shuffleResults.push(
            shuffle(shuffledArrayUppers[requestId], randomness)
        );
    }

    function lengthOfShuffleResults() public view returns (uint256) {
        return shuffleResults.length;
    }
}
