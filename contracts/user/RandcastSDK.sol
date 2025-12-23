// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @dev This function generates a shuffled array of uniformly distributed numbers within a specified range.
 * @param upper The upper limit on the range of numbers in the array.
 * @param randomness The initial seed for the random number generator used in shuffling.
 * @return arr Returns a randomly shuffled array
 */
function shuffle(uint256 upper, uint256 randomness) pure returns (uint256[] memory) {
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

/**
 * @dev This function returns a subset of randomly chosen elements from an array.
 * @param seed The initial value used for generating hash.
 * @param indices The initial array of indices to choose from.
 * @param count The number of indices to choose.
 * @return chosenIndices Returns the selected indices as an array.
 */
function draw(uint256 seed, uint256[] memory indices, uint256 count) pure returns (uint256[] memory) {
    return drawWithOffset(seed, indices, count, 0);
}

function drawWithOffset(uint256 seed, uint256[] memory indices, uint256 count, uint256 offset)
    pure
    returns (uint256[] memory)
{
    require(offset <= 1, "Offset must be less than or equal to 1");
    require(count <= indices.length, "Count cannot exceed indices length");
    if (count == 0) {
        return new uint256[](0);
    }

    uint256[] memory chosenIndices = new uint256[](count);

    // Create copy of indices to avoid modifying original array.
    uint256[] memory remainingIndices = new uint256[](indices.length);
    for (uint256 i = 0; i < indices.length; i++) {
        remainingIndices[i] = indices[i];
    }

    uint256 remainingCount = remainingIndices.length;
    for (uint256 i = 0; i < count; i++) {
        uint256 index = uint256(keccak256(abi.encodePacked(seed, i))) % remainingCount;
        chosenIndices[i] = remainingIndices[index] + offset;
        remainingIndices[index] = remainingIndices[remainingCount - 1];
        remainingCount--;
    }
    return chosenIndices;
}

/**
 * @dev This function performs a simple random roll to pick an number within a specified size.
 * @param randomness Random number used in determining the chosen number.
 * @param size The range (or size) of possible indices.
 * @return number The randomly chosen number.
 */
function roll(uint256 randomness, uint256 size) pure returns (uint256 number) {
    return randomness % size;
}

/**
 * @dev This function chooses an index based on provided weights, will revert if valueWeights is empty.
 * @param randomness The random number used to choose the index.
 * @param valueWeights An array of weight values corresponding to indices.
 * @return chosenIndex The picked index.
 */
function pickByWeights(uint256 randomness, uint256[] memory valueWeights) pure returns (uint256 chosenIndex) {
    uint256 weightsLen = valueWeights.length;
    require(weightsLen > 0, "Weights array cannot be empty");

    // calculate total weight
    uint256 sum = 0;
    for (uint256 i = 0; i < weightsLen; i++) {
        sum += valueWeights[i];
    }
    require(sum > 0, "Total weight must be greater than 0");

    uint256 weightValue = randomness % sum;

    // build cumulative sum and find the index
    uint256 cumulative = 0;
    for (uint256 i = 0; i < weightsLen; i++) {
        cumulative += valueWeights[i];
        if (weightValue < cumulative) {
            return i;
        }
    }

    // theoretically should not reach here, but for safety
    return weightsLen - 1;
}

/**
 * @dev This function generates a batch of random numbers based on a given seed.
 * @param seed The initial value used for generating hash.
 * @param length The number of random values.
 * @return batchRandomness An array of random numbers.
 */
function batch(uint256 seed, uint256 length) pure returns (uint256[] memory) {
    uint256[] memory batchRandomness = new uint256[](length);
    for (uint256 i = 0; i < length; ++i) {
        batchRandomness[i] = uint256(keccak256(abi.encode(seed, i)));
    }
    return batchRandomness;
}
