//+------------------------------------------------------------------+
//|                                              FVG_Crossfire.mq4   |
//|                    Converted from Pine Script v6 (Flux Charts)   |
//|                    Advanced Scalping Engine & State Machine      |
//+------------------------------------------------------------------+
#property copyright "FVG Crossfire Flux Charts"
#property version   "2.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Enums --------------------------------------------------------
enum ENUM_MITIGATION {
    MITIG_WICK = 0, // Wick
    MITIG_CLOSE = 1 // Close
};

enum ENUM_LINESTYLE {
    LSTYLE_SOLID = STYLE_SOLID,
    LSTYLE_DASH = STYLE_DASH,
    LSTYLE_DOT = STYLE_DOT
};

enum ENTRY_STATE {
    STATE_WAIT_SWEEP = 0,
    STATE_WAIT_REJECTION = 1,
    STATE_WAIT_STRUCTURE = 2,
    STATE_WAIT_DISPLACEMENT = 3,
    STATE_WAIT_RETEST = 4,
    STATE_ENTRY_TRIGGERED = 5,
    STATE_INVALID = 6
};

//--- Inputs -------------------------------------------------------
input string _b1              = "=== Base FVG ===";
input ENUM_MITIGATION fvgMitig= MITIG_CLOSE;
input double minGap           = 0.0;
input bool   showFunnel       = true;
input bool   fvgBorder        = false;
input ENUM_LINESTYLE fvgStyle = LSTYLE_DOT;
input color  bullFvgCol       = C'14,203,129';
input color  bearFvgCol       = C'246,70,93';

input string _b2              = "=== Crossfire Zone ===";
input int    lookback         = 3000;
input ENUM_MITIGATION zoneMitig= MITIG_CLOSE;
input bool   zoneBorder       = false;
input ENUM_LINESTYLE zoneStyle= LSTYLE_DOT;
input bool   showMid          = false;
input ENUM_LINESTYLE midStyle = LSTYLE_DASH;
input color  bullZoneCol      = C'14,203,129';
input color  bearZoneCol      = C'246,70,93';
input bool   retestMarks      = false; // Default disabled (Retest Arrows)
input bool   combineZones     = false;
input bool   showMitigated    = true;

input string _b4              = "=== Entry Engine ===";
input bool   showEntryArrows     = true;  // Enabled so user can see signals on chart
input int    SweepLookback       = 10;
input double SweepMinATR         = 0.10;
input int    StructureLookback   = 10;
input double DisplacementATR     = 0.8;
input double DisplacementBodyATR = 0.5;
input bool   UseHTFBias          = true;
input ENUM_TIMEFRAMES HTF        = PERIOD_M15;
input int    MinEntryScore       = 55;    // Tuned from 70 to 55 to prevent zero trades
input bool   DebugMode           = false;

input string _b3              = "=== Alerts ===";
input bool   alertNew         = true;
input bool   alertFlip        = true;
input bool   alertRetest      = false;
input bool   alertMitig       = false;
input bool   alertEntry       = true;

//--- Constants ----------------------------------------------------
#define SNAP_BARS     3
#define MAX_FVGS      80
#define MAX_SEGMENTS  120
#define MAX_RETEST    20
#define PREFIX        "FVG_FX_"

//--- Structs ------------------------------------------------------
struct FVG {
    int      dir;
    double   top;
    double   bottom;
    double   lagTop;
    double   lagBottom;
    int      startIdx;
    datetime anchorTopTime;
    datetime anchorBotTime;
};

struct Segment {
    int      dir;
    double   top;
    double   bottom;
    int      createIdx;
    bool     active;
    bool     done;
    bool     touching;
    int      chainId;
    int      flips;
    string   bxName;
    string   fvgTopName;
    string   fvgBotName;
    string   eqName;
    string   markName;
    string   retestNames[MAX_RETEST];
    int      retestCount;
    
    // Entry Engine Fields
    ENTRY_STATE state;
    int         score;
    double      sweepLevel;
    double      bosLevel;
    string      entryMarkName;
    string      debugMarkName;
};

//--- Globals ------------------------------------------------------
FVG      g_fvgs[];
Segment  g_segs[];
int      g_chainSeq = 0;
int      g_absIdx = 0;
datetime g_lastBarTime = 0;
bool     g_suppressAlerts = false;
int      g_nameCounter = 0;

bool     g_evNew, g_evFlip, g_evRetest, g_evMitig, g_evEntry;
bool     g_fvgWick, g_zoneWick;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
string NewName(string base) {
    g_nameCounter++;
    return PREFIX + base + "_" + IntegerToString(g_nameCounter);
}

string StarText(int n) {
    string s = "";
    if (n <= 4) {
        for (int i = 0; i < n; i++) s = s + "*";
        return s;
    }
    return IntegerToString(n) + "*";
}

void DeleteAllObjects() {
    int total = ObjectsTotal();
    for (int i = total - 1; i >= 0; i--) {
        string nm = ObjectName(i);
        if (StringFind(nm, PREFIX) == 0)
            ObjectDelete(nm);
    }
}

color BlendColor(color fg, int opacity) {
    color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND, 0);
    int r = (int)MathRound((((fg) & 0xFF) * opacity + ((bg) & 0xFF) * (100 - opacity)) / 100.0);
    int g = (int)MathRound(((((fg) >> 8) & 0xFF) * opacity + (((bg) >> 8) & 0xFF) * (100 - opacity)) / 100.0);
    int b = (int)MathRound(((((fg) >> 16) & 0xFF) * opacity + (((bg) >> 16) & 0xFF) * (100 - opacity)) / 100.0);
    return (color)(r | (g << 8) | (b << 16));
}

bool IsBlockGap(int shift) {
    if (shift + 2 >= Bars) return false;
    datetime t0 = Time[shift];
    datetime t1 = Time[shift+1];
    datetime t2 = Time[shift+2];

    bool dGap = false;
    bool wGap = false;

    if (Period() < PERIOD_D1) {
        if (TimeDay(t0) != TimeDay(t1) || TimeDay(t1) != TimeDay(t2)) dGap = true;
    }
    if (Period() <= PERIOD_D1) {
        if (TimeDayOfWeek(t0) < TimeDayOfWeek(t1) || TimeDayOfWeek(t1) < TimeDayOfWeek(t2)) wGap = true;
    }
    return dGap || wGap;
}

//+------------------------------------------------------------------+
//| Clear / dim segment                                              |
//+------------------------------------------------------------------+
void ClearSegment(Segment &s) {
    if (s.bxName     != "") { ObjectDelete(s.bxName);     s.bxName     = ""; }
    if (s.fvgTopName != "") { ObjectDelete(s.fvgTopName); s.fvgTopName = ""; }
    if (s.fvgBotName != "") { ObjectDelete(s.fvgBotName); s.fvgBotName = ""; }
    if (s.eqName     != "") { ObjectDelete(s.eqName);     s.eqName     = ""; }
    if (s.markName   != "") { ObjectDelete(s.markName);   s.markName   = ""; }
    if (s.entryMarkName != "") { ObjectDelete(s.entryMarkName); s.entryMarkName = ""; }
    if (s.debugMarkName != "") { ObjectDelete(s.debugMarkName); s.debugMarkName = ""; }
    
    for(int i = 0; i < s.retestCount; i++) {
        if(s.retestNames[i] != "") ObjectDelete(s.retestNames[i]);
    }
    s.retestCount = 0;
}

void DimSegment(Segment &s) {
    color baseCol = (s.dir == 1) ? bullZoneCol : bearZoneCol;
    color dim = BlendColor(baseCol, 20); 
    
    if (s.bxName     != "") ObjectSet(s.bxName,     OBJPROP_COLOR, dim);
    if (s.eqName     != "") ObjectSet(s.eqName,     OBJPROP_COLOR, dim);
    
    color fvgBaseCol = (s.dir == 1) ? bullFvgCol : bearFvgCol;
    color fvgDim = BlendColor(fvgBaseCol, 20);
    
    if (s.fvgTopName != "") ObjectSet(s.fvgTopName, OBJPROP_COLOR, fvgDim);
    if (s.fvgBotName != "") ObjectSet(s.fvgBotName, OBJPROP_COLOR, fvgDim);
}

//+------------------------------------------------------------------+
//| Box + funnel creation                                            |
//+------------------------------------------------------------------+
void CreateBox(Segment &s, datetime handoffTime) {
    color zc = (s.dir == 1) ? bullZoneCol : bearZoneCol;
    color blendedCol = BlendColor(zc, 50);

    s.bxName = NewName("bx");
    ObjectCreate(s.bxName, OBJ_RECTANGLE, 0, handoffTime, s.top, Time[0], s.bottom);
    ObjectSet(s.bxName, OBJPROP_COLOR, blendedCol);
    ObjectSet(s.bxName, OBJPROP_STYLE, zoneStyle);
    ObjectSet(s.bxName, OBJPROP_WIDTH, 1);
    ObjectSet(s.bxName, OBJPROP_BACK, true);

    if (showMid) {
        double m = (s.top + s.bottom) * 0.5;
        s.eqName = NewName("eq");
        ObjectCreate(s.eqName, OBJ_TREND, 0, handoffTime, m, Time[0], m);
        ObjectSet(s.eqName, OBJPROP_COLOR, zc);
        ObjectSet(s.eqName, OBJPROP_STYLE, midStyle);
        ObjectSet(s.eqName, OBJPROP_WIDTH, 1);
        ObjectSet(s.eqName, OBJPROP_RAY, false);
        ObjectSet(s.eqName, OBJPROP_BACK, false);
    }
}

void CreateFunnel(Segment &s, FVG &a, datetime handoffTime, double t, double bot) {
    color fc = (a.dir == 1) ? bullFvgCol : bearFvgCol;

    s.fvgTopName = NewName("ft");
    ObjectCreate(s.fvgTopName, OBJ_TREND, 0, a.anchorTopTime, a.top, handoffTime, t);
    ObjectSet(s.fvgTopName, OBJPROP_COLOR, fc);
    ObjectSet(s.fvgTopName, OBJPROP_STYLE, fvgStyle);
    ObjectSet(s.fvgTopName, OBJPROP_WIDTH, 1);
    ObjectSet(s.fvgTopName, OBJPROP_RAY, false);

    s.fvgBotName = NewName("fb");
    ObjectCreate(s.fvgBotName, OBJ_TREND, 0, a.anchorBotTime, a.bottom, handoffTime, bot);
    ObjectSet(s.fvgBotName, OBJPROP_COLOR, fc);
    ObjectSet(s.fvgBotName, OBJPROP_STYLE, fvgStyle);
    ObjectSet(s.fvgBotName, OBJPROP_WIDTH, 1);
    ObjectSet(s.fvgBotName, OBJPROP_RAY, false);
}

//+------------------------------------------------------------------+
//| Merge zone                                                       |
//+------------------------------------------------------------------+
bool MergeZone(int dir, double t, double bot) {
    for (int i = 0; i < ArraySize(g_segs); i++) {
        if (g_segs[i].active && !g_segs[i].done && g_segs[i].dir == dir
            && bot <= g_segs[i].top && g_segs[i].bottom <= t)
        {
            g_segs[i].top    = MathMax(g_segs[i].top, t);
            g_segs[i].bottom = MathMin(g_segs[i].bottom, bot);

            if (g_segs[i].bxName != "") {
                ObjectMove(g_segs[i].bxName, 0, (datetime)ObjectGet(g_segs[i].bxName, OBJPROP_TIME1), g_segs[i].top);
                ObjectMove(g_segs[i].bxName, 1, (datetime)ObjectGet(g_segs[i].bxName, OBJPROP_TIME2), g_segs[i].bottom);
            }
            if (g_segs[i].eqName != "") {
                double m = (g_segs[i].top + g_segs[i].bottom) * 0.5;
                ObjectMove(g_segs[i].eqName, 0, (datetime)ObjectGet(g_segs[i].eqName, OBJPROP_TIME1), m);
                ObjectMove(g_segs[i].eqName, 1, (datetime)ObjectGet(g_segs[i].eqName, OBJPROP_TIME2), m);
            }
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Build new crossfire zone                                         |
//+------------------------------------------------------------------+
int MakeChain(FVG &a, FVG &b, int shift) {
    double t   = MathMin(a.lagTop, b.top);
    double bot = MathMax(a.lagBottom, b.bottom);
    if (bot >= t) return 0;

    if (combineZones && MergeZone(b.dir, t, bot)) return 2;

    int handoffShift = shift + 1;
    if (handoffShift >= Bars) handoffShift = Bars - 1;
    datetime handoffTime = Time[handoffShift];

    Segment s;
    s.dir = b.dir; s.top = t; s.bottom = bot;
    s.createIdx = g_absIdx;
    s.active = true; s.done = false; s.touching = false;
    s.chainId = g_chainSeq;
    s.flips = 1;
    s.bxName = ""; s.fvgTopName = ""; s.fvgBotName = "";
    s.eqName = ""; s.markName = "";
    s.entryMarkName = ""; s.debugMarkName = "";
    s.retestCount = 0;
    
    // Init state machine
    s.state = STATE_WAIT_SWEEP;
    s.score = 15; // Base Zone Quality Score
    s.sweepLevel = 0;
    s.bosLevel = 0;

    for(int i=0; i<MAX_RETEST; i++) s.retestNames[i] = "";

    CreateBox(s, handoffTime);
    if (showFunnel) CreateFunnel(s, a, handoffTime, t, bot);

    int sz = ArraySize(g_segs);
    ArrayResize(g_segs, sz + 1);
    g_segs[sz] = s;
    return 1;
}

//+------------------------------------------------------------------+
//| Flip a live zone                                                 |
//+------------------------------------------------------------------+
bool FlipSegment(int idx, FVG &b, int shift) {
    double t   = MathMin(b.top, g_segs[idx].top);
    double bot = MathMax(b.bottom, g_segs[idx].bottom);
    if (bot >= t) return false;

    int handoffShift = shift + 1;
    if (handoffShift >= Bars) handoffShift = Bars - 1;
    datetime handoffTime = Time[handoffShift];

    if (g_segs[idx].bxName != "")
        ObjectSet(g_segs[idx].bxName, OBJPROP_TIME2, handoffTime);
    if (g_segs[idx].eqName != "")
        ObjectSet(g_segs[idx].eqName, OBJPROP_TIME2, handoffTime);
    if (g_segs[idx].markName != "") {
        ObjectDelete(g_segs[idx].markName);
        g_segs[idx].markName = "";
    }
    
    g_segs[idx].state = STATE_INVALID; // Old zone is done
    g_segs[idx].active = false;

    Segment ns;
    ns.dir = b.dir; ns.top = t; ns.bottom = bot;
    ns.createIdx = g_absIdx;
    ns.active = true; ns.done = false; ns.touching = false;
    ns.chainId = g_segs[idx].chainId;
    ns.flips = g_segs[idx].flips + 1;
    ns.bxName = ""; ns.fvgTopName = ""; ns.fvgBotName = "";
    ns.eqName = ""; ns.markName = "";
    ns.entryMarkName = ""; ns.debugMarkName = "";
    ns.retestCount = 0;
    
    // Init state machine
    ns.state = STATE_WAIT_SWEEP;
    ns.score = 15; 
    ns.sweepLevel = 0;
    ns.bosLevel = 0;

    for(int i=0; i<MAX_RETEST; i++) ns.retestNames[i] = "";

    CreateBox(ns, handoffTime);

    int sz = ArraySize(g_segs);
    ArrayResize(g_segs, sz + 1);
    g_segs[sz] = ns;
    return true;
}

//+------------------------------------------------------------------+
//| Lag mitigation                                                   |
//+------------------------------------------------------------------+
void LagMitigate(FVG &f, int shift) {
    if (f.startIdx < g_absIdx - SNAP_BARS) {
        if (shift + SNAP_BARS >= Bars) return;
        if (f.dir == 1) {
            double sl = g_fvgWick ? Low[shift + SNAP_BARS] : Close[shift + SNAP_BARS];
            if (sl < f.lagTop) f.lagTop = MathMax(sl, f.lagBottom);
        } else {
            double sh = g_fvgWick ? High[shift + SNAP_BARS] : Close[shift + SNAP_BARS];
            if (sh > f.lagBottom) f.lagBottom = MathMin(sh, f.lagTop);
        }
    }
}

//+------------------------------------------------------------------+
//| Finish entire chain                                              |
//+------------------------------------------------------------------+
void FinishChain(int cid, int shift) {
    for (int i = 0; i < ArraySize(g_segs); i++) {
        if (g_segs[i].chainId == cid && !g_segs[i].done) {
            g_segs[i].done = true;
            g_segs[i].state = STATE_INVALID; // Invalidate engine on mitigation

            if (g_segs[i].markName != "") {
                ObjectDelete(g_segs[i].markName);
                g_segs[i].markName = "";
            }

            if (showMitigated) {
                if (g_segs[i].active) {
                    if (g_segs[i].bxName != "")
                        ObjectSet(g_segs[i].bxName, OBJPROP_TIME2, Time[shift]);
                    if (g_segs[i].eqName != "")
                        ObjectSet(g_segs[i].eqName, OBJPROP_TIME2, Time[shift]);
                }
                DimSegment(g_segs[i]);
            } else {
                ClearSegment(g_segs[i]);
            }
            g_segs[i].active = false;
        }
    }
}

//+------------------------------------------------------------------+
//| Trim arrays                                                      |
//+------------------------------------------------------------------+
void TrimFvgs() {
    while (ArraySize(g_fvgs) > MAX_FVGS) {
        for (int j = 0; j < ArraySize(g_fvgs) - 1; j++)
            g_fvgs[j] = g_fvgs[j + 1];
        ArrayResize(g_fvgs, ArraySize(g_fvgs) - 1);
    }
}

void TrimSegments() {
    while (ArraySize(g_segs) > MAX_SEGMENTS) {
        ClearSegment(g_segs[0]);
        for (int j = 0; j < ArraySize(g_segs) - 1; j++)
            g_segs[j] = g_segs[j + 1];
        ArrayResize(g_segs, ArraySize(g_segs) - 1);
    }
}

//+------------------------------------------------------------------+
//| Debug & Entry Draw Helpers                                       |
//+------------------------------------------------------------------+
void DrawDebugText(Segment &s, datetime t, double price, string msg) {
    if (!DebugMode) return;
    if (s.debugMarkName == "") s.debugMarkName = NewName("dbg");
    
    ObjectCreate(s.debugMarkName, OBJ_TEXT, 0, t, price);
    ObjectSet(s.debugMarkName, OBJPROP_TIME1, t);
    ObjectSet(s.debugMarkName, OBJPROP_PRICE1, price);
    ObjectSetText(s.debugMarkName, msg, 8, "Arial", C'200,200,200');
}

void DrawEntryArrow(Segment &s, datetime t, double price) {
    if (!showEntryArrows) return; // Skip drawing if disabled
    if (s.entryMarkName == "") s.entryMarkName = NewName("entry");
    
    ObjectCreate(s.entryMarkName, OBJ_ARROW, 0, t, price);
    ObjectSet(s.entryMarkName, OBJPROP_ARROWCODE, (s.dir == 1) ? 233 : 234);
    ObjectSet(s.entryMarkName, OBJPROP_COLOR, (s.dir == 1) ? bullZoneCol : bearZoneCol);
    ObjectSet(s.entryMarkName, OBJPROP_WIDTH, 4); // Big arrow
}

//+------------------------------------------------------------------+
//| STATE MACHINE: Entry Engine                                      |
//+------------------------------------------------------------------+
void ProcessStateMachine(int i, int shift, double atr) {
    if (g_segs[i].state == STATE_INVALID || g_segs[i].state == STATE_ENTRY_TRIGGERED) return;

    double range = High[shift] - Low[shift];
    double body = MathAbs(Close[shift] - Open[shift]);

    if (g_segs[i].dir == 1) { // BULLISH ENGINE
        
        switch (g_segs[i].state) {
            case STATE_WAIT_SWEEP: {
                int lowestIdx = iLowest(Symbol(), 0, MODE_LOW, SweepLookback, shift + 1);
                double swingLow = Low[lowestIdx];
                
                if (Low[shift] < swingLow - (atr * SweepMinATR) && Low[shift] <= g_segs[i].top) {
                    g_segs[i].state = STATE_WAIT_REJECTION;
                    g_segs[i].sweepLevel = Low[shift];
                    g_segs[i].score += (Low[shift] < swingLow - (atr * 0.5)) ? 20 : 10;
                    DrawDebugText(g_segs[i], Time[shift], Low[shift] - atr, "SWEEP");
                }
                break;
            }
            case STATE_WAIT_REJECTION: {
                if (Close[shift] < g_segs[i].bottom) {
                    g_segs[i].state = STATE_INVALID; // Broken zone
                    DrawDebugText(g_segs[i], Time[shift], Low[shift] - atr, "INV: Broken");
                } else if (Close[shift] >= Open[shift] && Close[shift] > g_segs[i].bottom) {
                    double closePct = (range > 0) ? (Close[shift] - Low[shift]) / range : 0;
                    if (closePct > 0.5) {
                        g_segs[i].state = STATE_WAIT_STRUCTURE;
                        int highestIdx = iHighest(Symbol(), 0, MODE_HIGH, StructureLookback, shift + 1);
                        g_segs[i].bosLevel = High[highestIdx];
                        g_segs[i].score += (closePct >= 0.75) ? 15 : 10;
                        DrawDebugText(g_segs[i], Time[shift], Low[shift] - atr, "REJ -> Wait BOS: " + DoubleToStr(g_segs[i].bosLevel, Digits));
                    }
                }
                break;
            }
            case STATE_WAIT_STRUCTURE: {
                if (Low[shift] < g_segs[i].sweepLevel) {
                    g_segs[i].state = STATE_WAIT_REJECTION; // Re-swept
                    g_segs[i].sweepLevel = Low[shift];
                    DrawDebugText(g_segs[i], Time[shift], Low[shift] - atr, "RE-SWEEP");
                } else if (Close[shift] > g_segs[i].bosLevel) {
                    if (range >= atr * DisplacementATR && body >= atr * DisplacementBodyATR) {
                        g_segs[i].state = STATE_WAIT_RETEST;
                        g_segs[i].score += 20; // BOS
                        g_segs[i].score += (body >= atr) ? 15 : 10; // Disp
                        DrawDebugText(g_segs[i], Time[shift], Low[shift] - atr, "BOS+DISP");
                    } else {
                        g_segs[i].state = STATE_INVALID; // Weak break
                        DrawDebugText(g_segs[i], Time[shift], Low[shift] - atr, "INV: Weak Break");
                    }
                }
                break;
            }
            case STATE_WAIT_RETEST: {
                if (Low[shift] <= g_segs[i].top) {
                    g_segs[i].score += 15; // Retest points
                    
                    bool htfOk = true;
                    if (UseHTFBias) {
                        int htfShift = iBarShift(Symbol(), HTF, Time[shift]);
                        double htfEMA = iMA(Symbol(), HTF, 20, 0, MODE_EMA, PRICE_CLOSE, htfShift + 1);
                        double htfClose = iClose(Symbol(), HTF, htfShift + 1);
                        htfOk = (htfClose > htfEMA);
                    }
                    
                    if (g_segs[i].score >= MinEntryScore && htfOk) {
                        g_segs[i].state = STATE_ENTRY_TRIGGERED;
                        g_evEntry = true;
                        DrawEntryArrow(g_segs[i], Time[shift], Low[shift] - atr);
                        DrawDebugText(g_segs[i], Time[shift], Low[shift] - (atr * 1.5), "BUY ENTRY | Score: " + IntegerToString(g_segs[i].score));
                    } else {
                        g_segs[i].state = STATE_INVALID;
                        DrawDebugText(g_segs[i], Time[shift], Low[shift] - atr, "INV: Low Score/HTF");
                    }
                }
                break;
            }
        }
    } 
    else { // BEARISH ENGINE
        
        switch (g_segs[i].state) {
            case STATE_WAIT_SWEEP: {
                int highestIdx = iHighest(Symbol(), 0, MODE_HIGH, SweepLookback, shift + 1);
                double swingHigh = High[highestIdx];
                
                if (High[shift] > swingHigh + (atr * SweepMinATR) && High[shift] >= g_segs[i].bottom) {
                    g_segs[i].state = STATE_WAIT_REJECTION;
                    g_segs[i].sweepLevel = High[shift];
                    g_segs[i].score += (High[shift] > swingHigh + (atr * 0.5)) ? 20 : 10;
                    DrawDebugText(g_segs[i], Time[shift], High[shift] + atr, "SWEEP");
                }
                break;
            }
            case STATE_WAIT_REJECTION: {
                if (Close[shift] > g_segs[i].top) {
                    g_segs[i].state = STATE_INVALID;
                    DrawDebugText(g_segs[i], Time[shift], High[shift] + atr, "INV: Broken");
                } else if (Close[shift] <= Open[shift] && Close[shift] < g_segs[i].top) {
                    double closePct = (range > 0) ? (High[shift] - Close[shift]) / range : 0; // pct from top
                    if (closePct > 0.5) {
                        g_segs[i].state = STATE_WAIT_STRUCTURE;
                        int lowestIdx = iLowest(Symbol(), 0, MODE_LOW, StructureLookback, shift + 1);
                        g_segs[i].bosLevel = Low[lowestIdx];
                        g_segs[i].score += (closePct >= 0.75) ? 15 : 10;
                        DrawDebugText(g_segs[i], Time[shift], High[shift] + atr, "REJ -> Wait BOS: " + DoubleToStr(g_segs[i].bosLevel, Digits));
                    }
                }
                break;
            }
            case STATE_WAIT_STRUCTURE: {
                if (High[shift] > g_segs[i].sweepLevel) {
                    g_segs[i].state = STATE_WAIT_REJECTION; // Re-swept
                    g_segs[i].sweepLevel = High[shift];
                    DrawDebugText(g_segs[i], Time[shift], High[shift] + atr, "RE-SWEEP");
                } else if (Close[shift] < g_segs[i].bosLevel) {
                    if (range >= atr * DisplacementATR && body >= atr * DisplacementBodyATR) {
                        g_segs[i].state = STATE_WAIT_RETEST;
                        g_segs[i].score += 20; 
                        g_segs[i].score += (body >= atr) ? 15 : 10; 
                        DrawDebugText(g_segs[i], Time[shift], High[shift] + atr, "BOS+DISP");
                    } else {
                        g_segs[i].state = STATE_INVALID; 
                        DrawDebugText(g_segs[i], Time[shift], High[shift] + atr, "INV: Weak Break");
                    }
                }
                break;
            }
            case STATE_WAIT_RETEST: {
                if (High[shift] >= g_segs[i].bottom) {
                    g_segs[i].score += 15;
                    
                    bool htfOk = true;
                    if (UseHTFBias) {
                        int htfShift = iBarShift(Symbol(), HTF, Time[shift]);
                        double htfEMA = iMA(Symbol(), HTF, 20, 0, MODE_EMA, PRICE_CLOSE, htfShift + 1);
                        double htfClose = iClose(Symbol(), HTF, htfShift + 1);
                        htfOk = (htfClose < htfEMA);
                    }
                    
                    if (g_segs[i].score >= MinEntryScore && htfOk) {
                        g_segs[i].state = STATE_ENTRY_TRIGGERED;
                        g_evEntry = true;
                        DrawEntryArrow(g_segs[i], Time[shift], High[shift] + atr);
                        DrawDebugText(g_segs[i], Time[shift], High[shift] + (atr * 1.5), "SELL ENTRY | Score: " + IntegerToString(g_segs[i].score));
                    } else {
                        g_segs[i].state = STATE_INVALID;
                        DrawDebugText(g_segs[i], Time[shift], High[shift] + atr, "INV: Low Score/HTF");
                    }
                }
                break;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Core per-bar processor                                           |
//+------------------------------------------------------------------+
void ProcessBar(int shift, int absIdx) {
    if (shift + 2 >= Bars) return;
    g_absIdx = absIdx;

    double t = 0, b = 0;
    int i, j, k, sz, nSeg, res;
    bool consumed, hasNew;

    //--- 1. lag-mitigate waiting base FVGs
    for (k = ArraySize(g_fvgs) - 1; k >= 0; k--) {
        LagMitigate(g_fvgs[k], shift);
        if (g_fvgs[k].lagTop <= g_fvgs[k].lagBottom) {
            for (j = k; j < ArraySize(g_fvgs) - 1; j++)
                g_fvgs[j] = g_fvgs[j + 1];
            ArrayResize(g_fvgs, ArraySize(g_fvgs) - 1);
        }
    }

    //--- 2. detect new FVG 
    FVG nf;
    nf.dir = 0; nf.top = 0; nf.bottom = 0;
    nf.lagTop = 0; nf.lagBottom = 0;
    nf.startIdx = 0; nf.anchorTopTime = 0; nf.anchorBotTime = 0;
    hasNew = false;

    if (!IsBlockGap(shift)) { 
        if (Low[shift] > High[shift + 2]) {
            t = Low[shift];
            b = High[shift + 2];
            if ((t - b) / Close[shift] * 100.0 >= minGap) {
                nf.dir = 1; nf.top = t; nf.bottom = b;
                nf.lagTop = t; nf.lagBottom = b;
                nf.startIdx = absIdx;
                nf.anchorTopTime = Time[shift];
                nf.anchorBotTime = Time[shift + 2];
                hasNew = true;
            }
        } else if (High[shift] < Low[shift + 2]) {
            t = Low[shift + 2];
            b = High[shift];
            if ((t - b) / Close[shift] * 100.0 >= minGap) {
                nf.dir = -1; nf.top = t; nf.bottom = b;
                nf.lagTop = t; nf.lagBottom = b;
                nf.startIdx = absIdx;
                nf.anchorTopTime = Time[shift + 2];
                nf.anchorBotTime = Time[shift];
                hasNew = true;
            }
        }
    }

    if (hasNew) {
        consumed = false;

        //--- 3. flip opposite live zones
        nSeg = ArraySize(g_segs);
        for (i = 0; i < nSeg; i++) {
            if (g_segs[i].active && !g_segs[i].done && g_segs[i].dir == -nf.dir) {
                if (FlipSegment(i, nf, shift)) {
                    consumed = true;
                    g_evFlip = true;
                }
            }
        }

        //--- 4. strike opposite base FVGs
        for (i = ArraySize(g_fvgs) - 1; i >= 0; i--) {
            if (g_fvgs[i].dir == -nf.dir) {
                res = MakeChain(g_fvgs[i], nf, shift);
                if (res == 1) { g_evNew = true; g_chainSeq++; }
                if (res != 0) {
                    consumed = true;
                    for (j = i; j < ArraySize(g_fvgs) - 1; j++)
                        g_fvgs[j] = g_fvgs[j + 1];
                    ArrayResize(g_fvgs, ArraySize(g_fvgs) - 1);
                }
            }
        }

        //--- 5. keep as new base if not consumed
        if (!consumed) {
            sz = ArraySize(g_fvgs);
            ArrayResize(g_fvgs, sz + 1);
            g_fvgs[sz] = nf;
        }
    }

    //--- 6. Zone Touch (Visual Retest) & Mitigation Check
    double hiSrc = g_zoneWick ? High[shift] : Close[shift];
    double loSrc = g_zoneWick ? Low[shift]  : Close[shift];
    double atr = iATR(Symbol(), 0, 14, shift);
    if(atr == 0) atr = Point * 20; 

    for (i = 0; i < ArraySize(g_segs); i++) {
        if (g_segs[i].active && !g_segs[i].done && g_segs[i].createIdx < absIdx) {
            
            // Check Mitigation FIRST (invalidates state machine)
            bool mitigated = (g_segs[i].dir == 1) ? (loSrc <= g_segs[i].bottom) : (hiSrc >= g_segs[i].top);
            if (mitigated) {
                g_evMitig = true;
                FinishChain(g_segs[i].chainId, shift);
                continue; 
            }

            // Visual Touch (Arrows)
            bool touch = (High[shift] >= g_segs[i].bottom && Low[shift] <= g_segs[i].top);
            if (touch && !g_segs[i].touching) {
                g_evRetest = true;
                if (retestMarks) {
                    string rname = NewName("rt");
                    datetime tm = Time[shift];
                    double yp = (g_segs[i].dir == 1) ? Low[shift] - (atr * 0.5) : High[shift] + (atr * 0.5);
                    
                    ObjectCreate(rname, OBJ_ARROW, 0, tm, yp);
                    if (g_segs[i].dir == 1) {
                        ObjectSet(rname, OBJPROP_ARROWCODE, 233);
                        ObjectSet(rname, OBJPROP_COLOR, bullZoneCol);
                    } else {
                        ObjectSet(rname, OBJPROP_ARROWCODE, 234);
                        ObjectSet(rname, OBJPROP_COLOR, bearZoneCol);
                    }
                    ObjectSet(rname, OBJPROP_WIDTH, 1);
                    
                    if(g_segs[i].retestCount >= MAX_RETEST) {
                        ObjectDelete(g_segs[i].retestNames[0]);
                        for(int r = 0; r < MAX_RETEST - 1; r++) {
                            g_segs[i].retestNames[r] = g_segs[i].retestNames[r+1];
                        }
                        g_segs[i].retestCount--;
                    }
                    g_segs[i].retestNames[g_segs[i].retestCount] = rname;
                    g_segs[i].retestCount++;
                }
            }
            g_segs[i].touching = touch;

            // STATE MACHINE ENGINE: Process Entry Validations
            ProcessStateMachine(i, shift, atr);
        }
    }

    TrimFvgs();
    TrimSegments();
}

//+------------------------------------------------------------------+
//| Live visuals                                                     |
//+------------------------------------------------------------------+
void UpdateLiveVisuals() {
    for (int i = 0; i < ArraySize(g_segs); i++) {
        if (g_segs[i].active && !g_segs[i].done) {
            if (g_segs[i].bxName != "")
                ObjectSet(g_segs[i].bxName, OBJPROP_TIME2, Time[0]);
            if (g_segs[i].eqName != "")
                ObjectSet(g_segs[i].eqName, OBJPROP_TIME2, Time[0]);

            color zc = (g_segs[i].dir == 1) ? bullZoneCol : bearZoneCol;
            string txt = StarText(g_segs[i].flips);
            double my = (g_segs[i].dir == 1) ? g_segs[i].bottom : g_segs[i].top;

            if (g_segs[i].markName == "") {
                g_segs[i].markName = NewName("mk");
                ObjectCreate(g_segs[i].markName, OBJ_TEXT, 0, Time[0], my);
                ObjectSetText(g_segs[i].markName, txt, 8, "Arial", zc);
            } else {
                ObjectSet(g_segs[i].markName, OBJPROP_TIME1, Time[0]);
                ObjectSet(g_segs[i].markName, OBJPROP_PRICE1, my);
                ObjectSetText(g_segs[i].markName, txt, 8, "Arial", zc);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Rebuild history                                                  |
//+------------------------------------------------------------------+
void FullRebuild() {
    DeleteAllObjects();
    ArrayResize(g_fvgs, 0);
    ArrayResize(g_segs, 0);
    g_chainSeq = 0;
    g_absIdx   = 0;
    g_nameCounter = 0;

    int startShift = MathMin(lookback, Bars - 3);
    if (startShift < 1) return;

    for (int i = startShift; i >= 1; i--) {
        ProcessBar(i, g_absIdx);
        g_absIdx++;
    }
    UpdateLiveVisuals();
}

//+------------------------------------------------------------------+
//| Alerts                                                           |
//+------------------------------------------------------------------+
void FireAlerts() {
    if (g_suppressAlerts) return;
    string sym = Symbol() + " " + IntegerToString(Period());

    if (alertNew    && g_evNew)    Alert("FVG Crossfire [" + sym + "]: New crossfire zone formed.");
    if (alertFlip   && g_evFlip)   Alert("FVG Crossfire [" + sym + "]: Zone flipped direction.");
    if (alertRetest && g_evRetest) Alert("FVG Crossfire [" + sym + "]: Price touched a live zone.");
    if (alertMitig  && g_evMitig)  Alert("FVG Crossfire [" + sym + "]: Zone mitigated/invalidated.");
    if (alertEntry  && g_evEntry)  Alert("FVG ENTRY CONFIRMED [" + sym + "]: Valid Rejection + BOS + Retest.");

    g_evNew = false; g_evFlip = false; g_evRetest = false; g_evMitig = false; g_evEntry = false;
}

//+------------------------------------------------------------------+
//| Standard handlers                                                |
//+------------------------------------------------------------------+
int OnInit() {
    g_fvgWick  = (fvgMitig  == MITIG_WICK);
    g_zoneWick = (zoneMitig == MITIG_WICK);

    DeleteAllObjects();

    g_suppressAlerts = true;
    FullRebuild();
    g_suppressAlerts = false;

    g_lastBarTime = (Bars > 0) ? Time[0] : 0;
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    DeleteAllObjects();
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    if (Bars < 10) return rates_total;

    // Strict close-only evaluation (shift 1)
    if (Time[0] != g_lastBarTime) {
        g_lastBarTime = Time[0];
        g_evNew = false; g_evFlip = false; g_evRetest = false; g_evMitig = false; g_evEntry = false;

        ProcessBar(1, g_absIdx);
        g_absIdx++;

        FireAlerts();
    }

    UpdateLiveVisuals();
    return rates_total;
}
