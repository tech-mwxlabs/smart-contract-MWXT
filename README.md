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
      - [MWXLaunchpad Features](#mwxlaunchpad-features)
      - [Sale Flow](#sale-flow)
      - [Usage Examples](#usage-examples)
      - [Post-Deployment Configuration](#post-deployment-configuration)
    - [MWXDisperse](#mwxdisperse)
      - [MWXDisperse Features](#mwxdisperse-features)
      - [Usage Examples](#usage-examples-1)
    - [MWXStaking](#mwxstaking)
      - [MWXStaking Features](#mwxstaking-features)
      - [Post-Deployment Steps](#post-deployment-steps)
    - [MWXVesting](#mwxvesting)
      - [MWXVesting Features](#mwxvesting-features)
      - [Vesting Schedule Structure](#vesting-schedule-structure)
      - [Usage Examples](#usage-examples-2)
      - [Access Control](#access-control)
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
Deploy the MWXLaunchpad contract for private token sales with whitelist verification:
```bash
npx hardhat run scripts/deployLaunchpad.ts --network <network>
```
You will be prompted for:
- **USDT Token Address**: USDT payment token (validated with auto-detected decimals)
- **USDC Token Address**: USDC payment token (validated with auto-detected decimals)
- **Admin Verifier Address**: Address that signs whitelist approvals
- **Destination Address**: Address to receive collected funds
- **Token Sold Decimals**: Decimals of the token being sold
- **Initial Owner**: Contract owner (default: deployer address)
- **Sale Parameters**:
  - Start time (epoch timestamp, default: 2 minutes from now)
  - End time (epoch timestamp, default: 30 days from start)
  - Token price (USD with 18 decimals, e.g., 0.06)
  - Total allocation (tokens available for sale)
  - Soft cap (minimum USD to raise)
  - Hard cap (maximum USD to raise)
  - Minimum purchase (minimum USD per transaction)

The deployment script will automatically:
- Configure the sale with provided parameters
- Set up payment token validation
- Display comprehensive deployment summary

#### MWXLaunchpad Features
The MWXLaunchpad contract provides secure private token sales with:
- **Whitelist Verification**: EIP-712 signature-based whitelist system
- **Multi-Payment Support**: Accepts both USDT and USDC payments
- **Flexible Sale Parameters**: Configurable caps, timing, and pricing
- **Real-Time Fund Transfer**: Automatic transfer to destination address
- **Refund Mechanism**: Automatic refunds if soft cap not reached
- **Comprehensive Tracking**: Detailed contribution and allocation history
- **Upgradeable**: Uses OpenZeppelin's UUPS upgradeable pattern
- **Security Features**: Reentrancy protection, pausable functionality, access control

#### Sale Flow
1. **Sale Configuration**: Admin sets sale parameters (timing, pricing, caps)
2. **Whitelist Management**: Admin verifier signs buyer addresses for approval
3. **Token Purchase**: Whitelisted users buy tokens with USDT/USDC
4. **Fund Distribution**: 
   - If soft cap reached: Funds transferred to destination
   - If soft cap not reached: Users can claim refunds
5. **Sale Completion**: Automatic or manual sale ending

#### Usage Examples
```javascript
// Buy allocation (requires whitelist signature)
await mwxLaunchpad.buyAllocation(
  buyerAddress,
  usdtAddress, // or usdcAddress
  ethers.parseUnits("1000", 6), // USD amount
  signature // EIP-712 signature from admin verifier
);

// Check sale status
const status = await mwxLaunchpad.getSaleStatus();
// Returns: { isActive, isEnded, softCapReached, hardCapReached }

// Get user information
const userInfo = await mwxLaunchpad.getUserInfo(userAddress);
// Returns: { contribution, allocation, refundedAmount, canClaimRefund, ... }
```

#### Post-Deployment Configuration
After deployment, update your backend environment:
```bash
SIGNER_PRIVATE_KEY= (private key of Admin verifier address)
LAUNCHPAD_VERSION=1
LAUNCHPAD_CONTRACT_ADDRESS= (contract address of launchpad)
LAUNCHPAD_CHAIN_ID= (chain id of contract address deployed)
LAUNCHPAD_USDC_TOKEN_ADDRESS= (token address of usdc setted in launchpad)
LAUNCHPAD_USDT_TOKEN_ADDRESS= (token address of usdt setted in launchpad)
```

**Important Notes:**
- After deployment, delete and reinsert whitelisted users in admin dashboard (signatures might be cached)
- Ensure admin verifier has sufficient funds for gas fees
- Test whitelist signatures before going live

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
Deploy the MWXStaking contract with its RewardVault dependency:

**Step 1: Deploy RewardVault**
```bash
npx hardhat run scripts/deployRewardVault.ts --network <network>
```
This will deploy the RewardVault contract that manages reward token distribution.

**Step 2: Deploy MWXStaking**
```bash
npx hardhat run scripts/deployMWXStaking.ts --network <network>
```
You will be prompted for:
- **Staking Token Address**: The ERC20 token users will stake (validated with auto-detected decimals)
- **Reward Token Address**: The ERC20 token distributed as rewards (validated with auto-detected decimals)
- **RewardVault Address**: The RewardVault contract address from Step 1 (validated)
- **Reward Pool Amount**: Total tokens allocated for rewards (e.g., 1000000 for 1M tokens)
- **Reward Pool Duration**: Number of years for reward distribution (default: 1)

The deployment script will automatically:
- Set up the connection between MWXStaking and RewardVault
- Configure reward token approvals
- Display default locked staking options

#### MWXStaking Features
The MWXStaking contract provides comprehensive staking functionality:
- **Flexible Staking**: No lock period required for basic staking
- **Locked Staking with Multipliers**: 
  - 3 months: 1.25x multiplier
  - 6 months: 1.5x multiplier  
  - 12 months: 2x multiplier
- **Reward Distribution**: Based on effective stake amount and time
- **Emergency Unstaking**: Available for locked stakes (forfeits rewards)
- **Upgradeable**: Uses OpenZeppelin's UUPS upgradeable pattern
- **Role-Based Access Control**: Secure management functions
- **Reentrancy Protection**: Secure against reentrancy attacks

#### Post-Deployment Steps
After deployment, you need to:
1. **Transfer reward tokens** to the RewardVault contract address
2. **Users can start staking** tokens to earn rewards
3. **RewardVault automatically distributes** rewards to stakers based on their effective stake

### MWXVesting
Deploy the MWXVesting contract for token vesting with configurable schedules:
```bash
npx hardhat run scripts/deployMWXVesting.ts --network <network>
```
You will be prompted for:
- **Vesting Token Address**: The ERC20 token to be vested (validated with auto-detected decimals)
- **Owner Address**: Contract owner (default: deployer address)
- **Schedule Manager Address**: Address with permission to create vesting schedules (default: owner)
- **Batch Limits**: Maximum beneficiaries per batch operation
  - Create vesting schedule batch limit (default: 50)
  - Release batch limit (default: 50)
- **Default Vesting Parameters**:
  - Start timestamp (days from now, default: 1 day)
  - Cliff duration (days, default: 0 for no cliff)
  - Vesting duration (days, default: 365 for 1 year)
  - Release interval (days, default: 30)

#### MWXVesting Features
The MWXVesting contract provides comprehensive token vesting with the following features:
- **Flexible Vesting Schedules**: Support for cliff and linear vesting with configurable intervals
- **Batch Operations**: Create multiple vesting schedules and release tokens in batches
- **Role-Based Access Control**: Separate roles for schedule management and token release
- **Upgradeable**: Uses OpenZeppelin's UUPS upgradeable pattern
- **Comprehensive Security**: Reentrancy protection, pausable functionality, and emergency controls
- **Detailed Tracking**: Complete vesting schedule and claim history tracking
- **Custom Parameters**: Support for both default and custom vesting parameters per beneficiary

#### Vesting Schedule Structure
Each vesting schedule includes:
- **Total Amount**: Total tokens allocated (including cliff amount)
- **Cliff Amount**: Tokens released immediately at cliff
- **Linear Vesting**: Remaining tokens released linearly over time
- **Release Intervals**: Configurable intervals for token releases
- **Claim Tracking**: Automatic tracking of claimed amounts

#### Usage Examples
```javascript
// Create vesting schedules for multiple beneficiaries
await mwxVesting.createVestingSchedule(
  ["0x123...", "0x456..."], // beneficiaries
  [ethers.parseUnits("1000", 18), ethers.parseUnits("2000", 18)], // total amounts
  [ethers.parseUnits("100", 18), ethers.parseUnits("200", 18)] // cliff amounts
);

// Release tokens for a beneficiary
await mwxVesting.release("0x123...");

// Batch release for multiple beneficiaries
await mwxVesting.releaseBatch(["0x123...", "0x456..."]);

// Check releasable amount
const releasable = await mwxVesting.releasableAmount("0x123...");
```

#### Access Control
- **DEFAULT_ADMIN_ROLE**: Can pause/unpause, set vesting token, update batch limits
- **SCHEDULE_MANAGER_ROLE**: Can create vesting schedules and revoke them
- **RELEASER_ROLE**: Can release tokens for beneficiaries

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
