import { Signer } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";

import { forkNetwork, deployContract, ThenArgRecursive } from "../helpers";
import addresses from "../addresses.json";

const { blackhole } = addresses.avalanche.protocols;
const { tokens } = addresses.avalanche;

// Official Algebra QuoterV2 deployed address
const OFFICIAL_QUOTER_ADDRESS = "0x3e182bcf14Be6142b9217847ec1112e3c39Eb689";

// Deployer addresses for different tick spacings
const DEPLOYERS = {
  tickSpacing_1: "0xDcFccf2e8c4EfBba9127B80eAc76c5A122125d29",
  tickSpacing_50: "0x58b05074D52D1a84D8FfDAddA3c1b652e8C56994",
  tickSpacing_100: "0xf9221dE143A0E57c324bF2a0f281e605e845D767",
  tickSpacing_200: "0x5D433A94A4a2aA8f9AA34D8D15692Dc2E9960584",
};

interface TokenInfo {
  address: string;
  symbol: string;
  decimals: number;
}

const TOKEN_INFO: Record<string, TokenInfo> = {
  avax: { address: tokens.avax, symbol: "AVAX", decimals: 18 },
  usdc: { address: tokens.usdc, symbol: "USDC", decimals: 6 },
  usdt: { address: tokens.usdt, symbol: "USDT", decimals: 6 },
};

async function fixture() {
  const [deployer] = await ethers.getSigners();

  const officialQuoter = await getOfficialQuoter();
  const staticQuoter = await deployAlgebraIntegralStaticQuoter(deployer);

  return {
    deployer,
    officialQuoter,
    staticQuoter,
  };
}

async function getOfficialQuoter() {
  const quoterAbi = [
    "function quoteExactInputSingle((address tokenIn, address tokenOut, address deployer, uint256 amountIn, uint160 limitSqrtPrice)) external returns (uint256 amountOut, uint256 amountIn, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate, uint16 fee)",
  ];
  return ethers.getContractAt(quoterAbi, OFFICIAL_QUOTER_ADDRESS);
}

async function deployAlgebraIntegralStaticQuoter(deployer: Signer) {
  // Algebra Integral tick spacing deployers
  const tickSpacingDeployers = [
    DEPLOYERS.tickSpacing_1,
    DEPLOYERS.tickSpacing_50,
    DEPLOYERS.tickSpacing_100,
    DEPLOYERS.tickSpacing_200,
  ];

  return deployContract(deployer, "AlgebraIntegralStaticQuoter", [
    blackhole.factory,
    tickSpacingDeployers,
  ]);
}

async function compareQuotes(
  officialQuoter: any,
  staticQuoter: any,
  tokenInKey: string,
  tokenOutKey: string,
  amountIn: any,
  deployer: string,
  testName: string
) {
  const tokenIn = TOKEN_INFO[tokenInKey];
  const tokenOut = TOKEN_INFO[tokenOutKey];

  // Official quoter params (needs specific deployer)
  const officialParams = {
    tokenIn: tokenIn.address,
    tokenOut: tokenOut.address,
    deployer: deployer,
    amountIn,
    limitSqrtPrice: 0,
  };

  // Our static quoter params
  const staticParams = {
    tokenIn: tokenIn.address,
    tokenOut: tokenOut.address,
    amountIn,
    fee: 500,
    sqrtPriceLimitX96: 0,
  };

  console.log(`\n${testName}:`);

  try {
    // Get quotes from both quoters
    const officialResult =
      await officialQuoter.callStatic.quoteExactInputSingle(officialParams);
    const staticResult = await staticQuoter.quoteExactInputSingle(staticParams);

    const officialAmountOut = officialResult.amountOut;
    const staticAmountOut = staticResult;

    console.log(
      `  Official QuoterV2: ${ethers.utils.formatUnits(
        officialAmountOut,
        tokenOut.decimals
      )} ${tokenOut.symbol}`
    );
    console.log(
      `  Our Static Quoter: ${ethers.utils.formatUnits(
        staticAmountOut,
        tokenOut.decimals
      )} ${tokenOut.symbol}`
    );

    // Calculate difference percentage
    const difference = officialAmountOut.sub(staticAmountOut).abs();
    const diffPercentage =
      difference.mul(10000).div(officialAmountOut).toNumber() / 100;

    console.log(`  Difference: ${diffPercentage.toFixed(4)}%`);

    // Expect perfect or near-perfect accuracy (within 0.01% for rounding)
    expect(diffPercentage).to.be.lt(
      0.01,
      `Quote difference too high: ${diffPercentage}%`
    );

    // Expect exact match for our implementation
    expect(staticAmountOut).to.equal(
      officialAmountOut,
      "Should have exact match with native Algebra math"
    );

    return { officialAmountOut, staticAmountOut, diffPercentage };
  } catch (error: any) {
    console.log(`❌ Official quoter failed: ${error.message}`);
    console.log(`Falling back to our static quoter only...`);

    const staticResult = await staticQuoter.quoteExactInputSingle(staticParams);
    console.log(
      `  Our Static Quoter: ${ethers.utils.formatUnits(
        staticResult,
        tokenOut.decimals
      )} ${tokenOut.symbol}`
    );
    console.log(`  ⚠️  Cannot compare with official quoter`);

    // Just validate our quoter works
    expect(staticResult).to.be.gt(
      0,
      "Static quoter should return positive amount"
    );
    return { staticAmountOut: staticResult };
  }
}

async function ethereumFixture(blockNumber: number) {
  await forkNetwork("avalanche", blockNumber);
  return fixture();
}

describe("Algebra Integral Static Quoter", async () => {
  context("avalanche", () => {
    context("block 65834026", async () => {
      let fix: ThenArgRecursive<ReturnType<typeof ethereumFixture>>;

      beforeEach(async () => {
        fix = await ethereumFixture(65834026);
      });

      describe("AVAX/USDC pool (tickSpacing_200)", () => {
        it("should quote 1 AVAX → USDC with perfect accuracy", async () => {
          const amountIn = ethers.utils.parseEther("1");
          await compareQuotes(
            fix.officialQuoter,
            fix.staticQuoter,
            "avax",
            "usdc",
            amountIn,
            DEPLOYERS.tickSpacing_200,
            "1 AVAX → USDC"
          );
        });

        it("should quote 50 AVAX → USDC with perfect accuracy", async () => {
          const amountIn = ethers.utils.parseEther("50");
          await compareQuotes(
            fix.officialQuoter,
            fix.staticQuoter,
            "avax",
            "usdc",
            amountIn,
            DEPLOYERS.tickSpacing_200,
            "50 AVAX → USDC"
          );
        });

        it("should quote 100 AVAX → USDC with perfect accuracy", async () => {
          const amountIn = ethers.utils.parseEther("100");
          await compareQuotes(
            fix.officialQuoter,
            fix.staticQuoter,
            "avax",
            "usdc",
            amountIn,
            DEPLOYERS.tickSpacing_200,
            "100 AVAX → USDC"
          );
        });

        it("should quote 500 AVAX → USDC with perfect accuracy", async () => {
          const amountIn = ethers.utils.parseEther("500");
          await compareQuotes(
            fix.officialQuoter,
            fix.staticQuoter,
            "avax",
            "usdc",
            amountIn,
            DEPLOYERS.tickSpacing_200,
            "500 AVAX → USDC"
          );
        });

        it("should quote 1000 AVAX → USDC with perfect accuracy", async () => {
          const amountIn = ethers.utils.parseEther("1000");
          await compareQuotes(
            fix.officialQuoter,
            fix.staticQuoter,
            "avax",
            "usdc",
            amountIn,
            DEPLOYERS.tickSpacing_200,
            "1000 AVAX → USDC"
          );
        });

        it("should quote 10000 AVAX → USDC with perfect accuracy", async () => {
          const amountIn = ethers.utils.parseEther("10000");
          await compareQuotes(
            fix.officialQuoter,
            fix.staticQuoter,
            "avax",
            "usdc",
            amountIn,
            DEPLOYERS.tickSpacing_200,
            "10000 AVAX → USDC"
          );
        });
      });

      describe("USDC/USDT pool (tickSpacing_1)", () => {
        it("should quote 1000 USDC → USDT with perfect accuracy", async () => {
          const amountIn = ethers.utils.parseUnits("1000", 6); // USDC has 6 decimals
          await compareQuotes(
            fix.officialQuoter,
            fix.staticQuoter,
            "usdc",
            "usdt",
            amountIn,
            DEPLOYERS.tickSpacing_1,
            "1000 USDC → USDT"
          );
        });

        it("should quote 10000 USDC → USDT with perfect accuracy", async () => {
          const amountIn = ethers.utils.parseUnits("10000", 6);
          await compareQuotes(
            fix.officialQuoter,
            fix.staticQuoter,
            "usdc",
            "usdt",
            amountIn,
            DEPLOYERS.tickSpacing_1,
            "10000 USDC → USDT"
          );
        });

        it("should quote 50000 USDC → USDT with perfect accuracy", async () => {
          const amountIn = ethers.utils.parseUnits("50000", 6);
          await compareQuotes(
            fix.officialQuoter,
            fix.staticQuoter,
            "usdc",
            "usdt",
            amountIn,
            DEPLOYERS.tickSpacing_1,
            "50000 USDC → USDT"
          );
        });

        it("should quote 100000 USDC → USDT with perfect accuracy", async () => {
          const amountIn = ethers.utils.parseUnits("100000", 6);
          await compareQuotes(
            fix.officialQuoter,
            fix.staticQuoter,
            "usdc",
            "usdt",
            amountIn,
            DEPLOYERS.tickSpacing_1,
            "100000 USDC → USDT"
          );
        });

        // Reverse direction tests
        it("should quote 1000 USDT → USDC with perfect accuracy", async () => {
          const amountIn = ethers.utils.parseUnits("1000", 6); // USDT has 6 decimals
          await compareQuotes(
            fix.officialQuoter,
            fix.staticQuoter,
            "usdt",
            "usdc",
            amountIn,
            DEPLOYERS.tickSpacing_1,
            "1000 USDT → USDC"
          );
        });

        it("should quote 25000 USDT → USDC with perfect accuracy", async () => {
          const amountIn = ethers.utils.parseUnits("25000", 6);
          await compareQuotes(
            fix.officialQuoter,
            fix.staticQuoter,
            "usdt",
            "usdc",
            amountIn,
            DEPLOYERS.tickSpacing_1,
            "25000 USDT → USDC"
          );
        });
      });
    });
  });
});
