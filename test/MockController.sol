// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.10;

import "forge-std/Test.sol";
import "../src/IController.sol";
import "../src/RandcastConsumerBase.sol";

contract MockController is IController, Test {
    mapping(address => uint256) public nonces;
    struct Callback {
        address callbackContract;
        RequestType requestType;
        bytes params;
        bytes32 seedAndBlockNum;
    }

    mapping(bytes32 => Callback) public callbacks;

    function makeRandcastInputSeed(
        uint256 _userSeed,
        address _requester,
        uint256 _nonce
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(_userSeed, _requester, _nonce)));
    }

    function makeRequestId(uint256 inputSeed) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(inputSeed));
    }

    function requestRandomness(
        RequestType requestType,
        bytes memory params,
        uint256 seed
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
        callbacks[requestId].seedAndBlockNum = keccak256(
            abi.encodePacked(rawSeed, block.number)
        );

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
        RandcastConsumerBase b;
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

        (bool success, ) = callback.callbackContract.call(resp);

        (success);

        emit RandomnessRequestFulfilled(requestId, randomness);
    }

    function shuffle(uint256 upper, uint256 randomness)
        internal
        pure
        returns (uint256[] memory)
    {
        uint256[] memory arr = new uint256[](upper);
        for (uint256 k = 0; k < upper; k++) {
            arr[k] = k;
        }
        uint256 i = arr.length;
        uint256 j;
        uint256 t;

        while (--i > 0) {
            j = randomness % i;
            randomness = uint256(keccak256(abi.encode(randomness)));
            t = arr[i];
            arr[i] = arr[j];
            arr[j] = t;
        }

        return arr;
    }
}
