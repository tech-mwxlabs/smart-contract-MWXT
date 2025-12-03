import { ethers } from "hardhat";

export interface VestingSchedule {
    totalVestedAmount: bigint;
    releaseAmountAtCliff: bigint;
    claimedAmount: bigint;
    startTimestamp: bigint;
    cliffDuration: bigint;
    vestingDuration: bigint;
    releaseInterval: bigint;
    isActive: boolean;
}

export interface VestingTimelineEvent {
    timestamp: bigint;
    date: string;
    event: string;
    claimableAmount: bigint;
    cumulativeClaimed: bigint;
    remainingAmount: bigint;
}

export interface VestingTimeline {
    beneficiary: string;
    schedule: VestingSchedule;
    timeline: VestingTimelineEvent[];
    summary: {
        totalAmount: bigint;
        cliffAmount: bigint;
        linearVestingAmount: bigint;
        totalIntervals: number;
        vestingEndDate: string;
        fullyVestedDate: string;
    };
}

export class VestingTimelineHelper {
    private static readonly SECONDS_PER_DAY = 86400n;

    /**
     * Calculate the complete vesting timeline for a beneficiary
     * @param beneficiary The beneficiary address
     * @param schedule The vesting schedule data
     * @returns Complete timeline with all claim events
     */
    static calculateVestingTimeline(beneficiary: string, schedule: VestingSchedule): VestingTimeline {
        if (!schedule.isActive) {
            throw new Error("Vesting schedule is not active");
        }

        const timeline: VestingTimelineEvent[] = [];
        const totalAmount = schedule.totalVestedAmount + schedule.releaseAmountAtCliff;
        let cumulativeClaimed = 0n;

        // Calculate key timestamps
        const cliffEndTime = schedule.startTimestamp + schedule.cliffDuration;
        const vestingEndTime = cliffEndTime + schedule.vestingDuration;
        const totalIntervals = Number((schedule.vestingDuration + schedule.releaseInterval - 1n) / schedule.releaseInterval);

        // Add start event
        timeline.push({
            timestamp: schedule.startTimestamp,
            date: this.formatDate(schedule.startTimestamp),
            event: "Vesting Started",
            claimableAmount: 0n,
            cumulativeClaimed: 0n,
            remainingAmount: totalAmount
        });

        // Add cliff event if there's a cliff amount
        if (schedule.releaseAmountAtCliff > 0n) {
            timeline.push({
                timestamp: cliffEndTime,
                date: this.formatDate(cliffEndTime),
                event: "Cliff Period Ended - Cliff Amount Available",
                claimableAmount: schedule.releaseAmountAtCliff,
                cumulativeClaimed: 0n,
                remainingAmount: totalAmount - schedule.releaseAmountAtCliff
            });
            cumulativeClaimed = schedule.releaseAmountAtCliff;
        }

        // Calculate linear vesting events
        for (let interval = 1; interval <= totalIntervals; interval++) {
            const intervalEndTime = cliffEndTime + (BigInt(interval) * schedule.releaseInterval);
            
            // Calculate vested amount for this interval
            const vestedAmount = (schedule.totalVestedAmount * BigInt(interval)) / BigInt(totalIntervals);
            const previousVestedAmount = (schedule.totalVestedAmount * BigInt(interval - 1)) / BigInt(totalIntervals);
            const intervalClaimable = vestedAmount - previousVestedAmount;

            if (intervalClaimable > 0n) {
                cumulativeClaimed = schedule.releaseAmountAtCliff + vestedAmount;
                const remainingAmount = totalAmount - cumulativeClaimed;

                timeline.push({
                    timestamp: intervalEndTime,
                    date: this.formatDate(intervalEndTime),
                    event: `Interval ${interval}/${totalIntervals} - Linear Vesting`,
                    claimableAmount: intervalClaimable,
                    cumulativeClaimed: cumulativeClaimed,
                    remainingAmount: remainingAmount
                });
            }
        }

        // Add final vesting completion event
        timeline.push({
            timestamp: vestingEndTime,
            date: this.formatDate(vestingEndTime),
            event: "Vesting Fully Completed",
            claimableAmount: totalAmount - cumulativeClaimed,
            cumulativeClaimed: totalAmount,
            remainingAmount: 0n
        });

        return {
            beneficiary,
            schedule,
            timeline,
            summary: {
                totalAmount,
                cliffAmount: schedule.releaseAmountAtCliff,
                linearVestingAmount: schedule.totalVestedAmount,
                totalIntervals,
                vestingEndDate: this.formatDate(vestingEndTime),
                fullyVestedDate: this.formatDate(vestingEndTime)
            }
        };
    }

    /**
     * Calculate claimable amount at a specific timestamp
     * @param schedule The vesting schedule
     * @param timestamp The timestamp to check
     * @returns The claimable amount at that timestamp
     */
    static calculateClaimableAmountAt(schedule: VestingSchedule, timestamp: bigint): bigint {
        if (!schedule.isActive) return 0n;
        if (timestamp < schedule.startTimestamp) return 0n;
        if (timestamp < schedule.startTimestamp + schedule.cliffDuration) return 0n;

        const elapsedTime = timestamp - schedule.startTimestamp;
        let cliffClaimable = 0n;

        // At or after cliff, release cliff amount if not claimed
        if (elapsedTime >= schedule.cliffDuration) {
            if (schedule.releaseAmountAtCliff > 0n && schedule.claimedAmount < schedule.releaseAmountAtCliff) {
                cliffClaimable = schedule.releaseAmountAtCliff - schedule.claimedAmount;
            }
        }

        // Only calculate linear vesting after cliff
        const timeAfterCliff = elapsedTime - schedule.cliffDuration;

        // After vesting duration, release all vested amount
        if (timeAfterCliff >= schedule.vestingDuration) {
            return (schedule.totalVestedAmount + schedule.releaseAmountAtCliff) - schedule.claimedAmount;
        }

        // Calculate total intervals based on vesting duration only
        const totalIntervals = (schedule.vestingDuration + schedule.releaseInterval - 1n) / schedule.releaseInterval;
        let completedIntervals = timeAfterCliff / schedule.releaseInterval;

        // Ensure we don't exceed total intervals - 1 (last interval only claimable at end)
        if (completedIntervals >= totalIntervals) {
            completedIntervals = totalIntervals - 1n;
        }

        // Calculate vested amount
        let vestingClaimable = 0n;
        const vestedAmount = (schedule.totalVestedAmount * completedIntervals) / totalIntervals;
        const vestingClaimed = schedule.claimedAmount > schedule.releaseAmountAtCliff ? 
            schedule.claimedAmount - schedule.releaseAmountAtCliff : 0n;

        if (vestedAmount > vestingClaimed) {
            vestingClaimable = vestedAmount - vestingClaimed;
        }

        const totalClaimable = cliffClaimable + vestingClaimable;

        // Cap claimable to total allocation minus already claimed
        const totalAmount = schedule.totalVestedAmount + schedule.releaseAmountAtCliff;
        if (totalClaimable + schedule.claimedAmount > totalAmount) {
            return totalAmount - schedule.claimedAmount;
        }

        return totalClaimable;
    }

    /**
     * Get next claim date for a beneficiary
     * @param schedule The vesting schedule
     * @param currentTimestamp Current timestamp (defaults to current time)
     * @returns Next claim date or null if no more claims
     */
    static getNextClaimDate(schedule: VestingSchedule, currentTimestamp?: bigint): { timestamp: bigint; date: string; amount: bigint } | null {
        const now = currentTimestamp || BigInt(Math.floor(Date.now() / 1000));
        
        if (!schedule.isActive || now < schedule.startTimestamp) {
            return null;
        }

        const cliffEndTime = schedule.startTimestamp + schedule.cliffDuration;
        
        // If before cliff and there's a cliff amount, next claim is at cliff
        if (now < cliffEndTime && schedule.releaseAmountAtCliff > 0n) {
            return {
                timestamp: cliffEndTime,
                date: this.formatDate(cliffEndTime),
                amount: schedule.releaseAmountAtCliff
            };
        }

        // If after cliff, calculate next interval
        if (now >= cliffEndTime) {
            const timeAfterCliff = now - cliffEndTime;
            const totalIntervals = (schedule.vestingDuration + schedule.releaseInterval - 1n) / schedule.releaseInterval;
            const currentInterval = timeAfterCliff / schedule.releaseInterval;
            
            if (currentInterval < totalIntervals) {
                const nextIntervalTime = cliffEndTime + ((currentInterval + 1n) * schedule.releaseInterval);
                const nextVestedAmount = (schedule.totalVestedAmount * (currentInterval + 1n)) / totalIntervals;
                const currentVestedAmount = (schedule.totalVestedAmount * currentInterval) / totalIntervals;
                const nextAmount = nextVestedAmount - currentVestedAmount;

                if (nextAmount > 0n) {
                    return {
                        timestamp: nextIntervalTime,
                        date: this.formatDate(nextIntervalTime),
                        amount: nextAmount
                    };
                }
            }
        }

        return null;
    }

    /**
     * Get vesting progress percentage
     * @param schedule The vesting schedule
     * @param currentTimestamp Current timestamp (defaults to current time)
     * @returns Progress percentage (0-100)
     */
    static getVestingProgress(schedule: VestingSchedule, currentTimestamp?: bigint): number {
        const now = currentTimestamp || BigInt(Math.floor(Date.now() / 1000));
        
        if (!schedule.isActive || now < schedule.startTimestamp) {
            return 0;
        }

        const cliffEndTime = schedule.startTimestamp + schedule.cliffDuration;
        
        // Before cliff
        if (now < cliffEndTime) {
            return 0;
        }

        // After vesting completion
        const vestingEndTime = cliffEndTime + schedule.vestingDuration;
        if (now >= vestingEndTime) {
            return 100;
        }

        // During linear vesting
        const timeAfterCliff = now - cliffEndTime;
        const progress = Number((timeAfterCliff * 100n) / schedule.vestingDuration);
        
        return Math.min(progress, 100);
    }

    /**
     * Format timestamp to readable date
     * @param timestamp Unix timestamp
     * @returns Formatted date string
     */
    private static formatDate(timestamp: bigint): string {
        const date = new Date(Number(timestamp) * 1000);
        return date.toISOString();
    }

    /**
     * Print timeline in a readable format
     * @param timeline The vesting timeline
     */
    static printTimeline(timeline: VestingTimeline): void {
        console.log(`\n=== Vesting Timeline for ${timeline.beneficiary} ===`);
        console.log(`Total Amount: ${ethers.formatEther(timeline.summary.totalAmount)} tokens`);
        console.log(`Cliff Amount: ${ethers.formatEther(timeline.summary.cliffAmount)} tokens`);
        console.log(`Linear Vesting Amount: ${ethers.formatEther(timeline.summary.linearVestingAmount)} tokens`);
        console.log(`Total Intervals: ${timeline.summary.totalIntervals}`);
        console.log(`Vesting End Date: ${timeline.summary.vestingEndDate}`);
        console.log("\nTimeline Events:");
        console.log("=".repeat(100));
        
        timeline.timeline.forEach((event, index) => {
            console.log(`${index + 1}. ${event.date}`);
            console.log(`   Event: ${event.event}`);
            console.log(`   Claimable: ${ethers.formatEther(event.claimableAmount)} tokens`);
            console.log(`   Cumulative Claimed: ${ethers.formatEther(event.cumulativeClaimed)} tokens`);
            console.log(`   Remaining: ${ethers.formatEther(event.remainingAmount)} tokens`);
            console.log("-".repeat(50));
        });
    }

    /**
     * Get current vesting status
     * @param schedule The vesting schedule
     * @param currentTimestamp Current timestamp (defaults to current time)
     * @returns Current status information
     */
    static getCurrentStatus(schedule: VestingSchedule, currentTimestamp?: bigint): {
        isActive: boolean;
        progress: number;
        currentClaimable: bigint;
        nextClaim: { timestamp: bigint; date: string; amount: bigint } | null;
        totalClaimed: bigint;
        remainingAmount: bigint;
    } {
        const now = currentTimestamp || BigInt(Math.floor(Date.now() / 1000));
        const currentClaimable = this.calculateClaimableAmountAt(schedule, now);
        const nextClaim = this.getNextClaimDate(schedule, now);
        const progress = this.getVestingProgress(schedule, now);
        const totalAmount = schedule.totalVestedAmount + schedule.releaseAmountAtCliff;
        const remainingAmount = totalAmount - schedule.claimedAmount;

        return {
            isActive: schedule.isActive,
            progress,
            currentClaimable,
            nextClaim,
            totalClaimed: schedule.claimedAmount,
            remainingAmount
        };
    }
} 