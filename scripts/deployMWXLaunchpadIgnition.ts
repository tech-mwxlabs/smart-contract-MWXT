import { existsSync, mkdirSync, writeFileSync } from "fs";
import { join } from "path";
import hre from "hardhat";
import MWXLaunchpadModule from "../ignition/modules/MWXLaunchpad";
import readline from "readline/promises";
import { stdin as input, stdout as output } from "process";
import { parseUnits } from "ethers";

// ERC20 ABI for validation and getting decimals
const ERC20_ABI = [
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function name() view returns (string)",
  "function totalSupply() view returns (uint256)"
];

/**
 * Validates if the given address is a valid ERC20 token contract
 * @param address - The contract address to validate
 * @returns Promise<boolean> - true if valid ERC20, false otherwise
 */
async function validateTokenAddress(address: string): Promise<boolean> {
  try {
    // Check if address is valid format
    if (!hre.ethers.isAddress(address)) {
      console.log(`❌ Invalid address format: ${address}`);
      return false;
    }

    // Check if address has contract code
    const code = await hre.ethers.provider.getCode(address);
    if (code === "0x") {
      console.log(`❌ No contract found at address: ${address}`);
      return false;
    }

    // Try to create contract instance and call ERC20 methods
    const contract = new hre.ethers.Contract(address, ERC20_ABI, hre.ethers.provider);
    
    // Test calling ERC20 methods to ensure it's a valid ERC20 token
    const [decimals, symbol, name] = await Promise.all([
      contract.decimals(),
      contract.symbol(),
      contract.name()
    ]);

    console.log(`✅ Valid ERC20 token found:`);
    console.log(`   Name: ${name}`);
    console.log(`   Symbol: ${symbol}`);
    console.log(`   Decimals: ${decimals}`);
    
    return true;
  } catch (error: any) {
    console.log(`❌ Invalid ERC20 token at ${address}:`, error.message);
    return false;
  }
}

/**
 * Gets the decimal value of an ERC20 token
 * @param address - The token contract address
 * @returns Promise<number> - The decimal value of the token
 */
async function getTokenDecimals(address: string): Promise<number> {
  try {
    const contract = new hre.ethers.Contract(address, ERC20_ABI, hre.ethers.provider);
    const decimals = await contract.decimals();
    return Number(decimals);
  } catch (error: any) {
    throw new Error(`Failed to get decimals for token at ${address}: ${error.message}`);
  }
}

/**
 * Prompts user for token address and validates it
 * @param rl - Readline interface
 * @param tokenName - Name of the token (e.g., "USDT", "USDC")
 * @returns Promise<string> - Valid token address
 */
async function getValidatedTokenAddress(rl: readline.Interface, tokenName: string): Promise<string> {
  while (true) {
    const address = await rl.question(`Enter the ${tokenName} address: `);
    console.log(`\n🔍 Validating ${tokenName} address...`);
    
    const isValid = await validateTokenAddress(address);
    if (isValid) {
      console.log(`✅ ${tokenName} address validated successfully!\n`);
      return address;
    } else {
      console.log(`❌ Please enter a valid ${tokenName} address.\n`);
    }
  }
}

async function main() {
  const signers = await hre.ethers.getSigners();
  const owner = signers[0];
  const node_env = process.env.NODE_ENV || 'dev';
  const chainId = parseInt(await hre.network.provider.send("eth_chainId"), 16);
  const deploymentId = `chain-${chainId}-${node_env}`;

  console.log(`🚀 Starting MWX Launchpad deployment on network: ${process.env.HARDHAT_NETWORK}`);
  console.log(`📋 Deployment ID: ${deploymentId}\n`);

  const rl = readline.createInterface({ input, output });
  
  // Get and validate USDT address
  const usdt = await getValidatedTokenAddress(rl, "USDT");
  const usdtDecimals = await getTokenDecimals(usdt);
  console.log(`📊 USDT decimals: ${usdtDecimals}\n`);
  
  // Get and validate USDC address
  const usdc = await getValidatedTokenAddress(rl, "USDC");
  const usdcDecimals = await getTokenDecimals(usdc);
  console.log(`📊 USDC decimals: ${usdcDecimals}\n`);
  
  const adminVerifier = await rl.question("Enter the admin verifier address: ");
  const destinationAddress = await rl.question("Enter the destination address: ");
  const decimalTokenSold = await rl.question("Enter the decimal of token sold: ");
  let initialOwner = await rl.question("Enter the initial owner (default is deployer): ");
  if (!initialOwner || initialOwner == "") {
    initialOwner = owner.address;
  }
  const startTime = await rl.question("Enter the start time (epoch time in seconds): ");
  const endTime = await rl.question("Enter the end time (epoch time in seconds): ");
  const tokenPrice = parseUnits(await rl.question("Enter the token price: "), 18);
  const totalAllocation = parseUnits(await rl.question("Enter the total allocation: "), 18);
  
  // Use appropriate decimals for soft cap and hard cap based on payment tokens
  console.log(`\n💡 Note: Using ${usdtDecimals} decimals for soft cap and hard cap (based on USDT/USDC decimals)`);
  const softCap = parseUnits(await rl.question("Enter the soft cap: "), usdtDecimals);
  const hardCap = parseUnits(await rl.question("Enter the hard cap: "), usdtDecimals);
  const minimumPurchase = parseUnits(await rl.question("Enter the minimum purchase: "), usdtDecimals);
  rl.close();

  console.log(`\n📋 Deployment Summary:`);
  console.log(`   USDT: ${usdt} (${usdtDecimals} decimals)`);
  console.log(`   USDC: ${usdc} (${usdcDecimals} decimals)`);
  console.log(`   Initial Owner: ${initialOwner}`);
  console.log(`   Admin Verifier: ${adminVerifier}`);
  console.log(`   Destination: ${destinationAddress}`);
  console.log(`   Token Sold Decimals: ${decimalTokenSold}`);
  console.log(`   Start Time: ${startTime}`);
  console.log(`   End Time: ${endTime}`);
  console.log(`   Token Price: ${tokenPrice.toString()}`);
  console.log(`   Total Allocation: ${totalAllocation.toString()}`);
  console.log(`   Soft Cap: ${softCap.toString()}`);
  console.log(`   Hard Cap: ${hardCap.toString()}`);
  console.log(`   Minimum Purchase: ${minimumPurchase.toString()}\n`);

  console.log(`🔨 Deploying the MWXLaunchpad.sol...`);
  const { mwxLaunchpad, proxy, implementation } = await hre.ignition.deploy(MWXLaunchpadModule, {
    deploymentId,
    parameters: {
      MWXLaunchpadModule: {
        usdt,
        usdc,
        initialOwner,
        adminVerifier,
        destinationAddress,
        decimalTokenSold,
        startTime,
        endTime,
        tokenPrice,
        totalAllocation,
        softCap,
        hardCap,
        minimumPurchase,
      }
    }
  }); 
  console.log(`✅ Success deploying the MWXLaunchpad.sol\n`);

  const outputJson = {
    proxy: await proxy.getAddress(),
    implementation: await implementation.getAddress(),
    network: process.env.HARDHAT_NETWORK,
    usdt: {
      address: usdt,
      decimals: usdtDecimals
    },
    usdc: {
      address: usdc,
      decimals: usdcDecimals
    },
    deploymentParameters: {
      initialOwner,
      adminVerifier,
      destinationAddress,
      decimalTokenSold,
      startTime,
      endTime,
      tokenPrice: tokenPrice.toString(),
      totalAllocation: totalAllocation.toString(),
      softCap: softCap.toString(),
      hardCap: hardCap.toString(),
      minimumPurchase: minimumPurchase.toString()
    }
  };

  const deploymentPath = join(__dirname, 'deployments');
  if (!existsSync(deploymentPath)) {
    mkdirSync(deploymentPath, { recursive: true });
  }
  
  const deploymentDetailsPath = join(deploymentPath, `/deploy_mwx_launchpad_output_${process.env.HARDHAT_NETWORK}_${node_env}.json`);
  writeFileSync(deploymentDetailsPath, JSON.stringify(outputJson, null, 2), { encoding: 'utf-8' });
  console.log(`Deployment details saved to ${deploymentDetailsPath}\n`);

  console.log(`🎉 Success deploy the smart contract!\n`);
  console.log(`🔍 Trying to verify the smart contract\n\n`);

  console.log(`📝 Verifying the MWXLaunchpad.sol...`);
  await hre.run('verify:verify', {
    address: outputJson.implementation,
    constructorArguments: []
  });
  console.log(`✅ Success verifying the MWXLaunchpad.sol\n\n`);

  console.log(`📝 Verifying the UUPSUpgradeableProxy.sol...`);
  const iface = new hre.ethers.Interface(["function initialize(address, address, address, address, address, uint8)"])
  const initializeArgument = iface.encodeFunctionData("initialize", [
    usdt,
    usdc,
    initialOwner,
    adminVerifier,
    destinationAddress,
    decimalTokenSold,
  ]);

  await hre.run('verify:verify', {
    address: outputJson.proxy,
    constructorArguments: [
      outputJson.implementation,
      initializeArgument
    ]
  });
  console.log(`✅ Success verifying the UUPSUpgradeableProxy.sol\n\n`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });