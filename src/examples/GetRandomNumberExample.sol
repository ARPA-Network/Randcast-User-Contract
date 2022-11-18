// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import "../GeneralRandcastConsumerBase.sol";

contract GetRandomNumberExample is GeneralRandcastConsumerBase {
    /* requestId -> randomness */
    mapping(bytes32 => uint256) public randomResults;
    uint256[] public randomnessResults;

    constructor(address controller, address arpa)
        BasicRandcastConsumerBase(controller, arpa)
    {}

    /**
     * Requests randomness
     */
    function getRandomNumber() external {
        require(
            arpa.balanceOf(address(this)) >= requestFee,
            "Not enough ARPA - fill contract with faucet"
        );
        bytes memory params;
        requestRandomness(RequestType.Randomness, params);
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
