//+------------------------------------------------------------------+
//| Heikin Ashi Trend Strategy                                       |
//| v2.0 — Asia + US session filter                                  |
//| Optimised timeframe: M5                                          |
//| Logic: enter long/short on HA candle direction flip,             |
//|        ignoring small-body candles (< ATR × BodyMinPct)         |
//|        only during Asia (17:00–02:00 PDT) and                   |
//|        US (05:00–13:30 PDT) sessions. Close all on session end.  |
//+------------------------------------------------------------------+
#property copyright ""
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

//── Inputs ──────────────────────────────────────────────────────────
input int    AtrLength   = 14;    // ATR Length
input double BodyMinPct  = 0.3;   // Min Body (× ATR) — smaller candles are ignored
input double LotSize     = 0.1;   // Trade lot size
input int    MagicNumber = 20250621;

//── Session times in UTC (PDT = UTC-7) ──────────────────────────────
// Asia session:  17:00–02:00 PDT  =  00:00–09:00 UTC
// US   session:  05:00–13:30 PDT  =  12:00–20:30 UTC
// +15 min buffer after open, -15 min buffer before close (spread/swap)
input int AsiaStartHour  = 0;    // Asia start (UTC)
input int AsiaStartMin   = 0;
input int AsiaEndHour    = 9;    // Asia end (UTC)
input int AsiaEndMin     = 0;
input int USStartHour    = 12;   // US start (UTC)
input int USStartMin     = 0;
input int USEndHour      = 20;   // US end (UTC)
input int USEndMin       = 30;
input int OpenBufferMin  = 15;   // Skip N minutes after session open (high spread)
input int CloseBufferMin = 15;   // Skip N minutes before session close (swap charge)

//── Globals ─────────────────────────────────────────────────────────
CTrade trade;
int    atrHandle;

//+------------------------------------------------------------------+
int OnInit()
{
    atrHandle = iATR(_Symbol, _Period, AtrLength);
    if(atrHandle == INVALID_HANDLE)
    {
        Print("Failed to create ATR handle");
        return INIT_FAILED;
    }
    trade.SetExpertMagicNumber(MagicNumber);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
bool InSession()
{
    MqlDateTime dt;
    TimeToStruct(TimeGMT(), dt);
    int mins = dt.hour * 60 + dt.min;

    int asiaStart = AsiaStartHour * 60 + AsiaStartMin + OpenBufferMin;
    int asiaEnd   = AsiaEndHour   * 60 + AsiaEndMin   - CloseBufferMin;
    int usStart   = USStartHour   * 60 + USStartMin   + OpenBufferMin;
    int usEnd     = USEndHour     * 60 + USEndMin     - CloseBufferMin;

    bool inAsia = (mins >= asiaStart && mins < asiaEnd);
    bool inUS   = (mins >= usStart   && mins < usEnd);
    return inAsia || inUS;
}

//+------------------------------------------------------------------+
void OnTick()
{
    // Only act on a new bar
    static datetime lastBar    = 0;
    static bool     wasInSession = false;

    datetime currentBar = iTime(_Symbol, _Period, 0);
    bool     nowInSession = InSession();

    // Close all positions when session ends
    if(wasInSession && !nowInSession)
    {
        ClosePositions(POSITION_TYPE_BUY);
        ClosePositions(POSITION_TYPE_SELL);
    }
    wasInSession = nowInSession;

    if(currentBar == lastBar) return;
    lastBar = currentBar;

    if(!nowInSession) return;

    // Need enough bars for HA calculation and ATR
    if(Bars(_Symbol, _Period) < AtrLength + 3) return;

    // ── Fetch ATR ────────────────────────────────────────────────
    double atrBuf[];
    ArraySetAsSeries(atrBuf, true);
    if(CopyBuffer(atrHandle, 0, 1, 3, atrBuf) < 3) return;

    // ── Compute Heikin Ashi for last 3 confirmed bars ────────────
    double haOpen[3], haClose[3];
    for(int i = 2; i >= 0; i--)
    {
        int shift = i + 1;
        double o = iOpen (_Symbol, _Period, shift);
        double h = iHigh (_Symbol, _Period, shift);
        double l = iLow  (_Symbol, _Period, shift);
        double c = iClose(_Symbol, _Period, shift);

        haClose[i] = (o + h + l + c) / 4.0;
        haOpen[i]  = (i == 2) ? (o + c) / 2.0
                               : (haOpen[i+1] + haClose[i+1]) / 2.0;
    }

    // ── Body-size filter ─────────────────────────────────────────
    bool isBull0 = (haClose[0] > haOpen[0]) && (MathAbs(haClose[0] - haOpen[0]) >= atrBuf[0] * BodyMinPct);
    bool isBear0 = (haClose[0] < haOpen[0]) && (MathAbs(haClose[0] - haOpen[0]) >= atrBuf[0] * BodyMinPct);
    bool isBull1 = (haClose[1] > haOpen[1]) && (MathAbs(haClose[1] - haOpen[1]) >= atrBuf[1] * BodyMinPct);
    bool isBear1 = (haClose[1] < haOpen[1]) && (MathAbs(haClose[1] - haOpen[1]) >= atrBuf[1] * BodyMinPct);

    // ── Trend-change signals ─────────────────────────────────────
    static int lastDir = 0;

    int prevDir = lastDir;
    if(isBull1)      lastDir = 1;
    else if(isBear1) lastDir = -1;

    bool bullFlip = isBull0 && (lastDir == -1);
    bool bearFlip = isBear0 && (lastDir ==  1);

    if(isBull0)      lastDir = 1;
    else if(isBear0) lastDir = -1;

    // ── Trade execution ──────────────────────────────────────────
    if(bullFlip)
    {
        ClosePositions(POSITION_TYPE_SELL);
        if(!HasPosition(POSITION_TYPE_BUY))
            trade.Buy(LotSize, _Symbol, 0, 0, 0, "HA Long");
    }
    else if(bearFlip)
    {
        ClosePositions(POSITION_TYPE_BUY);
        if(!HasPosition(POSITION_TYPE_SELL))
            trade.Sell(LotSize, _Symbol, 0, 0, 0, "HA Short");
    }
}

//+------------------------------------------------------------------+
bool HasPosition(ENUM_POSITION_TYPE type)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
           PositionGetInteger(POSITION_MAGIC)  == MagicNumber &&
           PositionGetInteger(POSITION_TYPE)   == type)
            return true;
    }
    return false;
}

//+------------------------------------------------------------------+
void ClosePositions(ENUM_POSITION_TYPE type)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
           PositionGetInteger(POSITION_MAGIC)  == MagicNumber &&
           PositionGetInteger(POSITION_TYPE)   == type)
            trade.PositionClose(ticket);
    }
}
//+------------------------------------------------------------------+
