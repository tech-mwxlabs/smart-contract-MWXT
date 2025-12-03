import { ethers } from "hardhat";
import { VestingTimelineHelper, VestingSchedule } from "./helper/vesting-timeline.helper";

async function main() {
    const [deployer] = await ethers.getSigners();
    
    console.log("=== MWX Vesting Timeline Checker ===\n");
    console.log("Deployer address:", deployer.address);

    // Configuration - Update these values
    const VESTING_CONTRACT_ADDRESS = "YOUR_VESTING_CONTRACT_ADDRESS"; // Replace with actual address
    const BENEFICIARY_ADDRESS = "BENEFICIARY_ADDRESS_TO_CHECK"; // Replace with actual beneficiary address

    if (VESTING_CONTRACT_ADDRESS === "YOUR_VESTING_CONTRACT_ADDRESS" || 
        BENEFICIARY_ADDRESS === "BENEFICIARY_ADDRESS_TO_CHECK") {
        console.error("Please update the contract address and beneficiary address in the script");
        process.exit(1);
    }

    try {
        // Get the vesting contract
        const vestingContract = await ethers.getContractAt("MWXVesting", VESTING_CONTRACT_ADDRESS);
        console.log("Vesting contract address:", VESTING_CONTRACT_ADDRESS);
        console.log("Checking timeline for beneficiary:", BENEFICIARY_ADDRESS);
        console.log("=".repeat(60));

        // Get vesting schedule from contract
        const scheduleData = await vestingContract.getVestingSchedule(BENEFICIARY_ADDRESS);
        
        // Convert to our interface format
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

        if (!schedule.isActive) {
            console.log("❌ No active vesting schedule found for this beneficiary");
            return;
        }

        console.log("✅ Active vesting schedule found!");
        console.log("\n📋 Schedule Details:");
        console.log(`   Total Vested Amount: ${ethers.formatEther(schedule.totalVestedAmount)} tokens`);
        console.log(`   Cliff Amount: ${ethers.formatEther(schedule.releaseAmountAtCliff)} tokens`);
        console.log(`   Already Claimed: ${ethers.formatEther(schedule.claimedAmount)} tokens`);
        console.log(`   Start Date: ${new Date(Number(schedule.startTimestamp) * 1000).toISOString()}`);
        console.log(`   Cliff Duration: ${Number(schedule.cliffDuration) / (24 * 3600)} days`);
        console.log(`   Vesting Duration: ${Number(schedule.vestingDuration) / (24 * 3600)} days`);
        console.log(`   Release Interval: ${Number(schedule.releaseInterval) / (24 * 3600)} days`);

        // Calculate and display timeline
        console.log("\n📅 Complete Vesting Timeline:");
        console.log("=".repeat(60));
        
        const timeline = VestingTimelineHelper.calculateVestingTimeline(BENEFICIARY_ADDRESS, schedule);
        VestingTimelineHelper.printTimeline(timeline);

        // Get current status
        console.log("\n📊 Current Status:");
        console.log("=".repeat(60));
        
        const status = VestingTimelineHelper.getCurrentStatus(schedule);
        console.log(`   Is Active: ${status.isActive ? "✅ Yes" : "❌ No"}`);
        console.log(`   Progress: ${status.progress.toFixed(2)}%`);
        console.log(`   Currently Claimable: ${ethers.formatEther(status.currentClaimable)} tokens`);
        console.log(`   Total Claimed: ${ethers.formatEther(status.totalClaimed)} tokens`);
        console.log(`   Remaining Amount: ${ethers.formatEther(status.remainingAmount)} tokens`);
        
        if (status.nextClaim) {
            console.log(`   Next Claim Date: ${status.nextClaim.date}`);
            console.log(`   Next Claim Amount: ${ethers.formatEther(status.nextClaim.amount)} tokens`);
        } else {
            console.log("   Next Claim: No more claims available");
        }

        // Show upcoming milestones
        console.log("\n🎯 Upcoming Milestones:");
        console.log("=".repeat(60));
        
        const now = BigInt(Math.floor(Date.now() / 1000));
        const milestones = [
            { name: "Cliff End", days: Number(schedule.cliffDuration) / (24 * 3600) },
            { name: "25% Vesting", days: Number(schedule.cliffDuration + schedule.vestingDuration * 1n / 4n) / (24 * 3600) },
            { name: "50% Vesting", days: Number(schedule.cliffDuration + schedule.vestingDuration * 2n / 4n) / (24 * 3600) },
            { name: "75% Vesting", days: Number(schedule.cliffDuration + schedule.vestingDuration * 3n / 4n) / (24 * 3600) },
            { name: "100% Vesting", days: Number(schedule.cliffDuration + schedule.vestingDuration) / (24 * 3600) }
        ];

        milestones.forEach(({ name, days }) => {
            const milestoneTime = schedule.startTimestamp + BigInt(Math.floor(days * 24 * 3600));
            const claimable = VestingTimelineHelper.calculateClaimableAmountAt(schedule, milestoneTime);
            const date = new Date(Number(milestoneTime) * 1000).toISOString();
            const isPast = milestoneTime <= now;
            
            console.log(`   ${name}: ${date} ${isPast ? "✅" : "⏳"} (${ethers.formatEther(claimable)} tokens claimable)`);
        });

    } catch (error) {
        console.error("❌ Error checking vesting timeline:", error);
        process.exit(1);
    }
}

// Function to check multiple beneficiaries
async function checkMultipleBeneficiaries() {
    const [deployer] = await ethers.getSigners();
    
    console.log("=== MWX Multiple Beneficiaries Timeline Checker ===\n");
    
    const VESTING_CONTRACT_ADDRESS = "YOUR_VESTING_CONTRACT_ADDRESS"; // Replace with actual address
    const BENEFICIARIES = [
        "BENEFICIARY_1_ADDRESS",
        "BENEFICIARY_2_ADDRESS",
        "BENEFICIARY_3_ADDRESS"
    ]; // Replace with actual addresses

    if (VESTING_CONTRACT_ADDRESS === "YOUR_VESTING_CONTRACT_ADDRESS") {
        console.error("Please update the contract address in the script");
        process.exit(1);
    }

    try {
        const vestingContract = await ethers.getContractAt("MWXVesting", VESTING_CONTRACT_ADDRESS);
        
        for (const beneficiary of BENEFICIARIES) {
            if (beneficiary === "BENEFICIARY_1_ADDRESS") continue; // Skip placeholder addresses
            
            console.log(`\n🔍 Checking beneficiary: ${beneficiary}`);
            console.log("-".repeat(50));
            
            const scheduleData = await vestingContract.getVestingSchedule(beneficiary);
            
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

            if (!schedule.isActive) {
                console.log("❌ No active schedule");
                continue;
            }

            const status = VestingTimelineHelper.getCurrentStatus(schedule);
            const totalAmount = schedule.totalVestedAmount + schedule.releaseAmountAtCliff;
            
            console.log(`✅ Active schedule found`);
            console.log(`   Total Amount: ${ethers.formatEther(totalAmount)} tokens`);
            console.log(`   Progress: ${status.progress.toFixed(2)}%`);
            console.log(`   Claimable: ${ethers.formatEther(status.currentClaimable)} tokens`);
            console.log(`   Claimed: ${ethers.formatEther(status.totalClaimed)} tokens`);
            
            if (status.nextClaim) {
                console.log(`   Next claim: ${status.nextClaim.date} (${ethers.formatEther(status.nextClaim.amount)} tokens)`);
            }
        }
        
    } catch (error) {
        console.error("❌ Error checking multiple beneficiaries:", error);
        process.exit(1);
    }
}

// Run the main function
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

// Uncomment to check multiple beneficiaries
// checkMultipleBeneficiaries()
//     .then(() => process.exit(0))
//     .catch((error) => {
//         console.error(error);
//         process.exit(1);
//     }); 