import { existsSync, mkdirSync, writeFileSync } from "fs";
import { join } from "path";
import hre from "hardhat";
import MWXTModule from "../ignition/modules/MWXT";
import readline from "readline/promises";
import { stdin as input, stdout as output } from "process";

async function main() {
  const signers = await hre.ethers.getSigners();
  const owner = signers[0];
  const node_env = process.env.NODE_ENV || 'dev';
  const chainId = parseInt(await hre.network.provider.send("eth_chainId"), 16);
  const deploymentId = `chain-${chainId}-${node_env}`;

  const rl = readline.createInterface({ input, output });
  const name = await rl.question("Enter the name: ");
  const symbol = await rl.question("Enter the symbol: ");
  const initialSupply = await rl.question("Enter the initial supply: ");
  let initialOwner = await rl.question("Enter the initial owner (default is deployer): ");
  if (!initialOwner || initialOwner == "") {
    initialOwner = owner.address;
  }
  rl.close();

  console.log(`deploying the MWXT.sol`);
  const { mwxt, proxy, implementation } = await hre.ignition.deploy(MWXTModule, {
    deploymentId,
    parameters: {
      MWXTModule: {
        name,
        symbol,
        initialSupply,
        initialOwner
      }
    }
  }); 
  console.log(`success deploying the MWXT.sol\n`);

  const outputJson = {
    proxy: await proxy.getAddress(),
    implementation: await implementation.getAddress(),
    network: process.env.HARDHAT_NETWORK
  };

  const deploymentPath = join(__dirname, 'deployments');
  if (!existsSync(deploymentPath)) {
    mkdirSync(deploymentPath, { recursive: true });
  }
  
  const deploymentDetailsPath = join(deploymentPath, `/deploy_mwxt_output_${process.env.HARDHAT_NETWORK}_${node_env}.json`);
  writeFileSync(deploymentDetailsPath, JSON.stringify(outputJson, null, 2), { encoding: 'utf-8' });
  console.log(`Deployment details saved to ${deploymentDetailsPath}\n`);

  console.log(`success deploy the smart contract!\n`);
  console.log(`trying to verify the smart contract\n\n`);

  console.log(`verifying the MWXT.sol`);
  await hre.run('verify:verify', {
    address: outputJson.implementation,
    constructorArguments: []
  });
  console.log(`success verifying the MWXT.sol\n\n`);

  console.log(`verifying the UUPSUpgradeableProxy.sol`);
  const iface = new hre.ethers.Interface(["function initialize(address, string, string, uint256, address)"])
  const initializeArgument = iface.encodeFunctionData("initialize", [
    name,
    symbol,
    initialSupply,
    initialOwner
  ]); 

  await hre.run('verify:verify', {
    address: outputJson.proxy,
    constructorArguments: [
      outputJson.implementation,
      initializeArgument
    ]
  });
  console.log(`success verifying the UUPSUpgradeableProxy.sol\n\n`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });