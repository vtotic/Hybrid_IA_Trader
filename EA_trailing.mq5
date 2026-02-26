//+------------------------------------------------------------------+
//|                                                  EA_trailing.mq5 |
//|                                  Copyright 2026, Quant Developer |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Quant Developer"
#property link      "https://www.mql5.com"
#property version   "2.00"
#property strict
#property description "Expert Advisor Profesional - Scalping & Trailing"

#include <Trade\Trade.mqh>

//====================================================================
// INPUTS
//====================================================================
input group "=== Configuración Señal ==="
input int    filter_ema_period = 200;   // Periodo EMA de tendencia
input ENUM_TIMEFRAMES signal_tf = PERIOD_CURRENT; // Temporalidad de señal
input bool   usar_filtro_ruptura = false; // Confirmación de ruptura High/Low

input group "=== Gestión de Riesgo ==="
input double risk_percent     = 18.0;   // Riesgo por operación (%)
input int    sl_points        = 2824;   // Stop Loss Inicial (Puntos)
input ulong  magic_number     = 762422; // Número Mágico

input group "=== Gestión de Trade ==="
input int    breakeven_points = 805;    // Activación BreakEven (Puntos)
input int    be_lock_points   = 79;     // Puntos a asegurar en BE (Profit Lock)
input int    trailing_start   = 365;    // Puntos para iniciar Trailing Stop
input int    trailing_points  = 596;    // Distancia del Trailing (Puntos)
input int    partial_points   = 1647;   // Cierre Parcial al ganar (Puntos)
input double partial_percent  = 0.33;   // % a cerrar en parcial (0.33 = 33%)

//====================================================================
// VARIABLES GLOBALES
//====================================================================
CTrade trade;
int    handle_ema;
bool   is_partial_closed = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(magic_number);
   
   // Inicializar indicador EMA
   handle_ema = iMA(_Symbol, signal_tf, filter_ema_period, 0, MODE_EMA, PRICE_CLOSE);
   if(handle_ema == INVALID_HANDLE)
   {
      Print("Error al crear el indicador EMA");
      return(INIT_FAILED);
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Prioridad: Gestionar posición abierta lo más rápido posible
   if(PositionSelect(_Symbol))
   {
      if(PositionGetInteger(POSITION_MAGIC) == (long)magic_number)
      {
         ManagePosition();
      }
   }
   else
   {
      // 2. Si no hay posición, buscar nuevas señales
      int signal = GetSignal();
      if(signal != 0) OpenTrade(signal);
   }
}

//+------------------------------------------------------------------+
//| Lógica de Señal Refinada (Tendencia + Acción de Precio)          |
//+------------------------------------------------------------------+
int GetSignal()
{
   // Obtener valor de la EMA
   double ema_buffer[];
   ArraySetAsSeries(ema_buffer, true);
   if(CopyBuffer(handle_ema, 0, 0, 2, ema_buffer) < 2) return 0;
   
   // Datos de las velas
   double close1 = iClose(_Symbol, signal_tf, 1);
   double open1  = iOpen(_Symbol, signal_tf, 1);
   double high1  = iHigh(_Symbol, signal_tf, 1);
   double low1   = iLow(_Symbol, signal_tf, 1);
   double open0  = iOpen(_Symbol, signal_tf, 0);
   double price_current = iClose(_Symbol, signal_tf, 0);
   
   double ema_val = ema_buffer[0];
   
   // ESTRATEGIA REFINADA (MOMENTUM + BREAKOUT):
   bool trend_long  = (price_current > ema_val);
   bool pattern_long = (close1 > open1);
   bool momentum_long = (price_current > open0);
   bool breakout_long = (!usar_filtro_ruptura || price_current > high1);
   
   if(trend_long && pattern_long && momentum_long && breakout_long) 
      return 1;
   
   bool trend_short  = (price_current < ema_val);
   bool pattern_short = (close1 < open1);
   bool momentum_short = (price_current < open0);
   bool breakout_short = (!usar_filtro_ruptura || price_current < low1);
   
   if(trend_short && pattern_short && momentum_short && breakout_short) 
      return -1;
   
   return 0;
}

//+------------------------------------------------------------------+
//| Ejecución de entrada con gestión de lotaje                       |
//+------------------------------------------------------------------+
void OpenTrade(int signal)
{
   MqlTick last_tick;
   if(!SymbolInfoTick(_Symbol, last_tick)) return;

   double lots = CalculateLotSize(sl_points);
   if(lots <= 0) return;
   
   is_partial_closed = false;
   double price = (signal == 1) ? last_tick.ask : last_tick.bid;
   double sl    = (signal == 1) ? price - sl_points * _Point : price + sl_points * _Point;
   
   if(signal == 1)
      trade.Buy(lots, _Symbol, price, sl, 0, "Scalp_Buy");
   else
      trade.Sell(lots, _Symbol, price, sl, 0, "Scalp_Sell");
}

//+------------------------------------------------------------------+
//| Gestión activa (Alta Velocidad): BE, Parcial y Trailing          |
//+------------------------------------------------------------------+
void ManagePosition()
{
   MqlTick last_tick;
   if(!SymbolInfoTick(_Symbol, last_tick)) return;

   ulong  ticket = PositionGetInteger(POSITION_TICKET);
   double open   = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl     = PositionGetDouble(POSITION_SL);
   long   type   = PositionGetInteger(POSITION_TYPE);
   double vol    = PositionGetDouble(POSITION_VOLUME);
   
   double price  = (type == POSITION_TYPE_BUY) ? last_tick.bid : last_tick.ask;
   double profit_points = (type == POSITION_TYPE_BUY) ? (price - open) / _Point : (open - price) / _Point;
   
   double stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double min_dist = stops_level + 5 * _Point;

   // 1. BREAK EVEN CON PROFIT LOCK
   if(profit_points >= breakeven_points)
   {
      double lock_dist = be_lock_points * _Point;
      static datetime last_be_log = 0;

      if(type == POSITION_TYPE_BUY)
      {
         double target_be = NormalizeDouble(open + lock_dist, _Digits);
         if(sl < target_be) 
         {
            if(price > target_be + min_dist)
               trade.PositionModify(ticket, target_be, 0);
            else if(TimeCurrent() - last_be_log > 30) {
               Print("⚠️ BE bloqueado por el Broker (StopsLevel). Precio demasiado cerca del objetivo.");
               last_be_log = TimeCurrent();
            }
         }
      }
      else // SELL
      {
         double target_be = NormalizeDouble(open - lock_dist, _Digits);
         if((sl > target_be || sl == 0)) 
         {
            if(price < target_be - min_dist)
               trade.PositionModify(ticket, target_be, 0);
            else if(TimeCurrent() - last_be_log > 30) {
               Print("⚠️ BE bloqueado por el Broker (StopsLevel). Precio demasiado cerca del objetivo.");
               last_be_log = TimeCurrent();
            }
         }
      }
   }
   
   // 2. CIERRE PARCIAL
   if(!is_partial_closed && profit_points >= partial_points)
   {
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double close_vol = NormalizeDouble(vol * partial_percent, 2);
      close_vol = MathFloor(close_vol / step) * step;
      
      if(close_vol >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
      {
         if(trade.PositionClosePartial(ticket, close_vol))
            is_partial_closed = true;
      }
   }
   
   // 3. TRAILING STOP (Solo si supera el umbral trailing_start)
   if(profit_points >= trailing_start)
   {
      double dist = trailing_points * _Point;
      if(type == POSITION_TYPE_BUY)
      {
         double new_sl = NormalizeDouble(last_tick.bid - dist, _Digits);
         if(new_sl > sl + 2 * _Point)
            trade.PositionModify(ticket, new_sl, 0);
      }
      else
      {
         double new_sl = NormalizeDouble(last_tick.ask + dist, _Digits);
         if(new_sl < sl - 2 * _Point || sl == 0)
            trade.PositionModify(ticket, new_sl, 0);
      }
   }
}

//+------------------------------------------------------------------+
//| Cálculo de Lote basado en Riesgo Fijo                            |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl_dist)
{
   if(sl_dist <= 0) return 0;
   
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = balance * (risk_percent / 100.0);
   double tick_val   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tick_val <= 0 || tick_size <= 0) return 0;
   
   double point_value = tick_val / (tick_size / _Point);
   double lots = risk_money / (sl_dist * point_value);
   
   double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / step_lot) * step_lot;
   return MathMax(min_lot, MathMin(max_lot, lots));
}