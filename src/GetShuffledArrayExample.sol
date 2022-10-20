// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import "./RandcastConsumerBase.sol";

contract GetShuffledArrayExample is RandcastConsumerBase {
    /* requestId -> randomness */
    mapping(bytes32 => uint256[]) public randomResults;
    uint256[] public shuffleResults;

    constructor(address controller, address arpa)
        RandcastConsumerBase(controller, arpa)
    {}

    /**
     * Requests randomness
     */
    function getShuffledArray(uint256 seed, uint32 upper)
        public
        returns (bytes32 requestId)
    {
        require(
            arpa.balanceOf(address(this)) >= requestFee,
            "Not enough ARPA - fill contract with faucet"
        );
        bytes memory params = abi.encode(upper);
        return requestRandomness(RequestType.Shuffling, params, seed);
    }

    /**
     * Callback function used by Randcast Controller
     */
    function fulfillShuffledArray(bytes32 requestId, uint256[] memory array)
        internal
        override
    {
        randomResults[requestId] = array;
        shuffleResults = array;
    }

    function lengthOfShuffleResults() public view returns (uint256) {
        return shuffleResults.length;
    }
}
