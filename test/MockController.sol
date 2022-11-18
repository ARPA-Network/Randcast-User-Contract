// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.10;

import "forge-std/Test.sol";
import "../src/interfaces/IController.sol";
import "../src/BasicRandcastConsumerBase.sol";
import "../src/RequestIdBase.sol";
import "../src/utils/RandomnessHandler.sol";

contract MockController is IController, RequestIdBase, RandomnessHandler, Test {
    mapping(address => uint256) public nonces;
    // TODO only record the hash of the callback params to save storage gas
    struct Callback {
        address callbackContract;
        RequestType requestType;
        bytes params;
        uint256 seed;
        uint256 blockNum;
        uint16 requestConfirmations;
        uint256 callbackGasLimit;
    }

    mapping(bytes32 => Callback) public callbacks;

    function requestRandomness(
        RequestType requestType,
        bytes memory params,
        uint256 seed,
        uint16 requestConfirmations,
        uint256 callbackGasLimit
    ) external returns (bytes32) {
        uint256 rawSeed = makeRandcastInputSeed(
            seed,
            msg.sender,
            nonces[msg.sender]
        );
        nonces[msg.sender] = nonces[msg.sender] + 1;
        bytes32 requestId = makeRequestId(rawSeed);

        assert(callbacks[requestId].callbackContract == address(0));
        callbacks[requestId].callbackContract = msg.sender;
        callbacks[requestId].requestType = requestType;
        callbacks[requestId].params = params;
        callbacks[requestId].seed = rawSeed;
        callbacks[requestId].blockNum = block.number;
        callbacks[requestId].requestConfirmations = requestConfirmations;
        callbacks[requestId].callbackGasLimit = callbackGasLimit;

        // mock confirmation times
        vm.roll(block.number + requestConfirmations);
        // mock strategy of task assignment(group_index)
        emit RandomnessRequest(seed, 0, requestId, msg.sender);
        // mock fulfillRandomness directly
        PartialSignature[] memory mockPartialSignatures;
        uint256 actualSeed = uint256(
            keccak256(abi.encodePacked(rawSeed, block.number))
        );
        fulfillRandomness(
            0,
            requestId,
            uint256(keccak256(abi.encode(actualSeed))),
            mockPartialSignatures
        );
        return requestId;
    }

    function fulfillRandomness(
        uint256 groupIndex,
        bytes32 requestId,
        uint256 signature,
        PartialSignature[] memory partialSignatures
    ) public {
        // mock signature verification
        (groupIndex, partialSignatures);

        uint256 randomness = uint256(keccak256(abi.encode(signature)));

        Callback memory callback = callbacks[requestId];

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

        delete callbacks[requestId];

        (bool success, ) = callback.callbackContract.call{
            gas: callback.callbackGasLimit
        }(resp);

        (success);

        emit RandomnessRequestFulfilled(requestId, randomness);
    }
}
