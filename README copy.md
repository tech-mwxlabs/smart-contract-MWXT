# MWX Smart Contract Suite

This repository contains the smart contracts and deployment scripts for the MWX ecosystem. The project uses Hardhat, TypeScript, and OpenZeppelin for secure, upgradeable, and well-tested smart contracts.

---

## Table of Contents
- [MWX Smart Contract Suite](#mwx-smart-contract-suite)
  - [Table of Contents](#table-of-contents)
  - [Setup](#setup)
  - [Deployment](#deployment)
    - [MWXT Token](#mwxt-token)
    - [MWXLaunchpad](#mwxlaunchpad)
    - [MWXDisperse](#mwxdisperse)
      - [MWXDisperse Features](#mwxdisperse-features)
      - [Usage Examples](#usage-examples)
    - [MWXStaking](#mwxstaking)
  - [Testing](#testing)
  - [Networks](#networks)
---

## Setup

1. **Install dependencies:**
   ```bash
   npm install
   ```
2. **Configure environment:**
   - Copy `.env.example` to `.env` and set your RPC URLs and private keys for deployment.

---

## Deployment

### MWXT Token
Deploy the MWXT token using Hardhat Ignition:
```bash
npx hardhat run scripts/deployMWXTignition.ts --network <network>
```
You will be prompted for:
- Token name
- Token symbol
- Initial supply
- Initial owner address (default: deployer)

### MWXLaunchpad
Deploy the MWXLaunchpad contract using Hardhat Ignition:
```bash
npx hardhat run scripts/deployMWXLaunchpadIgnition.ts --network <network>
```
You will be prompted for:
- USDT and USDC token addresses (validated and decimals auto-detected)
- Admin verifier address
- Destination address
- Decimals of token sold
- Initial owner (default: deployer)
- Sale parameters (start/end time, price, allocation, caps, etc.)

Deployment details and addresses will be saved in the `scripts/deployments/` directory.

### MWXDisperse
Deploy the MWXDisperse contract for configurable token distribution:
```bash
npx hardhat run scripts/deployMWXDisperse.ts --network <network>
```
You will be prompted for:
- Contract owner address (default: deployer)
- Treasury address (required)
- Percentage configuration in basis points:
  - Treasury percentage (default: 2000 = 20%)
  - Recipient percentage (default: 7000 = 70%)
  - Burn percentage (default: 1000 = 10%)
- Maximum recipients per transaction (default: 100)

**Note:** Percentages must sum to 10000 (100%) in basis points.

#### MWXDisperse Features
The MWXDisperse contract provides configurable token distribution with the following features:
- **Multi-token Support**: Distribute both native ETH and ERC20 tokens
- **Percentage Splits**: Configurable splits between treasury, recipients, and burn
- **Batch Processing**: Distribute to multiple recipients in a single transaction
- **Upgradeable**: Uses OpenZeppelin's UUPS upgradeable pattern
- **Access Control**: Owner-only functions for configuration changes
- **Reentrancy Protection**: Secure against reentrancy attacks
- **Event Logging**: Comprehensive event emission for tracking

#### Usage Examples
```javascript
// Distribute ETH to multiple recipients
await mwxDisperse.disperse(
  ["0x123...", "0x456..."], // recipients
  [ethers.parseEther("1"), ethers.parseEther("2")], // amounts
  ethers.ZeroAddress // ETH
);

// Distribute ERC20 tokens
await mwxDisperse.disperse(
  ["0x123...", "0x456..."], // recipients
  [ethers.parseUnits("100", 18), ethers.parseUnits("200", 18)], // amounts
  "0xTokenAddress" // ERC20 token address
);
```
### MWXStaking
Deploy the MWXStaking contract:
```bash
npx hardhat run scripts/deployMWXStaking.ts --network <network>
```
You will be prompted for:
- Staking token address (validated ERC20 token)
- Reward token address (validated ERC20 token)
- Annual reward pool amount
- Number of years for reward pool (default: 1)

The contract includes:
- Flexible staking (no lock period)
- Locked staking with multipliers (3 months: 1.25x, 6 months: 1.5x, 12 months: 2x)
- Reward distribution based on effective stake amount
- Emergency unstaking (forfeits rewards for locked stakes)

---

## Testing

Run the full test suite with:
```bash
npx hardhat test
```
- MWXT: ERC20, permit, burn, pause, upgradeability, and edge cases
- MWXLaunchpad: Initialization, sale configuration, buying, refunds, access control, upgradeability, and more
- MWXDisperse: Token distribution, percentage splits, treasury management, burn functionality, and access control

Gas usage:
```bash
REPORT_GAS=true npx hardhat test
```

---

## Networks

Configure your networks in `hardhat.config.ts` and `.env` for:
- Localhost
- Base Mainnet
- Base Testnet
