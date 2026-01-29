//+------------------------------------------------------------------+
//|                                         BespojiMagic_Radar.mq4   |
//|                      べすぽじの魔術 - セットアップ検知（Radar）      |
//|                         Copyright 2026, Expert MQL4 Developer    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Expert MQL4 Developer"
#property link      ""
#property version   "2.01"
#property strict
#property indicator_chart_window
#property indicator_buffers 7

// インジケーターバッファ
double BuySignalBuffer[];      // Buffer 0: 買いシグナル（上向き矢印）
double SellSignalBuffer[];     // Buffer 1: 売りシグナル（下向き矢印）
double UpperBandBuffer[];      // Buffer 2: BB上限（+2σ）
double MiddleBandBuffer[];     // Buffer 3: BB中間（SMA）
double LowerBandBuffer[];      // Buffer 4: BB下限（-2σ）
double BreakUpStateBuffer[];   // Buffer 5: 買いセットアップ中（ブレイク済み）
double BreakDownStateBuffer[]; // Buffer 6: 売りセットアップ中（ブレイク済み）

//--- 入力パラメータ ---

// ボリンジャーバンド設定
input int    BB_Period = 21;                    // BB期間
input double BB_Deviation = 1.0;                // BB偏差
input int    BB_AppliedPrice = PRICE_CLOSE;     // 適用価格

// ブレイク検知設定
input int    Lookback_Period = 20;              // 高値・安値の判定期間
input int    Break_Validity = 20;               // ブレイク後の有効期限（足の本数）

// 1時間足MAフィルター設定
input bool   Enable_H1_Filter = false;          // H1 MAフィルター有効化
input int    H1_MA_Period = 21;                 // H1 MA期間

// 表示設定
input bool   Show_TP_SL_Lines = true;           // TP/SLライン表示
input bool   Show_Reference_Lines = true;       // 基準高値・安値ライン表示
input double SL_Offset_Pips = 2.0;              // SL位置のオフセット（pips）
input color  TP_Line_Color = clrAqua;           // TPライン色
input color  SL_Line_Color = clrRed;            // SLライン色
input color  Ref_High_Color = clrGray;          // 基準高値ライン色
input color  Ref_Low_Color = clrGray;           // 基準安値ライン色

// アラート設定
input bool   Enable_Sound_Alert = true;         // サウンドアラート
input bool   Enable_Mobile_Alert = false;       // モバイル通知

// 矢印表示設定
input color  Buy_Arrow_Color = clrLime;         // 買いシグナル矢印色
input color  Sell_Arrow_Color = clrRed;         // 売りシグナル矢印色
input int    Arrow_Size = 2;                    // 矢印サイズ

// ボリンジャーバンド表示設定
input color  BB_Upper_Color = clrDodgerBlue;    // BB上限線の色
input color  BB_Middle_Color = clrYellow;       // BB中間線の色
input color  BB_Lower_Color = clrDodgerBlue;    // BB下限線の色
input int    BB_Line_Width = 1;                 // BBライン幅

//--- グローバル変数（ブレイク状態管理）---
datetime last_break_up_time = 0;      // 最後の高値ブレイク時刻
datetime last_break_down_time = 0;    // 最後の安値ブレイク時刻

// アラート送信済み管理（重複防止）
datetime last_buy_alert_time = 0;
datetime last_sell_alert_time = 0;

// ラインの名前（管理用）
string buy_tp_line_name = "BespojiMagic_BuyTP";
string buy_sl_line_name = "BespojiMagic_BuySL";
string sell_tp_line_name = "BespojiMagic_SellTP";
string sell_sl_line_name = "BespojiMagic_SellSL";
string ref_high_line_name = "BespojiMagic_RefHigh";
string ref_low_line_name = "BespojiMagic_RefLow";

//+------------------------------------------------------------------+
//| カスタムインジケーター初期化関数                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BuySignalBuffer);
   SetIndexBuffer(1, SellSignalBuffer);
   SetIndexBuffer(2, UpperBandBuffer);
   SetIndexBuffer(3, MiddleBandBuffer);
   SetIndexBuffer(4, LowerBandBuffer);
   SetIndexBuffer(5, BreakUpStateBuffer);
   SetIndexBuffer(6, BreakDownStateBuffer);
   
   SetIndexStyle(0, DRAW_ARROW, EMPTY, Arrow_Size, Buy_Arrow_Color);
   SetIndexArrow(0, 233);
   SetIndexLabel(0, "Buy Signal");
   
   SetIndexStyle(1, DRAW_ARROW, EMPTY, Arrow_Size, Sell_Arrow_Color);
   SetIndexArrow(1, 234);
   SetIndexLabel(1, "Sell Signal");
   
   SetIndexStyle(2, DRAW_LINE, EMPTY, BB_Line_Width, BB_Upper_Color);
   SetIndexLabel(2, "BB Upper (+2sigma)");
   
   SetIndexStyle(3, DRAW_LINE, EMPTY, BB_Line_Width, BB_Middle_Color);
   SetIndexLabel(3, "BB Middle (SMA)");
   
   SetIndexStyle(4, DRAW_LINE, EMPTY, BB_Line_Width, BB_Lower_Color);
   SetIndexLabel(4, "BB Lower (-2sigma)");
   
   SetIndexStyle(5, DRAW_NONE);
   SetIndexLabel(5, "Buy Setup State");
   
   SetIndexStyle(6, DRAW_NONE);
   SetIndexLabel(6, "Sell Setup State");
   
   IndicatorShortName("Bespoji Magic Radar");
   
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteTPSLLines();
   ObjectDelete(0, ref_high_line_name);
   ObjectDelete(0, ref_low_line_name);
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
   if(rates_total < BB_Period + Lookback_Period) return(0);
   
   int start;
   if(prev_calculated == 0)
   {
      start = rates_total - 1;
      ArrayInitialize(BuySignalBuffer, EMPTY_VALUE);
      ArrayInitialize(SellSignalBuffer, EMPTY_VALUE);
      ArrayInitialize(BreakUpStateBuffer, 0.0);
      ArrayInitialize(BreakDownStateBuffer, 0.0);
   }
   else
   {
      start = rates_total - prev_calculated;
      if(start < 3) start = 3;
   }
   
   // Loop i >= 0 to include current forming bar for Trigger synchronization
   for(int i = start; i >= 0; i--)
   {
      CalculateBollingerBands(i);
      
      BuySignalBuffer[i] = EMPTY_VALUE;
      SellSignalBuffer[i] = EMPTY_VALUE;
      BreakUpStateBuffer[i] = 0.0;
      BreakDownStateBuffer[i] = 0.0;
      
      if(last_break_up_time != 0)
      {
         int break_bar = iBarShift(NULL, 0, last_break_up_time, false);
         if(break_bar >= 0 && (break_bar - i) <= Break_Validity)
         {
            BreakUpStateBuffer[i] = 1.0;
         }
      }
      
      if(last_break_down_time != 0)
      {
         int break_bar = iBarShift(NULL, 0, last_break_down_time, false);
         if(break_bar >= 0 && (break_bar - i) <= Break_Validity)
         {
            BreakDownStateBuffer[i] = 1.0;
         }
      }
      
      if (i > 0) // Actions for history/closed bars
      {
         DetectHighBreak(i, high);
         DetectLowBreak(i, low);
         GenerateBuySignal(i, open, high, low, close);
         GenerateSellSignal(i, open, high, low, close);
      }
      
      // 基準線の更新（最新の状態を表示）
      if (i == 0 && Show_Reference_Lines)
      {
         UpdateReferenceLines();
      }
   }
   
   if(prev_calculated > 0 && rates_total > prev_calculated)
   {
      CheckAndSendAlerts(1, time);
   }
   
   return(rates_total);
}

void CalculateBollingerBands(int shift)
{
   double sma = iMA(NULL, 0, BB_Period, 0, MODE_SMA, BB_AppliedPrice, shift);
   double sum = 0.0;
   for(int j = 0; j < BB_Period; j++)
   {
      double price = iClose(NULL, 0, shift + j);
      sum += MathPow(price - sma, 2);
   }
   double stddev = MathSqrt(sum / BB_Period);
   MiddleBandBuffer[shift] = sma;
   UpperBandBuffer[shift] = sma + (BB_Deviation * stddev);
   LowerBandBuffer[shift] = sma - (BB_Deviation * stddev);
}

void DetectHighBreak(int shift, const double &high[])
{
   if(shift + Lookback_Period + 1 >= Bars) return;
   double highest = iHigh(NULL, 0, iHighest(NULL, 0, MODE_HIGH, Lookback_Period, shift + 2));
   if(high[shift] > highest) last_break_up_time = iTime(NULL, 0, shift);
}

void DetectLowBreak(int shift, const double &low[])
{
   if(shift + Lookback_Period + 1 >= Bars) return;
   double lowest = iLow(NULL, 0, iLowest(NULL, 0, MODE_LOW, Lookback_Period, shift + 2));
   if(low[shift] < lowest) last_break_down_time = iTime(NULL, 0, shift);
}

void GenerateBuySignal(int shift, const double &open[], const double &high[], const double &low[], const double &close[])
{
   if(last_break_up_time == 0) return;
   int break_bar = iBarShift(NULL, 0, last_break_up_time, false);
   if(break_bar < 0 || (break_bar - shift) > Break_Validity) return;
   if(low[shift] > LowerBandBuffer[shift]) return;
   if(close[shift] <= open[shift]) return;
   
   if(Enable_H1_Filter)
   {
      double h1_ma = iMA(NULL, PERIOD_H1, H1_MA_Period, 0, MODE_SMA, PRICE_CLOSE, 0);
      if(close[shift] <= h1_ma) return;
   }
   
   BuySignalBuffer[shift] = low[shift] - (3.0 * Point * (Digits % 2 == 1 ? 10 : 1));
   last_break_up_time = 0;
   if(Show_TP_SL_Lines && shift == 1) DrawBuyTPSLLines(shift, low, close);
}

void GenerateSellSignal(int shift, const double &open[], const double &high[], const double &low[], const double &close[])
{
   if(last_break_down_time == 0) return;
   int break_bar = iBarShift(NULL, 0, last_break_down_time, false);
   if(break_bar < 0 || (break_bar - shift) > Break_Validity) return;
   if(high[shift] < UpperBandBuffer[shift]) return;
   if(close[shift] >= open[shift]) return;
   
   if(Enable_H1_Filter)
   {
      double h1_ma = iMA(NULL, PERIOD_H1, H1_MA_Period, 0, MODE_SMA, PRICE_CLOSE, 0);
      if(close[shift] >= h1_ma) return;
   }
   
   SellSignalBuffer[shift] = high[shift] + (3.0 * Point * (Digits % 2 == 1 ? 10 : 1));
   last_break_down_time = 0;
   if(Show_TP_SL_Lines && shift == 1) DrawSellTPSLLines(shift, high, close);
}

void CheckAndSendAlerts(int shift, const datetime &time[])
{
   if(BuySignalBuffer[shift] != EMPTY_VALUE && last_buy_alert_time != time[shift])
   {
      SendSignalAlert("Buy Signal", shift, time);
      last_buy_alert_time = time[shift];
   }
   if(SellSignalBuffer[shift] != EMPTY_VALUE && last_sell_alert_time != time[shift])
   {
      SendSignalAlert("Sell Signal", shift, time);
      last_sell_alert_time = time[shift];
   }
}

void SendSignalAlert(string signal_type, int bar, const datetime &time[])
{
   string message = "Bespoji Magic: " + signal_type + " Triggered! | " + Symbol() + " | " + TimeToString(time[bar], TIME_DATE|TIME_MINUTES);
   if(Enable_Sound_Alert) Alert(message);
   Print(message);
   if(Enable_Mobile_Alert) SendNotification(message);
}

void DrawBuyTPSLLines(int shift, const double &low[], const double &close[])
{
   DeleteTPSLLines();
   double pip_multiplier = (Digits % 2 == 1) ? 10.0 : 1.0;
   double sl_price = iLow(NULL, 0, iLowest(NULL, 0, MODE_LOW, Lookback_Period, shift + 1)) - (SL_Offset_Pips * Point * pip_multiplier);
   double tp_price = UpperBandBuffer[shift];
   ObjectCreate(0, buy_sl_line_name, OBJ_HLINE, 0, 0, sl_price); ObjectSetInteger(0, buy_sl_line_name, OBJPROP_COLOR, SL_Line_Color);
   ObjectCreate(0, buy_tp_line_name, OBJ_HLINE, 0, 0, tp_price); ObjectSetInteger(0, buy_tp_line_name, OBJPROP_COLOR, TP_Line_Color);
}

void DrawSellTPSLLines(int shift, const double &high[], const double &close[])
{
   DeleteTPSLLines();
   double pip_multiplier = (Digits % 2 == 1) ? 10.0 : 1.0;
   double sl_price = iHigh(NULL, 0, iHighest(NULL, 0, MODE_HIGH, Lookback_Period, shift + 1)) + (SL_Offset_Pips * Point * pip_multiplier);
   double tp_price = LowerBandBuffer[shift];
   ObjectCreate(0, sell_sl_line_name, OBJ_HLINE, 0, 0, sl_price); ObjectSetInteger(0, sell_sl_line_name, OBJPROP_COLOR, SL_Line_Color);
   ObjectCreate(0, sell_tp_line_name, OBJ_HLINE, 0, 0, tp_price); ObjectSetInteger(0, sell_tp_line_name, OBJPROP_COLOR, TP_Line_Color);
}

void DeleteTPSLLines()
{
   ObjectDelete(0, buy_tp_line_name); ObjectDelete(0, buy_sl_line_name);
   ObjectDelete(0, sell_tp_line_name); ObjectDelete(0, sell_sl_line_name);
}

//+------------------------------------------------------------------+
//| 基準高値・安値ラインの更新                                         |
//+------------------------------------------------------------------+
void UpdateReferenceLines()
{
   // 過去N本の最高値を取得（現在のバーとひとつ前のバーは除外して計算しているロジックに合わせる）
   double ref_high = iHigh(NULL, 0, iHighest(NULL, 0, MODE_HIGH, Lookback_Period, 2));
   double ref_low = iLow(NULL, 0, iLowest(NULL, 0, MODE_LOW, Lookback_Period, 2));

   // 高値ライン
   if(ObjectFind(0, ref_high_line_name) < 0)
   {
      ObjectCreate(0, ref_high_line_name, OBJ_HLINE, 0, 0, ref_high);
      ObjectSetInteger(0, ref_high_line_name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, ref_high_line_name, OBJPROP_WIDTH, 1);
   }
   ObjectMove(0, ref_high_line_name, 0, 0, ref_high);
   ObjectSetInteger(0, ref_high_line_name, OBJPROP_COLOR, Ref_High_Color);
   ObjectSetString(0, ref_high_line_name, OBJPROP_TEXT, " Ref High");

   // 安値ライン
   if(ObjectFind(0, ref_low_line_name) < 0)
   {
      ObjectCreate(0, ref_low_line_name, OBJ_HLINE, 0, 0, ref_low);
      ObjectSetInteger(0, ref_low_line_name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, ref_low_line_name, OBJPROP_WIDTH, 1);
   }
   ObjectMove(0, ref_low_line_name, 0, 0, ref_low);
   ObjectSetInteger(0, ref_low_line_name, OBJPROP_COLOR, Ref_Low_Color);
   ObjectSetString(0, ref_low_line_name, OBJPROP_TEXT, " Ref Low");
}
