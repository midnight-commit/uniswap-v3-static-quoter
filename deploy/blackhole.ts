import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

import addresses from "../test/addresses.json";

/**
 * Deployment script for Algebra Integral Static Quoter (Blackhole protocol on Avalanche)
 *
 * This script deploys the AlgebraIntegralStaticQuoter contract which provides gas-optimized
 * quotes for swaps against Algebra Integral pools using native Algebra math for perfect accuracy.
 *
 * Usage:
 *   npx hardhat deploy --network avalanche --tags blackhole
 *
 * Requirements:
 *   - Network must be "avalanche"
 *   - Factory address must be configured in test/addresses.json
 *   - All tick spacing deployers must be valid Algebra Integral deployers
 */
const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, log } = deployments;

  const allowedNetworks = ["avalanche"];
  if (!allowedNetworks.includes(network.name))
    throw new Error(`Wrong network! Only "${allowedNetworks}" supported`);

  const networkAddresses: any = Object.entries(addresses).find(
    ([key, _]) => key == network.name
  )?.[1];

  const contractName = "AlgebraIntegralStaticQuoter";

  // Algebra Integral tick spacing deployers for Avalanche (Blackhole protocol)
  // These deployers create pools with different tick spacings for optimal liquidity distribution
  const tickSpacingDeployers = [
    "0xDcFccf2e8c4EfBba9127B80eAc76c5A122125d29", // tickSpacing_1   - Stablecoin pairs
    "0x58b05074D52D1a84D8FfDAddA3c1b652e8C56994", // tickSpacing_50  - Standard pairs
    "0xf9221dE143A0E57c324bF2a0f281e605e845D767", // tickSpacing_100 - Volatile pairs
    "0x5D433A94A4a2aA8f9AA34D8D15692Dc2E9960584", // tickSpacing_200 - Most volatile pairs
  ];

  const args = [
    networkAddresses.protocols.blackhole.factory,
    tickSpacingDeployers,
  ];

  const { deployer } = await getNamedAccounts();

  log("🚀 Deploying Algebra Integral Static Quoter (Blackhole Protocol)");
  log(`   Network: ${network.name}`);
  log(`   Deployer: ${deployer}`);
  log("");

  const deployResult: any = await deploy(contractName, {
    from: deployer,
    contract: contractName,
    skipIfAlreadyDeployed: true,
    log: true,
    args,
  });

  if (deployResult.newlyDeployed) {
    log("");
    log(`🎉 Successfully deployed Algebra Integral Static Quoter!`);
    log(`📍 Contract Address: ${deployResult.address}`);
    log(`🏭 Factory Address: ${networkAddresses.protocols.blackhole.factory}`);
    log(
      `⚙️  Tick Spacing Deployers: ${tickSpacingDeployers.length} configured`
    );
    log("");
    log("✅ Features:");
    log("   • Perfect accuracy matching official Algebra QuoterV2");
    log("   • Gas-optimized for on-chain aggregator usage");
    log("   • Multi-pool liquidity discovery across all tick spacings");
    log("   • Native Algebra PriceMovementMath for mathematical precision");
    log("");
    log("🔗 Ready for integration with DEX aggregators!");
  } else {
    log(
      `⏩ Deployment skipped, using previous deployment at: ${deployResult.address}`
    );
  }
};

export default func;
func.tags = ["blackhole", "algebra-integral"];
