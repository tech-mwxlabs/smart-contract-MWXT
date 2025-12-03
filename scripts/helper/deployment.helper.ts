import { ethers } from "hardhat";
import readline from "readline/promises";

// ERC20 ABI for validation and getting decimals
const ERC20_ABI = [
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function name() view returns (string)",
  "function totalSupply() view returns (uint256)",
];

/**
 * Validates if the given address is a valid ERC20 token contract
 * @param address - The contract address to validate
 * @returns Promise<boolean> - true if valid ERC20, false otherwise
 */
export async function validateTokenAddress(address: string): Promise<boolean> {
  try {
    // Check if address is valid format
    if (!ethers.isAddress(address)) {
      console.log(`❌ Invalid address format: ${address}`);
      return false;
    }

    // Check if address has contract code
    const code = await ethers.provider.getCode(address);
    if (code === "0x") {
      console.log(`❌ No contract found at address: ${address}`);
      return false;
    }

    // Try to create contract instance and call ERC20 methods
    const contract = new ethers.Contract(address, ERC20_ABI, ethers.provider);

    // Test calling ERC20 methods to ensure it's a valid ERC20 token
    const [decimals, symbol, name] = await Promise.all([
      contract.decimals(),
      contract.symbol(),
      contract.name(),
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
export async function getTokenDecimals(address: string): Promise<number> {
  try {
    const contract = new ethers.Contract(address, ERC20_ABI, ethers.provider);
    const decimals = await contract.decimals();
    return Number(decimals);
  } catch (error: any) {
    throw new Error(
      `Failed to get decimals for token at ${address}: ${error.message}`
    );
  }
}

/**
 * Prompts user for token address and validates it
 * @param rl - Readline interface
 * @param tokenName - Name of the token (e.g., "USDT", "USDC")
 * @returns Promise<string> - Valid token address
 */
export async function getValidatedTokenAddress(
  rl: readline.Interface,
  tokenName: string
): Promise<string> {
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
