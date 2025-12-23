# SharedConsumer: A Production-Ready Randomness Consumer Contract for Lottery and Gaming Demonstrations

## Overview

`SharedConsumer` is a comprehensive, production-ready smart contract built on top of Randcast that provides out-of-the-box randomness solutions for various lottery and gaming scenarios. It serves as both a practical tool for communities seeking immediate randomness functionality and a reference implementation for developers looking to integrate Randcast into their projects.

The contract has been deployed across multiple major blockchain networks as part of the **Randcast Playground**, demonstrating its reliability and versatility in real-world applications.

## Key Features

### 🎯 Three Built-in Play Types

`SharedConsumer` supports three distinct randomness use cases:

1. **Draw Tickets** - Fair lottery ticket drawing from a pool
2. **Roll Dice** - Multiple dice rolls with customizable dice sizes
3. **Gacha** - Weighted random selection with rarity tiers (perfect for NFT drops, loot boxes, and card games)

### 💰 Free Response Callbacks

One of the standout features of `SharedConsumer` is that **response callbacks from trial subscription are completely free**. Users only pay for the initial randomness request, making it cost-effective for lottery and gaming demonstrations.

### 📚 Developer Reference

As a demonstration project, `SharedConsumer` showcases best practices for:

- Integrating with Randcast Adapter
- Implementing randomness callbacks
- Managing subscriptions and fees
- Handling different randomness request types
- Gas optimization strategies

## Deployment Status

The `SharedConsumer` contract has been deployed as part of the **Randcast Playground** on multiple major blockchain networks, including:

- **Ethereum Mainnet**(https://etherscan.io/address/0x8acfc64bF976488E9B83c517D4185Fd4D8A9D683)
- **BSC Mainnet**(https://bscscan.com/address/0x9a599D28907780289bB980ddFA38A17B1176FC29)
- **Base Mainnet**(https://basescan.org/address/0xC9519853F9E9576303dB70a054d320aCA82005Ad)
- **Optimism Mainnet**(https://optimistic.etherscan.io/address/0x9B9b0ea8b7a565dB81D3C78129626f077D47f7B9)
- **Taiko Mainnet**(https://taikoscan.io/address/0x9A6E06aa83eBF588c136dD7991d9002DF1E181CF)
- **Ethereum Hoodi Testnet**(https://hoodi.etherscan.io/address/0x1D2c2d06e6d923B2B88B1CDDb0955d418fae48a8)
- And more...

The Playground serves as:

1. **Production Environment**: Real-world testing and usage by communities
2. **Reference Implementation**: Code examples and integration patterns
3. **Cost Demonstration**: Showcasing the efficiency of Randcast's free response model

## Integration Guide

### For Communities (Quick Start)

1. **Connect to Playground**: Open the Playground website at [https://www.arpanetwork.io/play](https://www.arpanetwork.io/play)
2. **Select a Network**: Choose the network you want to use from the dropdown menu
3. **Read the Rules**: Read the rules(`help` command) for the play type and the parameters you want to use
4. **Send the Request**: In a simulated cmd window, enter the command `cast/draw/gacha` to send the request
5. **Wait for the result**: The result will be displayed in the console
6. **Pay Only for Requests**: Response callbacks are free!

### For Developers (Custom Integration)

1. **Study the Contract**: Review `SharedConsumer.sol` as a reference implementation
2. **Understand Patterns**: Learn how to:
   - Integrate with `BasicRandcastConsumerBase`
   - Implement `_fulfillRandomWords` and `_fulfillRandomness` callbacks
   - Calculate gas limits dynamically
   - Manage subscriptions
3. **Adapt to Your Needs**: Customize the contract for your specific use case
4. **Deploy Your Own**: Use the patterns learned to build your own consumer contract

## Contract Architecture

### Inheritance Structure

```solidity
contract SharedConsumer is
    RequestIdBase,
    BasicRandcastConsumerBase,
    UUPSUpgradeable,
    OwnableUpgradeable
```

- **RequestIdBase**: Provides request ID generation utilities
- **BasicRandcastConsumerBase**: Base contract for Randcast integration
- **UUPSUpgradeable**: Allows contract upgrades via UUPS proxy pattern
- **OwnableUpgradeable**: Provides access control for administrative functions

### Core Components

#### Play Types

```solidity
enum PlayType {
    Draw,    // Lottery ticket drawing
    Roll,     // Dice rolling
    Gacha     // Weighted random selection
}
```

#### Subscription Management

The contract:

- Supports trial subscription for demo purposes
- Allows users to use their own subscriptions
- Allows users to cancel their subscriptions

## Functionality Details

### 1. Draw Tickets (`drawTickets`)

Fairly selects winners from a pool of tickets.

**Use Cases:**

- Community giveaways
- Airdrop distribution
- Contest winner selection
- Token distribution lotteries

**Parameters:**

- `totalNumber`: Total number of tickets in the pool (max 1000)
- `winnerNumber`: Number of winners to select
- `subId`: Subscription ID (0 for auto-creation)
- `seed`: Random seed for request
- `requestConfirmations`: Number of block confirmations (0 for default)
- `message`: Optional message (often merkle root of ticket list)

**Example:**

```solidity
// Draw 10 winners from 1000 tickets
bytes32 requestId = sharedConsumer.drawTickets(
    1000,  // totalNumber
    10,    // winnerNumber
    0,     // subId (auto-create)
    123,   // seed
    0,     // requestConfirmations
    ""     // message
);
```

**Events:**

- `DrawTicketsRequest`: Emitted when request is made
- `DrawTicketsResult`: Emitted with winner ticket numbers

### 2. Roll Dice (`rollDice`)

Performs multiple dice rolls with customizable dice sizes.

**Use Cases:**

- Gaming mechanics
- Random number generation
- Decision making tools
- Multi-outcome randomness

**Parameters:**

- `bunch`: Number of dice rolls (max 100)
- `size`: Number of sides on each die
- `subId`: Subscription ID (0 for auto-creation)
- `seed`: Random seed for request
- `requestConfirmations`: Number of block confirmations (0 for default)
- `message`: Optional message

**Example:**

```solidity
// Roll 5 dice, each with 6 sides
bytes32 requestId = sharedConsumer.rollDice(
    5,   // bunch
    6,   // size
    0,   // subId
    456, // seed
    0,   // requestConfirmations
    ""   // message
);
```

**Events:**

- `RollDiceRequest`: Emitted when request is made
- `RollDiceResult`: Emitted with dice roll results (1-indexed)

### 3. Gacha (`gacha`)

Performs weighted random selection with rarity tiers and upper limits.

**Use Cases:**

- NFT drops with rarity tiers
- Loot box mechanics
- Card pack opening
- Item rarity distribution

**Parameters:**

- `count`: Number of items to draw (max 100)
- `weights`: Array of weights for each rarity tier
- `upperLimits`: Array of upper limits for each tier (index range)
- `subId`: Subscription ID (0 for auto-creation)
- `seed`: Random seed for request
- `requestConfirmations`: Number of block confirmations (0 for default)
- `message`: Optional message

**Example:**

```solidity
// Draw 10 items with 4 rarity tiers
uint256[] memory weights = new uint256[](4);
weights[0] = 7;  // Common
weights[1] = 5;  // Uncommon
weights[2] = 3;  // Rare
weights[3] = 1;  // Legendary

uint256[] memory upperLimits = new uint256[](4);
upperLimits[0] = 500;  // Common: items 1-500
upperLimits[1] = 200;  // Uncommon: items 1-200
upperLimits[2] = 50;  // Rare: items 1-50
upperLimits[3] = 10;  // Legendary: items 1-10

bytes32 requestId = sharedConsumer.gacha(
    10,           // count
    weights,      // weights
    upperLimits,  // upperLimits
    0,            // subId
    789,          // seed
    0,            // requestConfirmations
    ""            // message
);
```

**Events:**

- `GachaRequest`: Emitted when request is made
- `GachaResult`: Emitted with weight results (tier indices) and index results (item IDs)

**Result Interpretation:**

- `weightResults`: Array indicating which rarity tier was selected for each draw
- `indexResults`: Array indicating the specific item ID within the selected tier

## Events Reference

### Request Events

- `DrawTicketsRequest`: Lottery ticket drawing request
- `RollDiceRequest`: Dice rolling request
- `GachaRequest`: Gacha/loot box request

### Result Events

- `DrawTicketsResult`: Winner ticket numbers
- `RollDiceResult`: Dice roll results
- `GachaResult`: Weight and index results

All events include `requestId` for easy tracking and correlation.

## Limitations

- **Draw Tickets**: Maximum 1000 tickets, winner count must be ≤ total tickets
- **Roll Dice**: Maximum 100 rolls per request
- **Gacha**: Maximum 100 items per draw, weights and upperLimits arrays must match length

## Conclusion

`SharedConsumer` represents a production-ready solution for randomness needs in Web3 applications. Whether you're a community looking for immediate lottery functionality or a developer seeking integration patterns, `SharedConsumer` provides a robust foundation built on Randcast's decentralized randomness infrastructure.

The contract's deployment across multiple networks in the Randcast Playground demonstrates its reliability and versatility, while its free response callbacks from trial subscription make it economically viable for lottery and gaming demonstrations.

For more information, code examples, and deployment addresses, visit the [Randcast Documentation](https://docs.arpanetwork.io/) and [Randcast Playground](https://www.arpanetwork.io/play).
