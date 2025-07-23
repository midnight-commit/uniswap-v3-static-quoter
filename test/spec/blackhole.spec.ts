import { abi as QUOTERV2_ABI } from "@uniswap/v3-periphery/artifacts/contracts/lens/QuoterV2.sol/QuoterV2.json";
import { Signer } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";

import { forkNetwork, deployContract, ThenArgRecursive } from "../helpers";
import addresses from "../addresses.json";

const { blackhole } = addresses.avalanche.protocols;
const { tokens } = addresses.avalanche;

async function fixture() {
  const [deployer] = await ethers.getSigners();
  // const reference = await getQuoterV2();

  const quoter = await deployUniswapV3StaticQuoter(deployer);
  return {
    deployer,
    quoter,
  };
}

// async function getQuoterV2() {
//   return ethers.getContractAt(QUOTERV2_ABI, blackhole.quoterV2);
// }

async function deployUniswapV3StaticQuoter(deployer: Signer) {
  // Algebra Integral tick spacing deployers
  const tickSpacingDeployers = [
    "0xDcFccf2e8c4EfBba9127B80eAc76c5A122125d29", // tickSpacing_1
    "0x58b05074D52D1a84D8FfDAddA3c1b652e8C56994", // tickSpacing_50
    "0xf9221dE143A0E57c324bF2a0f281e605e845D767", // tickSpacing_100
    "0x5D433A94A4a2aA8f9AA34D8D15692Dc2E9960584", // tickSpacing_200
  ];

  return deployContract(deployer, "AlgebraIntegralStaticQuoter", [
    blackhole.factory,
    tickSpacingDeployers,
  ]);
}

async function ethereumFixture(blockNumber: number) {
  await forkNetwork("avalanche", blockNumber);
  return fixture();
}

describe("quoter", async () => {
  context("ethereum", () => {
    context("65834026", async () => {
      let fix: ThenArgRecursive<ReturnType<typeof ethereumFixture>>;

      beforeEach(async () => {
        fix = await ethereumFixture(65834026);
      });

      it("avax .3% usdc: 50 avax", async () => {
        const amountIn = ethers.utils.parseEther("1");

        const params = {
          tokenIn: tokens.avax,
          tokenOut: tokens.usdc,
          amountIn,
          fee: 500,
          sqrtPriceLimitX96: 0,
        };

        // const referenceOut =
        //   await fix.reference.callStatic.quoteExactInputSingle(params);
        // expect(referenceOut.amountOut).equals(amountOut);

        const quoterOut = await fix.quoter.quoteExactInputSingle(params);
        console.log("out: %d", quoterOut);
      });

      //   it("avax .3% usdc: 1 wei", async () => {
      //     const amountIn = 1;
      //     const amountOut = 0;

      //     const params = {
      //       tokenIn: tokens.avax,
      //       tokenOut: tokens.usdc,
      //       amountIn,
      //       fee: 250,
      //       sqrtPriceLimitX96: 0,
      //     };

      //     const referenceOut =
      //       await fix.reference.callStatic.quoteExactInputSingle(params);
      //     expect(referenceOut.amountOut).equals(amountOut);

      //     const quoterOut = await fix.quoter.quoteExactInputSingle(params);
      //     expect(quoterOut).equals(amountOut);
      //   });

      //   it("avax .3% usdc: max", async () => {
      //     const params = {
      //       tokenIn: tokens.avax,
      //       tokenOut: tokens.usdc,
      //       amountIn: ethers.constants.MaxUint256,
      //       fee: 250,
      //       sqrtPriceLimitX96: 0,
      //     };

      //     await expect(fix.reference.callStatic.quoteExactInputSingle(params))
      //       .reverted;
      //     await expect(fix.quoter.quoteExactInputSingle(params)).reverted;
      //   });

      //   it("invalid token", async () => {
      //     const params = {
      //       tokenIn: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc3",
      //       tokenOut: tokens.usdc,
      //       amountIn: ethers.utils.parseEther("1337"),
      //       fee: 250,
      //       sqrtPriceLimitX96: 0,
      //     };

      //     await expect(fix.reference.callStatic.quoteExactInputSingle(params))
      //       .reverted;
      //     await expect(fix.quoter.quoteExactInputSingle(params)).reverted;
      //   });
    });
  });
});
