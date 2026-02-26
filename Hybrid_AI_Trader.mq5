//+------------------------------------------------------------------+
//|                                              Hybrid_AI_Trader.mq5 |
//|                                  Copyright 2026, Quant Developer |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property copyright "Quant Developer"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Professional Hybrid EA (Swing + Scalping + AI)"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\DealInfo.mqh>

//--- Enums
enum ENUM_REGIME {
   REGIME_NONE = 0,
   REGIME_TREND = 1,
   REGIME_RANGE = 2
};

//--- Inputs
input group "=== Risk Management ==="
input double   InpRiskPercent       = 1.0;      // Swing Risk % (1%)
input double   InpScalpRiskPercent  = 0.4;      // Scalp Risk % (0.3-0.5%)
input double   InpMaxDailyLoss      = 5.0;      // Max Daily Loss %
input int      InpMaxSwingTradesDay = 5;        // Max Swing Trades/Day
input int      InpMaxScalpTradesDay = 15;       // Max Scalp Trades/Day
input int      InpMaxTradesPerSymbol= 2;        // Max Trades/Symbol
input int      InpMaxSpreadPoints   = 10;       // Max Spread (Points)

input group "=== AI Settings ==="
input string   InpAIServerURL       = "http://127.0.0.1:5001"; // Python API URL
input string   InpAISecretKey       = "6755e4775cc3687a48199ef08369a982"; // AI Auth Key
input double   InpSwingProbThresh   = 0.60;     // Swing AI Threshold
input double   InpScalpProbThresh   = 0.75;     // Scalp AI Threshold

input group "=== Trading Sessions (Broker Time) ==="
input int      InpLondonStartHour   = 9;        // London Start Hour
input int      InpNYStartHour       = 14;       // NY Start Hour
input int      InpTradeDurationHours= 4;        // Trade Duration (Hours)

input group "=== Strategy Parameters ==="
input ulong    InpMagicNumber       = 777777;   // Magic Number
input int      InpATRPeriod         = 16;       // ATR Period
input int      InpADXPeriod         = 37;       // ADX Period
input int      InpEMAFastPeriod     = 50;       // EMA Fast Period
input int      InpEMASlowPeriod     = 200;      // EMA Slow Period
input int      InpRSIPeriod         = 62;       // RSI Period
input int      InpBandsPeriod       = 20;       // Bollinger Bands Period
input double   InpBandsDeviations   = 2.0;      // Bollinger Bands Dev
input double   InpSwingSLMult       = 3.60;     // Swing SL Multiplier (ATR)
input double   InpSwingTPMult       = 26.4;     // Swing TP Multiplier (ATR)
input double   InpScalpSLMult       = 3.48;     // Scalp SL Multiplier (ATR)
input double   InpScalpTPMult       = 2.72;     // Scalp TP Multiplier (ATR)

input group "=== Trade Management ==="
input bool     InpUseBreakeven      = true;     // Use Breakeven
input double   InpBreakevenActivation = 6.5;    // BE Activation (ATR)
input bool     InpUseTrailingStop   = false;    // Use Trailing Stop
input double   InpTrailingStopStep  = 3.10;     // Trailing Step (ATR)
input bool     InpUseEarlyExit      = false;    // Use Early Exit

input group "=== Telegram ==="
input string   InpTelegramBotToken  = "8575836113:AAFa8bi7Mjla9L9Faqk4e9wEzww9-l_AWuA"; // Bot Token
input string   InpTelegramChatID    = "1385914494";    // Chat ID
input bool     InpUseTelegram       = true;     // Enable Telegram

//--- Global Objects
CTrade         trade;
CSymbolInfo    symInfo;
CPositionInfo  posInfo;
CAccountInfo   accInfo;
CDealInfo      dealInfo;

//--- Indicator Handles
int handle_atr, handle_adx, handle_ema50, handle_ema200, handle_rsi, handle_bands;

//--- State variables
int swingTradesToday = 0;
int scalpTradesToday = 0;
datetime lastTradeDay = 0;

//--- Function Prototypes
bool         SessionFilter();
bool         SpreadFilter();
ENUM_REGIME  RegimeDetector();
void         SwingModule(bool &signalLong, bool &signalShort, double &sl, double &tp);
void         ScalpingModule(bool &signalLong, bool &signalShort, double &sl, double &tp);
double       RiskManagerSeparate(double sl_price, double risk_percent);
void         TradeManager();
string       FeatureExtractor();
double       GetAIProbability(string strategyType);
void         TelegramNotifier(string message);
void         LogData(datetime time, ENUM_REGIME regime, double aiProb, string action, string reason="");
int          CountSymbolPositions();
void         ResetDailyCounters(datetime currentTime);
bool         IsDailyLossLimitReached();

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   symInfo.Name(_Symbol);
   symInfo.Refresh();
   trade.SetExpertMagicNumber(InpMagicNumber);
   // trade.SetMarginMode(); // Automatically handled by CTrade for most setups
   trade.SetTypeFillingBySymbol(_Symbol);

   // Initialize Indicators
   handle_atr = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   handle_adx = iADX(_Symbol, PERIOD_CURRENT, InpADXPeriod);
   handle_ema50 = iMA(_Symbol, PERIOD_CURRENT, InpEMAFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handle_ema200 = iMA(_Symbol, PERIOD_CURRENT, InpEMASlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handle_rsi = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   handle_bands = iBands(_Symbol, PERIOD_CURRENT, InpBandsPeriod, 0, InpBandsDeviations, PRICE_CLOSE);

   if(handle_atr == INVALID_HANDLE || handle_adx == INVALID_HANDLE ||
      handle_ema50 == INVALID_HANDLE || handle_ema200 == INVALID_HANDLE ||
      handle_rsi == INVALID_HANDLE || handle_bands == INVALID_HANDLE)
     {
      Print("Error creating indicators!");
      return(INIT_FAILED);
     }

   Print("Hybrid AI EA Initialized Successfully.");
   
   // --- Startup Health Check (Test AI Connectivity) ---
   Print("Testing AI Server Connection...");
   double testProb = GetAIProbability("swing"); // Simple test call
   if(testProb >= 0.0) Print("✅ AI Server Connectivity: OK");
   else Print("❌ AI Server Connectivity: FAILED (Check URL Permissions)");
   
   // --- Startup Telegram Notification ---
   string accType = (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO) ? "DEMO" : "REAL";
   string startupMsg = StringFormat("🚀 **Hybrid AI EA Online**\n" +
                                     "Symbol: %s\n" +
                                     "Account: %d (%s)\n" +
                                     "Mode: AI Filtering Active", 
                                     _Symbol, AccountInfoInteger(ACCOUNT_LOGIN), accType);
   TelegramNotifier(startupMsg);
   
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   IndicatorRelease(handle_atr);
   IndicatorRelease(handle_adx);
   IndicatorRelease(handle_ema50);
   IndicatorRelease(handle_ema200);
   IndicatorRelease(handle_rsi);
   IndicatorRelease(handle_bands);
  }

//+------------------------------------------------------------------+
//| Main Logic OnTick                                                |
//+------------------------------------------------------------------+
void OnTick()
  {
   symInfo.RefreshRates();
   
   // Real-time protection (runs on every tick)
   TradeManager();

   // 1. Check if New Bar (Signal logic only on bar close)
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(lastBarTime == currentBarTime) return; 
   
   if(lastBarTime == 0) { lastBarTime = currentBarTime; return; } 
   
   ResetDailyCounters(currentBarTime);
   PrintFormat("🔍 Scanning [New Bar: %s]. Regime: %s", TimeToString(currentBarTime), EnumToString(RegimeDetector()));
 
   // 2. Risk Management - Max Loss Check
   if(IsDailyLossLimitReached())
     {
      return;
     }

   // 3. Spread Filter Check
   if(!SpreadFilter())
     {
      LogData(currentBarTime, REGIME_NONE, 0, "Rejected", "Spread > " + IntegerToString(InpMaxSpreadPoints) + " pts");
      lastBarTime = currentBarTime;
      return; 
     }

   // 4. Determine Market Regime
   ENUM_REGIME regime = RegimeDetector();
   if(regime == REGIME_NONE) {
      lastBarTime = currentBarTime;
      return;
   }

   // 5. Evaluate Strategy based on Regime
   bool signalLong = false;
   bool signalShort = false;
   double sl = 0, tp = 0;
   string strategyName = "";
   double ai_prob = 0;

   if(regime == REGIME_TREND)
     {
      strategyName = "SWING";
      if(swingTradesToday >= InpMaxSwingTradesDay) { lastBarTime = currentBarTime; return; }
      
      SwingModule(signalLong, signalShort, sl, tp);
      
      if(signalLong || signalShort)
        {
         string side = signalLong ? "BUY" : "SELL";
         TelegramNotifier(StringFormat("🎯 [%s %s] Signal detected. Evaluating with AI...", strategyName, side));
         
         ai_prob = GetAIProbability("swing");
         if(ai_prob < InpSwingProbThresh)
           {
            TelegramNotifier(StringFormat("⚠️ [%s %s] Trade Filtered by AI. Prob: %.2f (Min: %.2f)", 
                                          strategyName, side, ai_prob, InpSwingProbThresh));
            LogData(currentBarTime, regime, ai_prob, "Rejected", "Swing AI Prob < " + DoubleToString(InpSwingProbThresh, 2));
            signalLong = false; signalShort = false;
           }
        }
     }
   else if(regime == REGIME_RANGE)
     {
      strategyName = "SCALP";
      if(scalpTradesToday >= InpMaxScalpTradesDay) { lastBarTime = currentBarTime; return; }
      if(!SessionFilter()) { lastBarTime = currentBarTime; return; } // Scalping only in active sessions
      
      ScalpingModule(signalLong, signalShort, sl, tp);
      
      if(signalLong || signalShort)
        {
         string side = signalLong ? "BUY" : "SELL";
         TelegramNotifier(StringFormat("🎯 [%s %s] Signal detected. Evaluating with AI...", strategyName, side));
         
         ai_prob = GetAIProbability("scalping");
         if(ai_prob < InpScalpProbThresh)
           {
            TelegramNotifier(StringFormat("⚠️ [%s %s] Trade Filtered by AI. Prob: %.2f (Min: %.2f)", 
                                          strategyName, side, ai_prob, InpScalpProbThresh));
            LogData(currentBarTime, regime, ai_prob, "Rejected", "Scalping AI Prob < " + DoubleToString(InpScalpProbThresh, 2));
            signalLong = false; signalShort = false;
           }
        }
     }

   // 6. Execution
   if(signalLong || signalShort)
     {
      if(CountSymbolPositions() >= InpMaxTradesPerSymbol)
        {
         LogData(currentBarTime, regime, ai_prob, "Rejected", "Max symbol positions reached");
         lastBarTime = currentBarTime;
         return;
        }

      double riskPct = (regime == REGIME_TREND) ? InpRiskPercent : InpScalpRiskPercent;
      double lotSize = RiskManagerSeparate(sl, riskPct);

      if(lotSize > 0)
        {
         if(signalLong)
           {
            if(trade.Buy(lotSize, _Symbol, symInfo.Ask(), sl, tp, strategyName))
              {
               if(regime == REGIME_TREND) swingTradesToday++; else scalpTradesToday++;
               // Telegram: SIGNAL + OPEN
               TelegramNotifier(StringFormat("🔔 [%s BUY][AI %.2f] Signal detected. Opening %.2f lots", strategyName, ai_prob, lotSize));
               LogData(currentBarTime, regime, ai_prob, "Executed Long", "OK");
              }
            else { 
               TelegramNotifier(StringFormat("❌ [%s BUY][AI %.2f] Order Rejected: %d", strategyName, ai_prob, trade.ResultRetcode()));
               LogData(currentBarTime, regime, ai_prob, "Rejected", "Trade Error: " + IntegerToString(trade.ResultRetcode())); 
            }
           }
         else if(signalShort)
           {
            if(trade.Sell(lotSize, _Symbol, symInfo.Bid(), sl, tp, strategyName))
              {
               if(regime == REGIME_TREND) swingTradesToday++; else scalpTradesToday++;
               // Telegram: SIGNAL + OPEN
               TelegramNotifier(StringFormat("🔔 [%s SELL][AI %.2f] Signal detected. Opening %.2f lots", strategyName, ai_prob, lotSize));
               LogData(currentBarTime, regime, ai_prob, "Executed Short", "OK");
              }
            else { 
               TelegramNotifier(StringFormat("❌ [%s SELL][AI %.2f] Order Rejected: %d", strategyName, ai_prob, trade.ResultRetcode()));
               LogData(currentBarTime, regime, ai_prob, "Rejected", "Trade Error: " + IntegerToString(trade.ResultRetcode())); 
            }
           }
        }
      else { LogData(currentBarTime, regime, ai_prob, "Rejected", "RiskManager lot size calculation returned 0"); }
     }

   // 7. Trade Management
   TradeManager();
   
   lastBarTime = currentBarTime;
  }

//+------------------------------------------------------------------+
//| Modules                                                          |
//+------------------------------------------------------------------+

//--- Check if within London or NY first 2 hours
bool SessionFilter()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   bool isLondon = (dt.hour >= InpLondonStartHour && dt.hour < InpLondonStartHour + InpTradeDurationHours);
   bool isNY = (dt.hour >= InpNYStartHour && dt.hour < InpNYStartHour + InpTradeDurationHours);
   
   return isLondon || isNY;
  }

//--- Check if current spread is acceptable
bool SpreadFilter()
  {
   // symInfo.Spread() is returned in points
   return (symInfo.Spread() <= InpMaxSpreadPoints);
  }

//--- Determine if market is Trending or Ranging
ENUM_REGIME RegimeDetector()
  {
   double adx[1];
   if(CopyBuffer(handle_adx, 0, 1, 1, adx) <= 0) return REGIME_NONE; // Main ADX line
   
   if(adx[0] > 25.0) return REGIME_TREND;
   if(adx[0] < 20.0) return REGIME_RANGE;
   
   PrintFormat("ℹ️ Market Neutral (ADX: %.2f). No trade signal.", adx[0]);
   return REGIME_NONE;
  }

//--- Swing Trading Logic (Trend following, Pullbacks)
void SwingModule(bool &signalLong, bool &signalShort, double &sl, double &tp)
  {
   double ema50[1], ema200[1], rsi[2], atr[1], close[1];
   if(CopyBuffer(handle_ema50, 0, 1, 1, ema50) <= 0) return;
   if(CopyBuffer(handle_ema200, 0, 1, 1, ema200) <= 0) return;
   if(CopyBuffer(handle_rsi, 0, 1, 2, rsi) <= 0) return;
   if(CopyBuffer(handle_atr, 0, 1, 1, atr) <= 0) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 1, 1, close) <= 0) return;

   // Uptrend
   if(ema50[0] > ema200[0])
     {
      // RSI pullback (e.g., crossing below 40 and then back up)
      if(rsi[0] < 45.0 && rsi[1] >= 45.0) 
        {
         signalLong = true;
         sl = symInfo.Ask() - (atr[0] * InpSwingSLMult);
         tp = symInfo.Ask() + (atr[0] * InpSwingTPMult);
         if (sl >= symInfo.Ask()) signalLong = false;
        }
     }
   // Downtrend
   else if(ema50[0] < ema200[0])
     {
      if(rsi[0] > 55.0 && rsi[1] <= 55.0)
        {
         signalShort = true;
         sl = symInfo.Bid() + (atr[0] * InpSwingSLMult);
         tp = symInfo.Bid() - (atr[0] * InpSwingTPMult);
         if (sl <= symInfo.Bid()) signalShort = false;
        }
     }
  }

//--- Scalping Trading Logic (Mean Reversion, Bollinger)
void ScalpingModule(bool &signalLong, bool &signalShort, double &sl, double &tp)
  {
   double upper[1], lower[1], atr[1], close[1];
   if(CopyBuffer(handle_bands, 1, 1, 1, upper) <= 0) return;
   if(CopyBuffer(handle_bands, 2, 1, 1, lower) <= 0) return;
   if(CopyBuffer(handle_atr, 0, 1, 1, atr) <= 0) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 1, 1, close) <= 0) return;

   // Simple Bollinger mean reversion
   if(close[0] <= lower[0])
     {
      signalLong = true;
      sl = symInfo.Ask() - (atr[0] * InpScalpSLMult);
      tp = symInfo.Ask() + (atr[0] * InpScalpTPMult);
      if (sl >= symInfo.Ask()) signalLong = false;
     }
   else if(close[0] >= upper[0])
     {
      signalShort = true;
      sl = symInfo.Bid() + (atr[0] * InpScalpSLMult);
      tp = symInfo.Bid() - (atr[0] * InpScalpTPMult);
      if (sl <= symInfo.Bid()) signalShort = false;
     }
  }

//--- Calculates exact lot size based on account risk and Stop Loss distance
double RiskManagerSeparate(double sl_price, double risk_percent)
  {
   if(sl_price == 0) return 0.0;
   
   double riskMoney = accInfo.Balance() * (risk_percent / 100.0);
   double tickValue = symInfo.TickValue();
   double tickSize = symInfo.TickSize();
   
   double currentPrice = (sl_price < symInfo.Bid()) ? symInfo.Ask() : symInfo.Bid();
   double slDistancePoints = MathAbs(currentPrice - sl_price) / symInfo.Point();
   
   if(slDistancePoints == 0 || tickValue == 0 || tickSize == 0) return 0.0;
   
   double lossPerLot = slDistancePoints * (tickValue / (tickSize / symInfo.Point()));
   if (lossPerLot == 0) return 0.0;
   
   double lotSize = riskMoney / lossPerLot;
   
   double minLot = symInfo.LotsMin();
   double maxLot = symInfo.LotsMax();
   double stepLot = symInfo.LotsStep();
   
   lotSize = MathFloor(lotSize / stepLot) * stepLot;
   
   if(lotSize < minLot) lotSize = minLot; // Enforce minimums rather than returning 0
   if(lotSize > maxLot) lotSize = maxLot;
   
   return lotSize;
  }

//--- Manages existing open trades (Breakeven, Trailing, Early Exit)
void TradeManager()
  {
   double atr[1];
   if(CopyBuffer(handle_atr, 0, 1, 1, atr) <= 0) return;
   
   // We might need fresh signals for Early Exit
   bool sigL=false, sigS=false;
   double dSL=0, dTP=0;
   ENUM_REGIME reg = RegimeDetector();
   if(InpUseEarlyExit && reg != REGIME_NONE)
     {
      if(reg == REGIME_TREND) SwingModule(sigL, sigS, dSL, dTP);
      else ScalpingModule(sigL, sigS, dSL, dTP);
     }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(posInfo.SelectByIndex(i))
        {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
           {
            double entry = posInfo.PriceOpen();
            double currentSL = posInfo.StopLoss();
            double currentTP = posInfo.TakeProfit();
            double currentBid = symInfo.Bid();
            double currentAsk = symInfo.Ask();
            
            // --- 1. Early Exit Logic ---
            if(InpUseEarlyExit)
              {
               if(posInfo.PositionType() == POSITION_TYPE_BUY && sigS)
                 {
                  trade.PositionClose(posInfo.Ticket());
                  TelegramNotifier("🚪 [Early Exit] BUY closed due to SELL signal.");
                  continue;
                 }
               if(posInfo.PositionType() == POSITION_TYPE_SELL && sigL)
                 {
                  trade.PositionClose(posInfo.Ticket());
                  TelegramNotifier("🚪 [Early Exit] SELL closed due to BUY signal.");
                  continue;
                 }
              }

            // --- 2. Breakeven & Trailing ---
            if(posInfo.PositionType() == POSITION_TYPE_BUY)
              {
               double profitPoints = (currentBid - entry) / symInfo.Point();
               double atrPoints = atr[0] / symInfo.Point();
               
               // Breakeven
               if(InpUseBreakeven && currentSL < entry && profitPoints >= (InpBreakevenActivation * atrPoints))
                 {
                  if(trade.PositionModify(posInfo.Ticket(), entry + (2 * symInfo.Point()), currentTP))
                    TelegramNotifier("🛡️ [Breakeven] SL moved to Entry + 2pts (BUY)");
                 }
               
               // Trailing Stop
               if(InpUseTrailingStop)
                 {
                  double trailDist = InpTrailingStopStep * atr[0];
                  double targetSL = currentBid - trailDist;
                  if(targetSL > currentSL && targetSL < currentBid - (5 * symInfo.Point()))
                    {
                     trade.PositionModify(posInfo.Ticket(), targetSL, currentTP);
                    }
                 }
              }
            else if(posInfo.PositionType() == POSITION_TYPE_SELL)
              {
               double profitPoints = (entry - currentAsk) / symInfo.Point();
               double atrPoints = atr[0] / symInfo.Point();
               
               // Breakeven
               if(InpUseBreakeven && (currentSL > entry || currentSL == 0) && profitPoints >= (InpBreakevenActivation * atrPoints))
                 {
                  if(trade.PositionModify(posInfo.Ticket(), entry - (2 * symInfo.Point()), currentTP))
                    TelegramNotifier("🛡️ [Breakeven] SL moved to Entry - 2pts (SELL)");
                 }
               
               // Trailing Stop
               if(InpUseTrailingStop)
                 {
                  double trailDist = InpTrailingStopStep * atr[0];
                  double targetSL = currentAsk + trailDist;
                  if((targetSL < currentSL || currentSL == 0) && targetSL > currentAsk + (5 * symInfo.Point()))
                    {
                     trade.PositionModify(posInfo.Ticket(), targetSL, currentTP);
                    }
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Python AI Communication                                          |
//+------------------------------------------------------------------+
string FeatureExtractor()
  {
   double atr[1], adx[1], ema200[2];
   long vol[1];
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   CopyBuffer(handle_atr, 0, 1, 1, atr);
   CopyBuffer(handle_adx, 0, 1, 1, adx);
   CopyBuffer(handle_ema200, 0, 1, 2, ema200);
   CopyTickVolume(_Symbol, PERIOD_CURRENT, 1, 1, vol);
   
   double slope = ema200[1] - ema200[0];
   double spread = symInfo.Spread();
   
   string json = StringFormat("{\"atr\":%.5f,\"adx\":%.2f,\"spread\":%.1f,\"ema_slope\":%.5f,\"volume\":%d,\"hour\":%d}",
                              atr[0], adx[0], spread, slope, vol[0], dt.hour);
   return json;
  }

double GetAIProbability(string strategyType)
  {
   // --- Mock Mode for Strategy Tester ---
   // The MT5 Tester blocks WebRequests. We return a high probability to test local logic.
   if(MQLInfoInteger(MQL_TESTER)) return 0.85;

   string json = FeatureExtractor();
   string url = InpAIServerURL + "/predict_" + strategyType;
   
   PrintFormat("📡 AI Request -> URL: %s | Body: %s", url, json);
   
   char data[];
   StringToCharArray(json, data, 0, StringLen(json));
   
   char result[];
   string resultHeaders;
   
   ResetLastError();
   ResetLastError();
   // Add X-API-Key to headers for security
   string headers = "Content-Type: application/json\r\n" + 
                    "X-API-Key: " + InpAISecretKey + "\r\n";
   
   // Increase timeout to 5000ms for Mac/Wine & clean headers
   int res = WebRequest("POST", url, headers, 5000, data, result, resultHeaders);
   
   if(res == 200)
     {
      string responseStr = CharArrayToString(result);
      Print("📥 AI Response: ", responseStr);

      int probIdx = StringFind(responseStr, "\"probability\"");
      if(probIdx >= 0)
        {
         int colonIdx = StringFind(responseStr, ":", probIdx);
         int endIdx = StringFind(responseStr, "}", colonIdx);
         if(colonIdx > 0 && endIdx > 0)
           {
            string probStr = StringSubstr(responseStr, colonIdx + 1, endIdx - colonIdx - 1);
            StringTrimLeft(probStr);
            StringTrimRight(probStr);
            double val = StringToDouble(probStr);
            PrintFormat("✅ AI Parsed Prob: %.4f", val);
            return val;
           }
        }
      // If probability not found or parsing failed, return error
      PrintFormat("⚠️ AI Response Parsing Error: Probability not found in response: %s", responseStr);
     }
   else
     {
      int lastErr = GetLastError();
      string advice = (res == -1 && lastErr == 5203) ? "Timeout: Server too slow or IP unreachable from Wine." : "Check URL Permissions in MT5 Options.";
      PrintFormat("⚠️ AI Connection Error %d | LastError: %d | URL: %s", res, lastErr, url);
      Print("Advice: ", advice);
      // Print raw body sent for debugging
      Print("AI Body Sent: ", json);
     }
   return -1.0; // Return error value
  }

//+------------------------------------------------------------------+
//| Transaction Monitoring                                           |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
  {
   // Monitor deals to detect closed positions
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      if(HistoryDealSelect(trans.deal))
        {
         long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
         if(magic == InpMagicNumber)
           {
            ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
            // Entry OUT means a position was closed
            if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
              {
               double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
               double commission = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
               double swap = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
               double netProfit = profit + commission + swap;
               
               string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
               string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT); // Stores "SWING" or "SCALP"
               
               string icon = (netProfit >= 0) ? "✅" : "🛑";
               string sign = (netProfit >= 0) ? "+" : "";
               
               // Probabilidad IA no está en el deal, pero podemos indicar el tipo de cierre
               string msg = StringFormat("%s [%s][%s] Trade Closed\nResult: %s%.2f$", 
                                         icon, comment, symbol, sign, netProfit);
               
               TelegramNotifier(msg);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Utilities                                                        |
//+------------------------------------------------------------------+
void TelegramNotifier(string message)
  {
   if(!InpUseTelegram || InpTelegramBotToken == "YOUR_TOKEN_HERE") return;
   
   string url = "https://api.telegram.org/bot" + InpTelegramBotToken + "/sendMessage";
   
   // Ensure proper encoding for specials and icons
   string body = "chat_id=" + InpTelegramChatID + "&text=" + message;
   char data[], result[];
   string resultHeaders;
   
   StringToCharArray(body, data, 0, StringLen(body));
   
   // Use POST for reliability and avoid URL length limits
   int res = WebRequest("POST", url, "Content-Type: application/x-www-form-urlencoded\r\n", 2000, data, result, resultHeaders);
   
   if(res != 200)
     {
      string errDesc = "";
      if(res == -1) errDesc = "Check Internet connection or URL Permissions in MT5 Options.";
      if(res == 401) errDesc = "Unauthorized: Your Bot Token is likely incorrect.";
      if(res == 400) errDesc = "Bad Request: Check Chat ID or message format.";
      
      PrintFormat("❌ Telegram Error %d: %s. %s", res, IntegerToString(GetLastError()), errDesc);
     }
  }

void LogData(datetime time, ENUM_REGIME regime, double aiProb, string action, string reason="")
  {
   string filename = "HybridEA_Log_" + _Symbol + ".csv";
   int fileHandle = FileOpen(filename, FILE_WRITE|FILE_READ|FILE_CSV|FILE_ANSI, ",");
   
   if(fileHandle != INVALID_HANDLE)
     {
      FileSeek(fileHandle, 0, SEEK_END);
      
      if(FileSize(fileHandle) == 0)
        {
         FileWrite(fileHandle, "Time", "Regime", "AI_Prob", "Action", "Reason");
        }
        
      string regimeStr = "NONE";
      if(regime == REGIME_TREND) regimeStr = "TREND";
      if(regime == REGIME_RANGE) regimeStr = "RANGE";
      
      FileWrite(fileHandle, TimeToString(time), regimeStr, DoubleToString(aiProb, 2), action, reason);
      FileClose(fileHandle);
     }
   else
     {
      Print("Failed to open Log file. Error: ", GetLastError());
     }
  }

int CountSymbolPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(posInfo.SelectByIndex(i))
        {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
           count++;
        }
     }
   return count;
  }

void ResetDailyCounters(datetime currentTime)
  {
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   
   MqlDateTime lastDt;
   TimeToStruct(lastTradeDay, lastDt);
   
   // Reset on new day
   if(dt.day_of_year != lastDt.day_of_year || dt.year != lastDt.year)
     {
      swingTradesToday = 0;
      scalpTradesToday = 0;
      lastTradeDay = currentTime;
     }
  }

bool IsDailyLossLimitReached()
  {
   if(lastTradeDay == 0) return false;
   datetime startOfDay = lastTradeDay - (lastTradeDay % 86400); 
   
   HistorySelect(startOfDay, TimeCurrent());
   double dailyProfit = 0;
   
   for(int i=0; i<HistoryDealsTotal(); i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol && HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber)
        {
         dailyProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
         dailyProfit += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         dailyProfit += HistoryDealGetDouble(ticket, DEAL_SWAP);
        }
     }
     
   double maxLossMoney = accInfo.Balance() * (InpMaxDailyLoss / 100.0);
   
   return (dailyProfit <= -maxLossMoney);
  }
//+------------------------------------------------------------------+
