//+------------------------------------------------------------------+
//|                                              XAUUSD_TrendEA.mq5 |
//|         Generated from manual Heikin Ashi backtest annotations   |
//|         Symbol: XAUUSD | Timeframe: M1 | Chart type: Heikin Ashi |
//+------------------------------------------------------------------+
#property copyright "Generated with Claude"
#property version   "1.0"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

input ulong  MagicNumber          = 20260701; // identifies this EA's own positions, so it ignores manual/other-EA trades on the same symbol
input double LotSize             = 0.01;
input double DojiBodyRatio       = 0.15; // body/range below this = treated as doji/neutral (bar 2026-01-09 21:37 UTC)
input double MinTrendBodyRatio   = 0.45; // body/range must be at least this to count as a convincing trend candle (bar 2026-01-09 21:38 UTC had ratio ~0.40 and was rejected)
input double BreakoutMinBodyRatio = 0.30; // min body/range for a breakout candle to count as "decent size" (bar 2026-01-09 21:41 UTC had ratio ~0.34)
input int    ConsolidationLookback = 5;   // bars used to define the recent consolidation range for breakout checks
input int    ReversalLookback      = 5;   // bars compared against to decide if a counter-trend candle's body is "larger than its neighbors" (bar 2026-01-09 21:44 UTC)
input double CautionWickRatio     = 0.30; // lower-wick/range fraction that signals enough selling pressure to cut a long, even without a full reversal (bar 2026-01-09 21:50 UTC)
input double NoWickThreshold      = 0.05; // wick/range on the trend side below this counts as "no wick" (bar 2026-01-09 21:51 UTC)
input int    WarmupBars           = 15;   // bars to observe after start before acting on any signal - avoids firing on a cold-start bar with no established context (bar 2026-01-09 21:36 UTC was rejected for exactly this reason)
input double CounterExitBodyRatio     = 0.35; // min body/range for a counter-trend candle to be read as a trend change and close (not flip) the position (bar 2026-01-09 21:52 UTC had ratio ~0.41)
input double CounterExitMaxEntryWick  = 0.20; // max wick/range on the entry side of that counter-trend candle - "small wick" (bar 2026-01-09 21:52 UTC had ~0.16)
input double NewLowBreachRatio        = 0.50; // a bearish bar's low must undercut the preceding small-bullish bar's low by at least this fraction of that bar's range to count as a real breakdown (bar 2026-07-01 08:00 UTC breached by ~2.1x; a 0.09-point breach on bar 2026-07-01 07:23 UTC, only ~4%, was correctly NOT treated this way)

input group "Trading Session Filter"
input bool UseSessionFilter          = true;  // only take NEW entries inside the windows below; open positions are still managed (can still exit) at any time
input int  BrokerToUtcOffsetHours    = 0;     // hours to ADD to broker server time to get UTC - set this to match your broker's server timezone
input int  Session1StartHour = 8,  Session1EndHour = 13; // 08:00-13:00 UTC
input int  Session2StartHour = 13, Session2EndHour = 17; // 13:00-17:00 UTC
input int  Session3StartHour = 17, Session3EndHour = 19; // 17:00-19:00 UTC

double haOpen[], haHigh[], haLow[], haClose[];
datetime lastBarTime = 0;
int barsSeen = 0;
int barsInPosition = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
}

bool IsBullishHA(int shift) { return haClose[shift] > haOpen[shift]; }
bool IsBearishHA(int shift) { return haClose[shift] < haOpen[shift]; }

double BodyRatio(int shift)
{
   double range = haHigh[shift] - haLow[shift];
   if(range <= 0) return 0;
   return MathAbs(haClose[shift] - haOpen[shift]) / range;
}

bool IsDojiHA(int shift) { return BodyRatio(shift) < DojiBodyRatio; }

double RangeLow(int shift, int lookback)
{
   double lo = haLow[shift + 1];
   for(int i = shift + 1; i <= shift + lookback; i++)
      lo = MathMin(lo, haLow[i]);
   return lo;
}

double RangeHigh(int shift, int lookback)
{
   double hi = haHigh[shift + 1];
   for(int i = shift + 1; i <= shift + lookback; i++)
      hi = MathMax(hi, haHigh[i]);
   return hi;
}

bool IsBreakoutShort(int shift)
{
   return IsBearishHA(shift) && BodyRatio(shift) >= BreakoutMinBodyRatio &&
          haLow[shift] < RangeLow(shift, ConsolidationLookback);
}

bool IsBreakoutLong(int shift)
{
   return IsBullishHA(shift) && BodyRatio(shift) >= BreakoutMinBodyRatio &&
          haHigh[shift] > RangeHigh(shift, ConsolidationLookback);
}

double UpperWickRatio(int shift)
{
   double range = haHigh[shift] - haLow[shift];
   if(range <= 0) return 0;
   return (haHigh[shift] - MathMax(haOpen[shift], haClose[shift])) / range;
}

double LowerWickRatio(int shift)
{
   double range = haHigh[shift] - haLow[shift];
   if(range <= 0) return 0;
   return (MathMin(haOpen[shift], haClose[shift]) - haLow[shift]) / range;
}

// A convincing trend candle (non-doji, body >= MinTrendBodyRatio) with
// no wick on the trend side - taken as a standalone entry even without a
// range breakout. Confirmed both ways: short on bar 2026-01-09 21:51 UTC
// (no upper wick), long on bar 2026-01-09 21:53 UTC (no lower wick).
bool IsTrendEntryShort(int shift)
{
   return IsBearishHA(shift) && !IsDojiHA(shift) &&
          BodyRatio(shift) >= MinTrendBodyRatio &&
          UpperWickRatio(shift) <= NoWickThreshold;
}

bool IsTrendEntryLong(int shift)
{
   return IsBullishHA(shift) && !IsDojiHA(shift) &&
          BodyRatio(shift) >= MinTrendBodyRatio &&
          LowerWickRatio(shift) <= NoWickThreshold;
}

double Body(int shift) { return MathAbs(haClose[shift] - haOpen[shift]); }

double MaxBody(int shift, int lookback)
{
   double m = 0;
   for(int i = shift + 1; i <= shift + lookback; i++)
      m = MathMax(m, Body(i));
   return m;
}

// A counter-trend candle whose body is bigger than every one of the last
// ReversalLookback candles - signals a sharp reversal worth flipping for.
// Confirmed both ways: bullish flipping short into long (bar 2026-01-09
// 21:44 UTC), bearish flipping long into short (bar 2026-07-01 07:29 UTC,
// no upper wick, body ratio ~0.62, biggest of the last 5 candles).
bool IsReversalLong(int shift)  { return IsBullishHA(shift) && Body(shift) > MaxBody(shift, ReversalLookback); }
bool IsReversalShort(int shift) { return IsBearishHA(shift) && Body(shift) > MaxBody(shift, ReversalLookback); }

// A bearish candle that isn't a full reversal candle but still shows a
// long lower wick and a real (non-doji) body - enough of a threat to cut
// a long without flipping short. Mirrored short-side case not yet observed.
bool IsCautionExitLong(int shift)
{
   return IsBearishHA(shift) && !IsDojiHA(shift) &&
          BodyRatio(shift) < BreakoutMinBodyRatio &&
          LowerWickRatio(shift) >= CautionWickRatio;
}

// A bullish candle with a moderate-to-decent body and a small wick on its
// entry side (clean push, little rejection) closes out a short as a trend
// change - but does NOT flip into a long (weaker signal than
// IsReversalLong, which requires the body to beat all recent neighbors).
// Mirrored bearish case (closing a long) not yet observed.
bool IsCounterTrendExitShort(int shift)
{
   return IsBullishHA(shift) && !IsDojiHA(shift) &&
          BodyRatio(shift) >= CounterExitBodyRatio &&
          LowerWickRatio(shift) <= CounterExitMaxEntryWick;
}

// A small-bodied bullish bar (weak continuation) followed by a bearish bar
// whose low undercuts that bullish bar's low by a real margin (not just a
// tick) reads as a breakdown worth exiting a long for, even if the bearish
// bar's own body/wick shape wouldn't otherwise trip IsCautionExitLong or
// IsReversalShort (bar 2026-07-01 07:59-08:00 UTC: small bullish bar then
// a bearish bar breaching its low by ~2.1x that bar's range). A near-tick
// low breach (bar 2026-07-01 07:22-07:23 UTC, ~4% of range) is NOT enough.
bool IsWeakeningTrendExitLong(int shift)
{
   int prevShift = shift + 1;
   if(!(IsBullishHA(prevShift) && BodyRatio(prevShift) < BreakoutMinBodyRatio)) return false;
   if(!IsBearishHA(shift)) return false;

   double prevRange = haHigh[prevShift] - haLow[prevShift];
   if(prevRange <= 0) return false;

   double breach = haLow[prevShift] - haLow[shift];
   return breach >= NewLowBreachRatio * prevRange;
}

// A doji (indecision bar) immediately followed by a convincing, clean
// (no opposing wick) trend candle in the other direction reads as the
// indecision resolving into a full reversal - closes the position AND
// flips, even if the candle's body doesn't beat every recent neighbor
// (which is what IsReversalLong/Short would require). Confirmed for
// long->short (bar 2026-07-01 08:22 UTC: doji at 08:21 UTC, then bearish,
// no upper wick, ratio ~0.64). Mirrored short->long case not yet observed.
bool IsPostDojiReversalShort(int shift)
{
   int prevShift = shift + 1;
   return IsDojiHA(prevShift) && IsBearishHA(shift) && !IsDojiHA(shift) &&
          BodyRatio(shift) >= MinTrendBodyRatio &&
          UpperWickRatio(shift) <= NoWickThreshold;
}

// A doji on the very first bar after entering a long, whose high fails to
// exceed the entry bar's high, means the entry got no follow-through -
// exit immediately. Only applies right at entry (barsHeld == 1); a doji
// deep into an established trend is just caution, not an exit (bar
// 2026-07-01 07:43 UTC and 08:21 UTC were both held). Confirmed for longs
// (bar 2026-07-01 08:28 UTC, one bar after the 08:27 UTC entry).
bool IsNoConfirmationExitLong(int shift, int barsHeld)
{
   return barsHeld == 1 && IsDojiHA(shift) && haHigh[shift] <= haHigh[shift + 1];
}

// Mirror of IsNoConfirmationExitLong: a doji on the very first bar after
// entering a short, whose low fails to undercut the entry bar's low, means
// no follow-through - exit immediately. Explicitly checked against bar
// 2026-07-01 11:41 UTC (doji, first bar after a short entry) - that bar's
// low DID undercut the entry bar's low, so this would correctly NOT have
// fired there; it was confirmed as a real gap, not a guess.
bool IsNoConfirmationExitShort(int shift, int barsHeld)
{
   return barsHeld == 1 && IsDojiHA(shift) && haLow[shift] >= haLow[shift + 1];
}

// Computes Heikin Ashi OHLC from real chart bars. Index 0 = current
// (forming) bar, higher index = further back, matching MT5 series direction.
void UpdateHeikinAshi(int count)
{
   ArrayResize(haOpen, count);
   ArrayResize(haHigh, count);
   ArrayResize(haLow, count);
   ArrayResize(haClose, count);

   for(int i = count - 1; i >= 0; i--)
   {
      double o = iOpen(_Symbol, PERIOD_CURRENT, i);
      double h = iHigh(_Symbol, PERIOD_CURRENT, i);
      double l = iLow(_Symbol, PERIOD_CURRENT, i);
      double c = iClose(_Symbol, PERIOD_CURRENT, i);

      haClose[i] = (o + h + l + c) / 4.0;
      haOpen[i]  = (i == count - 1) ? (o + c) / 2.0 : (haOpen[i + 1] + haClose[i + 1]) / 2.0;
      haHigh[i]  = MathMax(h, MathMax(haOpen[i], haClose[i]));
      haLow[i]   = MathMin(l, MathMin(haOpen[i], haClose[i]));
   }
}

// Restricts new entries to the configured UTC session windows. Existing
// positions are always managed regardless of session, so the EA can never
// get stuck holding a position through a dead zone with no way to exit.
bool IsWithinTradingSession()
{
   if(!UseSessionFilter) return true;

   datetime t = TimeCurrent() + BrokerToUtcOffsetHours * 3600;
   MqlDateTime dt;
   TimeToStruct(t, dt);
   int minutesOfDay = dt.hour * 60 + dt.min;

   if(minutesOfDay >= Session1StartHour * 60 && minutesOfDay < Session1EndHour * 60) return true;
   if(minutesOfDay >= Session2StartHour * 60 && minutesOfDay < Session2EndHour * 60) return true;
   if(minutesOfDay >= Session3StartHour * 60 && minutesOfDay < Session3EndHour * 60) return true;
   return false;
}

bool IsNewBar()
{
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t != lastBarTime)
   {
      lastBarTime = t;
      return true;
   }
   return false;
}

void OnTick()
{
   if(!IsNewBar()) return;
   barsSeen++;
   if(barsSeen < WarmupBars) return; // still building context - see WarmupBars

   UpdateHeikinAshi(MathMax(ConsolidationLookback, ReversalLookback) + 5);
   int shift = 1; // last fully closed HA bar

   // Patterns observed so far:
   // - Trader waits for a clear bullish HA candle before entering long.
   // - Small-body/doji HA candles are treated as neutral, not a trend
   //   signal, even if technically bullish or bearish.
   // - A non-doji candle can still be rejected if its body isn't large
   //   enough relative to its range to be convincing on its own
   //   (MinTrendBodyRatio) - this applies when there's no other
   //   confirming context like a range breakout.
   // - Entry: a candle with a decent body (>= BreakoutMinBodyRatio) whose
   //   wick pierces the recent consolidation range triggers an entry in
   //   that direction (bar 2026-01-09 21:41 UTC: bearish, ratio ~0.34,
   //   low broke below the prior 5-bar range low -> SHORT).
   // - Hold: as long as the position's direction candle stays large-bodied
   //   with no opposing wick, keep holding even without a new extreme each
   //   bar (bars 2026-01-09 21:42-21:43 UTC).
   // - Reversal exit+flip: a counter-trend candle whose body is bigger
   //   than all of the last ReversalLookback candles' bodies closes out
   //   the position and flips into the new direction (bar 2026-01-09
   //   21:44 UTC: bullish body far exceeded recent bearish bodies while
   //   short -> exit short, enter long).
   // - Caution exit (no flip): a bearish, non-doji candle with a long
   //   lower wick (>= CautionWickRatio of range) but too small a body to
   //   count as a breakout/reversal candle is treated as a threat worth
   //   cutting a long for, without going short (bar 2026-01-09 21:50 UTC:
   //   body ratio ~0.25, lower wick ~54% of range).
   // - Standalone trend entry: a convincing trend candle (no range
   //   breakout needed) with zero wick on the trend side is also a valid
   //   entry on its own, but ONLY once WarmupBars of context have been
   //   observed - the same shape on bar 2026-01-09 21:36 UTC (the very
   //   first bar seen, no prior context) was explicitly rejected. Confirmed
   //   both ways: short (21:51 UTC), long (21:53 UTC, no lower wick, ratio
   //   ~0.56, which also happened to break the recent range high).
   // - Counter-trend exit (no flip): a moderate-to-decent body opposing
   //   candle with a small wick on its entry side reads as a trend change
   //   and closes the position, without the stronger conviction
   //   IsReversalLong/Short requires to flip (bar 2026-01-09 21:52 UTC:
   //   bullish, body ratio ~0.41, lower wick ~16%, while short -> exit
   //   short, stay flat).
   // - Reversal exit+flip, mirrored: a bearish candle whose body beats all
   //   of the last ReversalLookback candles closes a long and flips short
   //   (bar 2026-07-01 07:29 UTC: no upper wick, body ratio ~0.62, beat
   //   every one of the last 5 candles' bodies while long).
   // - Weakening-trend exit (no flip): a small-bodied bullish bar followed
   //   by a bearish bar that undercuts its low by a real margin (>=
   //   NewLowBreachRatio of that bar's range) exits a long even when the
   //   bearish bar's own shape doesn't trip IsCautionExitLong or
   //   IsReversalShort (bar 2026-07-01 08:00 UTC).
   // - Post-doji reversal (exit+flip): a doji immediately followed by a
   //   convincing, no-opposing-wick trend candle in the other direction is
   //   read as indecision resolving into a real reversal - flips the
   //   position even without beating every recent body like
   //   IsReversalLong/Short requires (bar 2026-07-01 08:22 UTC: doji at
   //   08:21 UTC then a clean bearish candle, ratio ~0.64, while long ->
   //   exit long, enter short).
   // - No-confirmation exit (no flip): a doji on the very first bar after
   //   entry that fails to make a new high (long) means the entry didn't
   //   get follow-through - exit right away, even though the same doji
   //   shape deep into a trend is just held through (bar 2026-07-01
   //   08:28 UTC, one bar after the 08:27 UTC long entry). Mirrored on the
   //   short side (IsNoConfirmationExitShort) - checked against bar
   //   2026-07-01 11:41 UTC where the doji still made a new low, correctly
   //   not triggering.

   bool hasPosition = PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber;
   long posType = hasPosition ? PositionGetInteger(POSITION_TYPE) : -1;
   if(hasPosition) barsInPosition++; else barsInPosition = 0;

   if(hasPosition && posType == POSITION_TYPE_SELL && IsReversalLong(shift))
   {
      trade.PositionClose(_Symbol);
      trade.Buy(LotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK));
      return;
   }

   if(hasPosition && posType == POSITION_TYPE_SELL &&
      (IsCounterTrendExitShort(shift) || IsNoConfirmationExitShort(shift, barsInPosition)))
   {
      trade.PositionClose(_Symbol);
      return;
   }

   if(hasPosition && posType == POSITION_TYPE_BUY && (IsReversalShort(shift) || IsPostDojiReversalShort(shift)))
   {
      trade.PositionClose(_Symbol);
      trade.Sell(LotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID));
      return;
   }

   if(hasPosition && posType == POSITION_TYPE_BUY &&
      (IsCautionExitLong(shift) || IsWeakeningTrendExitLong(shift) || IsNoConfirmationExitLong(shift, barsInPosition)))
   {
      trade.PositionClose(_Symbol);
      return;
   }

   if(!hasPosition && IsWithinTradingSession())
   {
      if(IsBreakoutShort(shift) || IsTrendEntryShort(shift))
         trade.Sell(LotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID));
      else if(IsBreakoutLong(shift) || IsTrendEntryLong(shift))
         trade.Buy(LotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK));
   }
}
