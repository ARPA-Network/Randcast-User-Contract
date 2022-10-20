// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface RequestTypeBase {
    enum RequestType {
        Randomness,
        RandomWords,
        Shuffling
    }
}
