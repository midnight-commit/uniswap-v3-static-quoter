import { abi as QUOTERV2_ABI } from "@uniswap/v3-periphery/artifacts/contracts/lens/QuoterV2.sol/QuoterV2.json";
import { Signer } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";

import { forkNetwork, deployContract, ThenArgRecursive } from "../helpers";
import addresses from "../addresses.json";

const { phar } = addresses.avalanche.protocols;
const { tokens } = addresses.avalanche;

async function fixture() {
  const [deployer] = await ethers.getSigners();
  const quoter = await deployUniswapV3StaticQuoter(deployer);
  return {
    deployer,
    quoter,
  };
}

async function deployUniswapV3StaticQuoter(deployer: Signer) {
  return deployContract(deployer, "PharStaticQuoter", [phar.factory]);
}

async function ethereumFixture(blockNumber: number) {
  await forkNetwork("avalanche", blockNumber);
  return fixture();
}

describe("quoter", async () => {
  context("ethereum", () => {
    context("70351413", async () => {
      let fix: ThenArgRecursive<ReturnType<typeof ethereumFixture>>;

      beforeEach(async () => {
        fix = await ethereumFixture(70351413);
      });

      it("avax .3% usdc: 50 avax", async () => {
        const amountIn = ethers.utils.parseEther("1");

        const params = {
          tokenIn: tokens.avax,
          tokenOut: tokens.usdc,
          amountIn,
          fee: 10,
          sqrtPriceLimitX96: 0,
        };

        // const referenceOut = await fix.reference.callStatic.quoteExactInputSingle(params);
        const quoterOut = await fix.quoter.quoteExactInputSingle(params);

        // expect(quoterOut).equals(referenceOut.amountOut);
        console.log("out %s", quoterOut);
      });
    });
  });
});
