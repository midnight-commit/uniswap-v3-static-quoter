import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

import addresses from "../test/addresses.json";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, log } = deployments;

  const allowedNetworks = ["avalanche"];
  if (!allowedNetworks.includes(network.name))
    throw new Error(`Wrong network! Only "${allowedNetworks}" supported`);

  const contractName = "PangolinV3StaticQuoter";
  let factory;
  switch (network.name) {
    case "avalanche":
      factory = addresses.avalanche.protocols.pangolin.factory;
      break;
    default:
      factory = addresses.avalanche.protocols.pangolin.factory;
      break;
  }
  const args = [factory];
  const { deployer } = await getNamedAccounts();

  log("1) Deploy contract");
  const deployResult: any = await deploy(contractName, {
    from: deployer,
    contract: contractName,
    skipIfAlreadyDeployed: true,
    log: true,
    args,
  });

  if (deployResult.newlyDeployed)
    log(`- 🎉 Deployed at: ${deployResult.address}`);
  else
    log(
      `- ⏩ Deployment skipped, using previous deployment at: ${deployResult.address}`
    );
};

export default func;
func.tags = ["pangolinV3"];
