# MWX Vesting Timeline Helper

This helper provides comprehensive tools to calculate and visualize vesting timelines for the MWX Vesting contract.

## Overview

The `VestingTimelineHelper` class implements the same logic as the smart contract's `_calculateReleasableAmount` function, allowing you to:

- Calculate complete vesting timelines
- Determine claimable amounts at any point in time
- Track vesting progress
- Find next claim dates
- Get current vesting status

## Features

### 1. Complete Timeline Calculation
Calculate the full vesting timeline including:
- Vesting start date
- Cliff period and cliff amount release
- Linear vesting intervals
- Final vesting completion

### 2. Current Status Analysis
Get real-time information about:
- Current claimable amount
- Vesting progress percentage
- Next claim date and amount
- Total claimed and remaining amounts

### 3. Progress Tracking
Monitor vesting progress over time with percentage calculations.

### 4. Multi-Beneficiary Support
Check timelines for multiple beneficiaries efficiently.

## Usage

### Basic Usage

```typescript
import { VestingTimelineHelper, VestingSchedule } from "./helper/vesting-timeline.helper";

// Create a vesting schedule object
const schedule: VestingSchedule = {
    totalVestedAmount: ethers.parseEther("1000"), // 1000 tokens for linear vesting
    releaseAmountAtCliff: ethers.parseEther("100"), // 100 tokens at cliff
    claimedAmount: ethers.parseEther("50"), // 50 tokens already claimed
    startTimestamp: BigInt(Math.floor(Date.now() / 1000)), // Start now
    cliffDuration: 30n * 24n * 3600n, // 30 days cliff
    vestingDuration: 365n * 24n * 3600n, // 1 year vesting
    releaseInterval: 30n * 24n * 3600n, // 30 days intervals
    isActive: true
};

// Calculate complete timeline
const timeline = VestingTimelineHelper.calculateVestingTimeline(beneficiary, schedule);

// Print timeline
VestingTimelineHelper.printTimeline(timeline);

// Get current status
const status = VestingTimelineHelper.getCurrentStatus(schedule);
console.log(`Progress: ${status.progress.toFixed(2)}%`);
console.log(`Claimable: ${ethers.formatEther(status.currentClaimable)} tokens`);
```

### With Contract Data

```typescript
// Get vesting contract
const vestingContract = await ethers.getContractAt("MWXVesting", contractAddress);

// Get schedule data from contract
const scheduleData = await vestingContract.getVestingSchedule(beneficiaryAddress);

// Convert to helper format
const schedule: VestingSchedule = {
    totalVestedAmount: scheduleData[0],
    releaseAmountAtCliff: scheduleData[1],
    claimedAmount: scheduleData[2],
    startTimestamp: scheduleData[3],
    cliffDuration: scheduleData[4],
    vestingDuration: scheduleData[5],
    releaseInterval: scheduleData[6],
    isActive: scheduleData[7]
};

// Use helper functions
const timeline = VestingTimelineHelper.calculateVestingTimeline(beneficiaryAddress, schedule);
```

## Available Methods

### `calculateVestingTimeline(beneficiary, schedule)`
Calculates the complete vesting timeline with all claim events.

**Returns:** `VestingTimeline` object with timeline events and summary.

### `calculateClaimableAmountAt(schedule, timestamp)`
Calculates the claimable amount at a specific timestamp.

**Returns:** `bigint` representing claimable tokens.

### `getCurrentStatus(schedule, currentTimestamp?)`
Gets the current vesting status.

**Returns:** Object with progress, claimable amount, next claim info, etc.

### `getNextClaimDate(schedule, currentTimestamp?)`
Finds the next claim date and amount.

**Returns:** Next claim info or null if no more claims.

### `getVestingProgress(schedule, currentTimestamp?)`
Calculates vesting progress as a percentage.

**Returns:** Number between 0-100.

### `printTimeline(timeline)`
Prints a formatted timeline to console.

## Running the Scripts

### Example Script
```bash
npx hardhat run scripts/vesting-timeline-example.ts
```

### Check Specific Beneficiary
```bash
# Update the script with contract and beneficiary addresses first
npx hardhat run scripts/check-vesting-timeline.ts
```

## Vesting Logic

The helper implements the exact same logic as the smart contract:

1. **Cliff Period**: No tokens claimable until cliff duration passes
2. **Cliff Release**: At cliff, `releaseAmountAtCliff` becomes available
3. **Linear Vesting**: After cliff, tokens vest linearly over intervals
4. **Total Intervals**: `(vestingDuration + releaseInterval - 1) / releaseInterval`
5. **Vesting Amount**: `(totalVestedAmount * completedIntervals) / totalIntervals`

## Data Structures

### VestingSchedule
```typescript
interface VestingSchedule {
    totalVestedAmount: bigint;      // Tokens for linear vesting after cliff
    releaseAmountAtCliff: bigint;   // Tokens released at cliff
    claimedAmount: bigint;          // Already claimed tokens
    startTimestamp: bigint;         // Vesting start time
    cliffDuration: bigint;          // Cliff period in seconds
    vestingDuration: bigint;        // Linear vesting duration in seconds
    releaseInterval: bigint;        // Release interval in seconds
    isActive: boolean;              // Whether schedule is active
}
```

### VestingTimelineEvent
```typescript
interface VestingTimelineEvent {
    timestamp: bigint;              // Event timestamp
    date: string;                   // Formatted date
    event: string;                  // Event description
    claimableAmount: bigint;        // Tokens claimable at this event
    cumulativeClaimed: bigint;      // Total claimed up to this point
    remainingAmount: bigint;        // Remaining tokens after this event
}
```

## Error Handling

The helper includes proper error handling for:
- Inactive vesting schedules
- Invalid timestamps
- Missing contract data
- Network connection issues

## Examples

See the following files for complete examples:
- `scripts/vesting-timeline-example.ts` - Basic usage examples
- `scripts/check-vesting-timeline.ts` - Practical beneficiary checking 