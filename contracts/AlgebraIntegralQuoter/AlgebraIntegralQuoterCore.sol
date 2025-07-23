// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import "./interfaces/IAlgebraPool.sol";
import "./lib/TickBitmapAlgebra.sol";
import "../UniV3likeQuoterCore.sol";

contract AlgebraIntegralQuoterCore is UniV3likeQuoterCore {
    function getPoolGlobalState(address pool) internal view override returns (GlobalState memory gs) {
        (uint160 price, int24 tick,,,,) = IAlgebraPool(pool).globalState();
        gs.startPrice = price;
        gs.startTick = tick;
        // Get the actual current fee (handles dynamic fees correctly)
        gs.fee = IAlgebraPool(pool).fee();
    }

    function getTickSpacing(address pool) internal view override returns (int24) {
        return IAlgebraPool(pool).tickSpacing();
    }

    function getLiquidity(address pool) internal view override returns (uint128) {
        return IAlgebraPool(pool).liquidity();
    }

    function nextInitializedTickWithinOneWord(address poolAddress, int24 tick, int24 tickSpacing, bool zeroForOne)
        internal
        view
        override
        returns (int24 next, bool initialized)
    {
        return TickBitmap.nextInitializedTickWithinOneWord(poolAddress, tick, tickSpacing, zeroForOne);
    }

    function getTicks(address pool, int24 tick)
        internal
        view
        override
        returns (
            uint128 liquidityTotal,
            int128 liquidityDelta,
            uint256 outerFeeGrowth0Token,
            uint256 outerFeeGrowth1Token,
            int56 outerTickCumulative,
            uint160 outerSecondsPerLiquidity,
            uint32 outerSecondsSpent,
            bool initialized
        )
    {
        return IAlgebraPool(pool).ticks(tick);
    }
}
